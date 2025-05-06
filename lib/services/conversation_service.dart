// Service to handle fetching and caching conversation summaries
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/conversation_summary_model.dart';
import '../models/message_model.dart'; // Need Message model for processing
import '../services/database_helper.dart';
import '../services/profile_service.dart';
import 'dart:developer';

class ConversationService {
  final SupabaseClient _supabase;
  final DatabaseHelper _dbHelper;
  final ProfileService _profileService;

  ConversationService({
    SupabaseClient? supabaseClient,
    DatabaseHelper? dbHelper,
    ProfileService? profileService,
  })  : _supabase = supabaseClient ?? Supabase.instance.client,
        _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _profileService = profileService ?? ProfileService();

  // Fetches summaries, attempts network first, falls back to cache.
  Future<List<ConversationSummary>> getSummaries(String currentUserId,
      {bool forceRefresh = false}) async {
    log('[ConversationService] getSummaries called for user: $currentUserId, forceRefresh: $forceRefresh');

    // Try loading from cache first ONLY if not forcing a refresh.
    if (!forceRefresh) {
      try {
        final cachedSummaries = await _loadSummariesFromCache();
        if (cachedSummaries.isNotEmpty) {
          log('[ConversationService] Returning ${cachedSummaries.length} summaries from cache initially.');
          // Return cached data immediately, network fetch happens in background (or if forced)
          // Let the caller (Provider) handle updating UI with network data later.
          // This provides a faster initial load.
          // NOTE: This pattern might change if the Provider needs combined results.
          // For now, just return cache if available when not refreshing.
          return cachedSummaries;
        }
      } catch (e) {
        log('[ConversationService] Error loading summaries from cache initially: $e');
        // Continue to network fetch
      }
    }

    // --- Network Fetch Attempt ---
    try {
      log('[ConversationService] Fetching summaries from network...');
      // 1. Fetch raw messages from network (logic from MessageProvider)
      final messagesResponse = await _supabase
          .from('messages')
          .select('*') // Select all fields needed for Message.fromJson
          .or('from_user_id.eq.$currentUserId,to_user_id.eq.$currentUserId')
          .order('created_at', ascending: false)
          .limit(200); // Limit can be adjusted

      final List<dynamic> messagesData =
          messagesResponse as List<dynamic>? ?? [];
      log('[ConversationService] Fetched ${messagesData.length} raw messages from network.');

      if (messagesData.isEmpty) {
        log('[ConversationService] Network returned no messages. Clearing cache and returning empty list.');
        await _dbHelper
            .clearConversationSummaries(); // Clear cache if network is empty
        return [];
      }

      // 2. Extract user IDs and fetch profiles (logic from MessageProvider)
      final Set<String> userIds = {};
      for (var msgData in messagesData) {
        userIds.add(msgData['from_user_id'] as String);
        userIds.add(msgData['to_user_id'] as String);
      }
      userIds.remove(currentUserId);

      Map<String, String> displayNameMap = {};
      if (userIds.isNotEmpty) {
        log('[ConversationService] Prefetching ${userIds.length} profiles for summaries.');
        await _profileService.prefetchDisplayNames(userIds);
        for (final userId in userIds) {
          displayNameMap[userId] =
              await _profileService.getDisplayName(userId) ?? 'Unknown User';
        }
        log('[ConversationService] Finished fetching profiles for summaries.');
      }

      // 3. Process messages into summaries (logic from MessageProvider)
      final Map<String, Message> latestMessages = {};
      for (var msgData in messagesData) {
        try {
          final message = Message.fromJson(msgData as Map<String, dynamic>);
          final String otherUserId = (message.fromUserId == currentUserId)
              ? message.toUserId
              : message.fromUserId;
          // Ensure otherUserId is valid before proceeding
          if (otherUserId.isNotEmpty) {
            if (!latestMessages.containsKey(otherUserId) ||
                message.createdAt
                    .isAfter(latestMessages[otherUserId]!.createdAt)) {
              latestMessages[otherUserId] = message;
            }
          } else {
            log('[ConversationService] Warning: Message ${msgData['message_id']} has invalid otherUserId.');
          }
        } catch (e) {
          log('[ConversationService] Error processing message data into Message object: $e - Data: $msgData');
        }
      }

      final List<ConversationSummary> networkSummaries =
          latestMessages.entries.map((entry) {
        final otherUserId = entry.key;
        final latestMessage = entry.value;
        final otherUserName = displayNameMap[otherUserId] ?? 'Unknown User';
        String displayText;
        final bool hasText = latestMessage.messageText != null &&
            latestMessage.messageText!.trim().isNotEmpty;
        final bool hasImage = latestMessage.messageMedia?['type'] == 'image';

        if (hasImage && !hasText) {
          displayText = '[Image]';
        } else if (hasText) {
          displayText = latestMessage.messageText!;
        } else {
          // Includes case where media is present but not image, or no text/image
          displayText =
              '[Media Message]'; // Or more specific based on media type if needed
        }

        return ConversationSummary(
          otherUserId: otherUserId,
          otherUserDisplayName: otherUserName,
          lastMessageText: displayText,
          lastMessageTimestamp: latestMessage.createdAt,
          lastMessageFromUserId: latestMessage.fromUserId,
        );
      }).toList();

      // Sort summaries by timestamp descending
      networkSummaries.sort(
          (a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));

      // 4. Cache the fetched summaries
      try {
        await _dbHelper.batchUpsertConversationSummaries(networkSummaries);
        log('[ConversationService] Cached ${networkSummaries.length} summaries from network.');
      } catch (cacheError) {
        log('[ConversationService] Error caching summaries from network: $cacheError');
        // Proceed with returning network data anyway
      }

      return networkSummaries;
    } catch (e, stacktrace) {
      log('[ConversationService] Error fetching summaries from network: $e',
          error: e, stackTrace: stacktrace);
      // Network failed, try returning cache as a fallback if not already returned
      if (forceRefresh) {
        // If refresh was forced, cache wasn't returned earlier
        try {
          final cachedSummaries = await _loadSummariesFromCache();
          if (cachedSummaries.isNotEmpty) {
            log('[ConversationService] Network failed, returning ${cachedSummaries.length} summaries from cache as fallback.');
            return cachedSummaries;
          }
        } catch (cacheError) {
          log('[ConversationService] Error loading fallback summaries from cache: $cacheError');
        }
      }
      // If cache was already returned or fallback failed, rethrow or return empty
      // Rethrowing allows the provider to handle the error state more explicitly.
      throw Exception('Failed to fetch or cache summaries: $e');
    }
  }

  // Helper to load summaries from cache (moved from MessageProvider)
  Future<List<ConversationSummary>> _loadSummariesFromCache() async {
    log('[ConversationService] Loading summaries from cache...');
    // Error handling should be done here or let it bubble up
    final cachedSummaries = await _dbHelper.getCachedConversationSummaries();
    log('[ConversationService] Found ${cachedSummaries.length} summaries in cache.');
    return cachedSummaries;
  }

  // Optional: Method to clear cache (e.g., on logout)
  Future<void> clearSummaryCache() async {
    try {
      await _dbHelper.clearConversationSummaries();
      log('[ConversationService] Cleared conversation summary cache.');
    } catch (e) {
      log('[ConversationService] Error clearing summary cache: $e');
    }
  }
}
