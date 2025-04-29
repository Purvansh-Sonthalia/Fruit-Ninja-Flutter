import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer'; // For logging
import 'dart:collection'; // For SplayTreeMap
import '../models/message_model.dart';
import '../models/conversation_summary_model.dart'; // Import the new model
import '../services/auth_service.dart'; // To get the current user ID
import 'dart:convert'; // For jsonEncode
import 'package:http/http.dart' as http; // For HTTP requests
import 'package:flutter_dotenv/flutter_dotenv.dart'; // For environment variables
import '../services/database_helper.dart';
import 'package:uuid/uuid.dart'; // For generating temporary local IDs

class MessageProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService; // Inject AuthService
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = Uuid(); // UUID generator

  // Keep track of offline status
  bool _isOffline = false;

  // Conversation summaries state
  List<ConversationSummary> _conversationSummaries = [];
  bool _isLoadingSummaries = false;
  bool _hasErrorSummaries = false;
  String _errorSummariesMessage = '';

  // State for messages within a specific chat
  Map<String, List<Message>> _chatMessages = {}; // Key: otherUserId
  Map<String, bool> _isLoadingChat = {};
  Map<String, bool> _hasErrorChat = {}; // Separate error state per chat
  Map<String, String> _errorChatMessage = {}; // Separate error message per chat
  Map<String, DateTime?> _latestMessageTimestampPerChat =
      {}; // Added: Track latest timestamp per chat
  Map<String, Message?> _fetchedSingleMessages =
      {}; // Added: Cache for single message lookups

  // Constructor requires AuthService
  MessageProvider(this._authService);

  // Getters for UI
  List<ConversationSummary> get conversationSummaries => _conversationSummaries;
  bool get isLoadingSummaries => _isLoadingSummaries;
  bool get hasErrorSummaries => _hasErrorSummaries;
  String get errorSummariesMessage => _errorSummariesMessage;
  @Deprecated('Use isLoadingSummaries instead')
  bool get isLoading => _isLoadingSummaries;
  @Deprecated('Use hasErrorSummaries instead')
  bool get hasError => _hasErrorSummaries;
  @Deprecated('Use errorSummariesMessage instead')
  String get errorMessage => _errorSummariesMessage;

  // Getter for specific chat messages
  List<Message> getMessagesForChat(String otherUserId) =>
      _chatMessages[otherUserId] ?? [];
  bool isLoadingChat(String otherUserId) =>
      _isLoadingChat[otherUserId] ?? false;
  bool chatHasError(String otherUserId) => _hasErrorChat[otherUserId] ?? false;
  String getChatErrorMessage(String otherUserId) =>
      _errorChatMessage[otherUserId] ?? '';
  bool get isOffline => _isOffline; // Expose offline status

  // Fetch conversation summaries with caching
  Future<void> fetchMessages({bool forceRefresh = false}) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      log('[MessageProvider] User not logged in. Cannot fetch summaries.');
      _setSummariesError('User not logged in.');
      notifyListeners(); // Notify immediately for login error
      return;
    }

    if (_isLoadingSummaries) return; // Prevent concurrent fetches

    _isLoadingSummaries = true;
    _isOffline = false; // Assume online
    _hasErrorSummaries = false;
    _errorSummariesMessage = '';

    // Load from cache first if not refreshing and state is empty
    if (!forceRefresh && _conversationSummaries.isEmpty) {
      await _loadSummariesFromCache();
    }
    // If forcing refresh, clear state visually now
    if (forceRefresh) {
      _conversationSummaries.clear();
    }
    notifyListeners(); // Notify UI about loading state / cached data / cleared state

    // Attempt network fetch
    try {
      log('[MessageProvider] Fetching summaries from network...');
      // 1. Fetch messages from network
      final messagesResponse = await _supabase
          .from('messages')
          .select('*')
          .or('from_user_id.eq.$currentUserId,to_user_id.eq.$currentUserId')
          .order('created_at', ascending: false)
          .limit(200); // Fetch a decent number to generate summaries

      final List<dynamic> messagesData = messagesResponse as List<dynamic>;
      log('[MessageProvider] Fetched ${messagesData.length} raw messages from network for summary generation.');

      // --- Process messages and profiles (requires network) ---
      if (messagesData.isEmpty) {
        _conversationSummaries = []; // Clear if network returns none
        await _dbHelper.clearConversationSummaries(); // Clear cache too
        _isLoadingSummaries = false;
        notifyListeners();
        return;
      }

      final Set<String> userIds = {};
      for (var msgData in messagesData) {
        userIds.add(msgData['from_user_id'] as String);
        userIds.add(msgData['to_user_id'] as String);
      }
      userIds.remove(currentUserId);

      Map<String, String> displayNameMap = {};
      if (userIds.isNotEmpty) {
        final profilesResponse = await _supabase
            .from('profiles')
            .select('user_id, display_name')
            .inFilter('user_id', userIds.toList());
        final List<dynamic> profilesData = profilesResponse as List<dynamic>;
        displayNameMap = {
          for (var profileData in profilesData)
            profileData['user_id'] as String:
                profileData['display_name'] as String? ?? 'Anonymous'
        };
      }

      final Map<String, Message> latestMessages = {};
      for (var msgData in messagesData) {
        final message = Message.fromJson(msgData as Map<String, dynamic>);
        final String otherUserId = (message.fromUserId == currentUserId)
            ? message.toUserId
            : message.fromUserId;
        if (!latestMessages.containsKey(otherUserId) ||
            message.createdAt.isAfter(latestMessages[otherUserId]!.createdAt)) {
          latestMessages[otherUserId] = message;
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
          displayText = '[Media Message]';
        }

        return ConversationSummary(
          otherUserId: otherUserId,
          otherUserDisplayName: otherUserName,
          lastMessageText: displayText,
          lastMessageTimestamp: latestMessage.createdAt,
          lastMessageFromUserId: latestMessage.fromUserId,
        );
      }).toList();

      networkSummaries.sort(
          (a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));
      // --- End processing ---

      // Update state and cache
      _conversationSummaries = networkSummaries;
      await _dbHelper.batchUpsertConversationSummaries(networkSummaries);
      log('[MessageProvider] Updated and cached ${_conversationSummaries.length} summaries from network.');

      _isLoadingSummaries = false;
      _hasErrorSummaries = false;
    } catch (e, stacktrace) {
      log('[MessageProvider] Error fetching summaries from network: $e',
          error: e, stackTrace: stacktrace);
      _isOffline = true; // Assume offline on error
      _setSummariesError(
          'Failed to load conversations. Using cached data if available.');
      // Keep cached data if already loaded and refresh wasn't forced
      if (_conversationSummaries.isEmpty) {
        await _loadSummariesFromCache(); // Try loading cache if network failed and state is empty
        if (_conversationSummaries.isEmpty) {
          _errorSummariesMessage =
              'Failed to load conversations. No cached data.';
        }
      }
    } finally {
      _isLoadingSummaries = false;
      if (hasListeners) {
        notifyListeners();
      }
    }
  }

  // Helper to load summaries from cache
  Future<void> _loadSummariesFromCache() async {
    try {
      log('[MessageProvider] Loading summaries from cache...');
      final cachedSummaries = await _dbHelper.getCachedConversationSummaries();
      if (cachedSummaries.isNotEmpty) {
        _conversationSummaries = cachedSummaries;
        log('[MessageProvider] Loaded ${_conversationSummaries.length} summaries from cache.');
        // Don't notify here, let the caller do it.
      } else {
        log('[MessageProvider] No summaries found in cache.');
      }
    } catch (e) {
      log('[MessageProvider] Error loading summaries from cache: $e');
      _setSummariesError('Error loading cached conversations.');
    }
  }

  // Helper to set summary error state
  void _setSummariesError(String message) {
    _isLoadingSummaries = false; // Ensure loading is false on error
    _hasErrorSummaries = true;
    _errorSummariesMessage = message;
    // Don't clear summaries here, keep cache if available
    // Caller should notify
  }

  // Fetch messages for a specific chat with caching
  Future<void> fetchMessagesForChat(String otherUserId) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      _setChatError(otherUserId, 'User not logged in.');
      notifyListeners(); // Notify immediately
      return;
    }

    if (_isLoadingChat[otherUserId] ?? false)
      return; // Prevent concurrent fetches

    _isLoadingChat[otherUserId] = true;
    _isOffline = false; // Assume online
    _hasErrorChat[otherUserId] = false;
    _errorChatMessage[otherUserId] = '';
    // Don't clear network timestamp here, polling might need it

    // Load from cache first if chat messages aren't already loaded
    if ((_chatMessages[otherUserId] ?? []).isEmpty) {
      await _loadMessagesForChatFromCache(otherUserId, currentUserId);
    }
    notifyListeners(); // Notify UI about loading state / cached data

    // Attempt network fetch
    try {
      log('[MessageProvider] Fetching initial messages for chat $otherUserId from network...');
      final response = await _supabase
          .from('messages')
          .select('*')
          .or('and(from_user_id.eq.$currentUserId,to_user_id.eq.$otherUserId),and(from_user_id.eq.$otherUserId,to_user_id.eq.$currentUserId)')
          .order('created_at', ascending: false)
          .limit(100);

      final List<dynamic> messagesData = response as List<dynamic>;
      log('[MessageProvider] Fetched ${messagesData.length} initial messages for chat $otherUserId from network.');

      final List<Message> networkMessages = messagesData
          .map((msgData) => Message.fromJson(msgData as Map<String, dynamic>))
          .toList();

      // Update state and cache
      _chatMessages[otherUserId] = networkMessages;
      await _dbHelper.batchUpsertMessages(networkMessages);
      log('[MessageProvider] Updated and cached ${networkMessages.length} messages for chat $otherUserId.');

      // Update latest timestamp for polling
      if (networkMessages.isNotEmpty) {
        _latestMessageTimestampPerChat[otherUserId] =
            networkMessages.first.createdAt;
        log('[MessageProvider] Stored latest network timestamp for chat $otherUserId: ${_latestMessageTimestampPerChat[otherUserId]}');
      } else {
        // If network returns no messages, clear the timestamp
        _latestMessageTimestampPerChat.remove(otherUserId);
        log('[MessageProvider] Cleared timestamp for chat $otherUserId as network returned empty.');
      }

      _isLoadingChat[otherUserId] = false;
      _hasErrorChat[otherUserId] = false;
    } catch (e, stacktrace) {
      log('[MessageProvider] Error fetching initial chat messages from network for $otherUserId: $e',
          error: e, stackTrace: stacktrace);
      _isOffline = true; // Assume offline
      _setChatError(otherUserId,
          'Failed to load messages. Using cached data if available.');
      // Keep cached data if already loaded
      if ((_chatMessages[otherUserId] ?? []).isEmpty) {
        await _loadMessagesForChatFromCache(
            otherUserId, currentUserId); // Try reloading cache
        if ((_chatMessages[otherUserId] ?? []).isEmpty) {
          _errorChatMessage[otherUserId] =
              'Failed to load messages. No cached data.';
        }
      }
    } finally {
      _isLoadingChat[otherUserId] = false;
      if (hasListeners) {
        notifyListeners();
      }
    }
  }

  // Helper to load chat messages from cache
  Future<void> _loadMessagesForChatFromCache(
      String otherUserId, String currentUserId) async {
    try {
      log('[MessageProvider] Loading messages for chat $otherUserId from cache...');
      final cachedMessages = await _dbHelper
          .getCachedMessagesForChat(otherUserId, currentUserId, limit: 100);
      if (cachedMessages.isNotEmpty) {
        _chatMessages[otherUserId] = cachedMessages;
        log('[MessageProvider] Loaded ${cachedMessages.length} messages for chat $otherUserId from cache.');
        // Don't update network timestamp based on cache
      } else {
        log('[MessageProvider] No messages found in cache for chat $otherUserId.');
        // Ensure list exists even if empty from cache
        if (!_chatMessages.containsKey(otherUserId)) {
          _chatMessages[otherUserId] = [];
        }
      }
    } catch (e) {
      log('[MessageProvider] Error loading messages from cache for chat $otherUserId: $e');
      _setChatError(otherUserId, 'Error loading cached messages.');
    }
  }

  // Helper to set chat error state
  void _setChatError(String otherUserId, String message) {
    _isLoadingChat[otherUserId] = false; // Ensure loading is false on error
    _hasErrorChat[otherUserId] = true;
    _errorChatMessage[otherUserId] = message;
    // Don't clear messages here
    // Caller should notify
  }

  // Fetch only NEW messages for a specific conversation (Polling)
  // Caching Integration: Cache any *new* messages fetched from network.
  // Also deletes messages from cache if polling detects server-side deletion.
  // Does NOT rely on cache for determining what's new (uses network timestamp).
  Future<void> fetchNewMessagesForChat(String otherUserId) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) return;

    // Use the timestamp from the last successful *network* fetch/poll
    final lastKnownTimestamp = _latestMessageTimestampPerChat[otherUserId];
    if (lastKnownTimestamp == null) {
      log('[MessageProvider] No last known network timestamp for chat $otherUserId. Cannot poll for new messages.');
      // Don't poll if we haven't successfully fetched initial messages from network yet.
      // This prevents polling based on potentially stale cache timestamps.
      return;
    }

    // log('[MessageProvider] Polling for new messages in chat $otherUserId since $lastKnownTimestamp');

    try {
      // --- Query 1: Fetch NEW full messages from NETWORK ---
      final newMessagesResponse = await _supabase
          .from('messages')
          .select('*')
          .or(
              'and(from_user_id.eq.$currentUserId,to_user_id.eq.$otherUserId),and(from_user_id.eq.$otherUserId,to_user_id.eq.$currentUserId)')
          .gt(
              'created_at',
              lastKnownTimestamp
                  .toIso8601String()) // Fetch messages strictly newer than last network sync
          .order('created_at',
              ascending: true); // Fetch oldest new messages first

      final List<dynamic> newMessagesData =
          newMessagesResponse as List<dynamic>;
      DateTime? latestTimestampInNewBatch;
      final List<Message> newNetworkMessages = newMessagesData.map((msgData) {
        final message = Message.fromJson(msgData as Map<String, dynamic>);
        // Track the latest timestamp from this new batch
        if (latestTimestampInNewBatch == null ||
            message.createdAt.isAfter(latestTimestampInNewBatch!)) {
          latestTimestampInNewBatch = message.createdAt;
        }
        return message;
      }).toList();

      // --- Query 2: Fetch RECENT message IDs from NETWORK (to detect deletions) ---
      const int recentMessageLimit = 100; // How many recent messages to check
      final recentIdsResponse = await _supabase
          .from('messages')
          .select('message_id') // Select only IDs
          .or('and(from_user_id.eq.$currentUserId,to_user_id.eq.$otherUserId),and(from_user_id.eq.$otherUserId,to_user_id.eq.$currentUserId)')
          .order('created_at', ascending: false) // Get the most recent ones
          .limit(recentMessageLimit);

      final List<dynamic> recentIdsData = recentIdsResponse as List<dynamic>;
      final Set<String> recentServerIds =
          recentIdsData.map((data) => data['message_id'] as String).toSet();

      // --- Compare local state with server state ---
      // Get current messages from memory (which should reflect cache + optimistic updates)
      final List<Message> currentLocalMessages =
          List<Message>.from(_chatMessages[otherUserId] ?? []);
      final Set<String> currentLocalIds =
          currentLocalMessages.map((m) => m.messageId).toSet();

      // Identify deleted messages (present locally, but not in recent server IDs)
      final Set<String> deletedIds =
          currentLocalIds.difference(recentServerIds);
      // Identify truly new messages (fetched in query 1, but not already present locally)
      final List<Message> trulyNewMessages = newNetworkMessages
          .where(
              (newMessage) => !currentLocalIds.contains(newMessage.messageId))
          .toList();

      bool changed = false;
      List<Message> updatedMessages = currentLocalMessages;

      // Apply deletions if any found
      if (deletedIds.isNotEmpty) {
        log('[MessageProvider] Detected ${deletedIds.length} deleted messages in chat $otherUserId via polling: ${deletedIds.join(", ")}');
        updatedMessages = updatedMessages
            .where((msg) => !deletedIds.contains(msg.messageId))
            .toList();
        changed = true;
        // --- Also delete from cache (fire and forget is okay here) ---
        deletedIds.forEach((id) async {
          try {
            await _dbHelper.deleteMessage(id);
          } catch (e) {
            log('[MessageProvider] Error deleting message $id from cache during poll: $e');
          }
        });
        // -----------------------------------------------------------
      }

      // Apply additions if any found
      if (trulyNewMessages.isNotEmpty) {
        log('[MessageProvider] Applying ${trulyNewMessages.length} new messages to chat $otherUserId via polling.');
        updatedMessages.insertAll(0, trulyNewMessages); // Prepend new messages
        changed = true;

        // --- Cache the newly fetched messages ---
        try {
          await _dbHelper.batchUpsertMessages(trulyNewMessages);
        } catch (e) {
          log('[MessageProvider] Error caching new messages for chat $otherUserId during poll: $e');
        }
        // ------------------------------------

        // Update the latest known *network* timestamp only if new messages were actually added
        if (latestTimestampInNewBatch != null) {
          // Make sure the timestamp only moves forward
          if (_latestMessageTimestampPerChat[otherUserId] == null ||
              latestTimestampInNewBatch!
                  .isAfter(_latestMessageTimestampPerChat[otherUserId]!)) {
            _latestMessageTimestampPerChat[otherUserId] =
                latestTimestampInNewBatch;
            log('[MessageProvider] Updated latest network timestamp for chat $otherUserId via polling: ${_latestMessageTimestampPerChat[otherUserId]}');
          }
        }
      }

      // --- Update state and notify if changes occurred ---
      if (changed) {
        _chatMessages[otherUserId] = updatedMessages;
        notifyListeners();
        log('[MessageProvider] Notified listeners for chat $otherUserId due to polling changes.');
      }
      // Reset offline flag if polling succeeds
      _isOffline = false;
    } on PostgrestException catch (e) {
      log('[MessageProvider] PostgrestException polling chat messages $otherUserId: ${e.message}',
          error: e);
      _isOffline = true;
      // Don't set chat error on polling failure, just log it.
      // Chat screen will continue show cached data if available.
    } catch (e, stacktrace) {
      log('[MessageProvider] Generic error polling chat messages $otherUserId: $e',
          error: e, stackTrace: stacktrace);
      _isOffline = true;
      // Also don't set error here
    }
    // No finally/notifyListeners here, only notify if there were actual updates.
  }

  // Send message with optimistic caching
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
    String? parentMessageId,
    Map<String, dynamic>? media,
  }) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      log('[MessageProvider] Cannot send message: User not logged in.');
      _setChatError(toUserId, 'Cannot send message: Not logged in.');
      notifyListeners(); // Notify UI about the error
      return false;
    }

    log('[MessageProvider] Preparing to send message to $toUserId...');

    // 1. Create optimistic message with temporary local ID
    final tempMessageId = 'local_${_uuid.v4()}';
    final messageTimestamp = DateTime.now();
    final optimisticMessage = Message(
      messageId: tempMessageId, // Use temporary ID
      createdAt: messageTimestamp,
      fromUserId: currentUserId,
      toUserId: toUserId,
      messageText: text.trim(),
      messageMedia: media,
      parentMessageId: parentMessageId,
      // Add temporary local status if needed for UI differentiation (e.g., isPending field)
    );

    // 2. Add optimistic message to local state & cache immediately
    final List<Message> currentMessages =
        List<Message>.from(_chatMessages[toUserId] ?? []);
    currentMessages.insert(
        0, optimisticMessage); // Add to beginning (since list is reversed)
    _chatMessages[toUserId] = currentMessages;
    _setChatError(toUserId, ''); // Clear previous errors for this chat
    notifyListeners(); // Update UI immediately with optimistic message

    try {
      await _dbHelper.batchUpsertMessages([optimisticMessage]);
      log('[MessageProvider] Optimistically cached message $tempMessageId.');
    } catch (e) {
      log('[MessageProvider] Error caching optimistic message $tempMessageId: $e');
      // Proceed with network send anyway
    }

    // 3. Attempt to send message to network
    String? networkMessageId;
    try {
      log('[MessageProvider] Sending message $tempMessageId to network...');
      final response = await _supabase
          .from('messages')
          .insert({
            'from_user_id': currentUserId,
            'to_user_id': toUserId,
            'message_text': text.trim(),
            'message_media': media,
            'parent_message_id': parentMessageId,
            // Do NOT send the tempMessageId here, let DB generate the real one
          })
          .select('message_id, created_at')
          .single(); // Select real ID and timestamp

      networkMessageId = response['message_id'] as String?;
      final networkTimestampStr = response['created_at'] as String?;
      // Use network timestamp if available, otherwise fallback to local timestamp
      final networkTimestamp = networkTimestampStr != null
          ? DateTime.parse(networkTimestampStr)
          : messageTimestamp;

      if (networkMessageId == null) {
        throw Exception('Failed to retrieve message ID after network insert.');
      }
      log('[MessageProvider] Network send successful. Real ID: $networkMessageId');
      _isOffline = false; // Mark as online since send succeeded

      // 4. Update local message with real ID and timestamp
      final List<Message> updatedMessages =
          List<Message>.from(_chatMessages[toUserId] ?? []);
      final index =
          updatedMessages.indexWhere((msg) => msg.messageId == tempMessageId);
      Message confirmedMessage; // Declare outside if block

      if (index != -1) {
        // Create a new message instance with the network ID and timestamp
        confirmedMessage = Message(
          messageId: networkMessageId, // Use real network ID
          createdAt: networkTimestamp, // Use network timestamp
          fromUserId: optimisticMessage.fromUserId,
          toUserId: optimisticMessage.toUserId,
          messageText: optimisticMessage.messageText,
          messageMedia: optimisticMessage.messageMedia,
          parentMessageId: optimisticMessage.parentMessageId,
          // Add isPending: false here if using that status
        );
        updatedMessages[index] = confirmedMessage;
        _chatMessages[toUserId] = updatedMessages;

        // Update cache: Delete old temp one, insert new confirmed one
        try {
          await _dbHelper.deleteMessage(tempMessageId);
          await _dbHelper.batchUpsertMessages([confirmedMessage]);
          log('[MessageProvider] Updated cache for message $networkMessageId.');
        } catch (e) {
          log('[MessageProvider] Error updating cache for confirmed message $networkMessageId: $e');
        }

        // Update latest timestamp for polling
        _latestMessageTimestampPerChat[toUserId] = networkTimestamp;
        log('[MessageProvider] Updated latest network timestamp for chat $toUserId after send: $networkTimestamp');

        notifyListeners(); // Notify UI about the confirmed ID/timestamp
      } else {
        log('[MessageProvider] Warning: Optimistic message $tempMessageId not found locally after successful network send.');
        // Message might have been removed by polling, or other issue.
        // Create the confirmed message object anyway for caching.
        confirmedMessage = Message(
            messageId: networkMessageId,
            createdAt: networkTimestamp,
            fromUserId: currentUserId,
            toUserId: toUserId,
            messageText: text.trim(),
            messageMedia: media,
            parentMessageId: parentMessageId);
        // Ensure the confirmed message is in the cache
        try {
          await _dbHelper.batchUpsertMessages([confirmedMessage]);
          log('[MessageProvider] Ensured confirmed message $networkMessageId is in cache after not found locally.');
        } catch (e) {
          log('[MessageProvider] Error caching confirmed message $networkMessageId after not found locally: $e');
        }
        // Optionally trigger a full refresh for the chat if this happens often
        // fetchMessagesForChat(toUserId);
      }

      // 5. Send Notification (after successful send)
      final bool hasText = text.trim().isNotEmpty;
      final bool hasImage = media?['type'] == 'image';
      // Ensure networkMessageId is not null before sending notification
      if (networkMessageId != null) {
        await _sendMessageNotification(
          recipientUserId: toUserId,
          senderUserId: currentUserId,
          messageId: networkMessageId,
          messageText: text.trim(),
          hasText: hasText,
          hasImage: hasImage,
        );
      } else {
        log('[MessageProvider] Error: Cannot send notification, network message ID is null.');
      }

      // 6. Trigger summary refresh (non-blocking)
      // Use non-blocking call, don't await it here
      fetchMessages(forceRefresh: true);

      return true;
    } catch (e, stacktrace) {
      log('[MessageProvider] Error sending message $tempMessageId to network: $e',
          error: e, stackTrace: stacktrace);
      _isOffline = true;
      _setChatError(toUserId,
          'Failed to send message. Stored locally.'); // Updated error message
      // Keep optimistic message in UI and cache
      // Optionally, add a 'failed' status to the optimistic message for UI feedback
      notifyListeners();
      return false;
    }
  }

  // Helper to send notification
  Future<void> _sendMessageNotification({
    required String recipientUserId,
    required String senderUserId,
    required String messageId,
    required String messageText,
    required bool hasText,
    required bool hasImage,
  }) async {
    log('[Notification] Attempting to send message notification to $recipientUserId from $senderUserId for message $messageId');

    // Prevent self-notification (shouldn't happen in 1-on-1 chat, but good practice)
    if (recipientUserId == senderUserId) {
      log('[Notification] Sender and recipient are the same. No notification sent.');
      return;
    }

    // 1. Get Sender's Display Name
    String senderDisplayName = 'Someone'; // Default
    try {
      final profileResponse = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('user_id', senderUserId)
          .single();
      senderDisplayName =
          profileResponse['display_name'] as String? ?? 'Someone';
    } catch (e) {
      log('[Notification] Error fetching sender\'s display name ($senderUserId)',
          error: e);
      // Continue with default name
    }

    // 2. Access Backend URL
    final String? backendBaseUrl = dotenv.env['BACKEND_URL'];
    if (backendBaseUrl == null) {
      log('[Notification] Error: BACKEND_URL not found in .env file.');
      return;
    }
    // *** Use a specific endpoint for messages if possible ***
    // final String notificationUrl = '$backendBaseUrl/api/send-message-notification';
    final String notificationUrl =
        '$backendBaseUrl/api/send-like-notification'; // If reusing

    // 3. Prepare Payload
    // Dynamically set title and body based on content
    String title = senderDisplayName;
    String body;

    if (hasImage && !hasText) {
      // Image only
      body = '$senderDisplayName sent you an image.';
      // Optional: Keep title simpler or specific?
      // title = '$senderDisplayName sent an image';
    } else if (hasImage && hasText) {
      // Image and Text
      body = messageText.length > 80
          ? '${messageText.substring(0, 77)}... (Image)'
          : '$messageText (Image)';
      // title = '$senderDisplayName sent a message'; // Or keep as sender name
    } else {
      // Text only (or empty text reply - should we handle this case?)
      body = messageText.isEmpty
          ? '$senderDisplayName sent a reply.' // Placeholder for empty text reply?
          : (messageText.length > 100
              ? '${messageText.substring(0, 97)}...'
              : messageText);
    }

    // Adjust payload to match /api/send-like-notification expectations
    final payload = {
      'recipientUserId': recipientUserId,
      'likerUserId': senderUserId,
      'likerDisplayName': senderDisplayName,
      'postId': messageId, // Send messageId as postId
      'messageId': messageId,
      'messageText': messageText, // Send original text regardless of truncation
      'notificationType': 'message',
      'notificationTitle': title, // Use dynamic title
      'notificationBody': body, // Use dynamic body
      // Send flags if backend needs them (optional)
      // 'hasImage': hasImage,
      // 'hasText': hasText,
    };

    // 4. Send Request
    try {
      final response = await http.post(
        Uri.parse(notificationUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        log('[Notification] Message notification sent successfully via $notificationUrl.');
      } else {
        log('[Notification] Failed to send message notification via $notificationUrl. Status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e, stacktrace) {
      log('[Notification] Error sending message notification HTTP request',
          error: e, stackTrace: stacktrace);
    }
  }

  // Method to fetch a single message by ID (e.g., for reply context)
  Future<Message?> fetchSingleMessage(String messageId) async {
    // Check cache first
    if (_fetchedSingleMessages.containsKey(messageId)) {
      log('[MessageProvider] Returning cached single message: $messageId');
      return _fetchedSingleMessages[
          messageId]; // Return cached value (could be null)
    }

    log('[MessageProvider] Fetching single message from DB: $messageId');
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('message_id', messageId)
          .limit(1)
          .maybeSingle(); // Use maybeSingle to handle null gracefully

      if (response == null) {
        log('[MessageProvider] Single message $messageId not found.');
        _fetchedSingleMessages[messageId] =
            null; // Cache the null result (not found/error)
        return null;
      }

      log('[MessageProvider] Fetched single message successfully.');
      final message = Message.fromJson(response as Map<String, dynamic>);
      _fetchedSingleMessages[messageId] = message; // Cache the fetched message
      return message;
    } on PostgrestException catch (e) {
      log('[MessageProvider] PostgrestException fetching single message $messageId',
          error: e);
      _fetchedSingleMessages[messageId] =
          null; // Cache the null result (not found/error)
      return null;
    } catch (e, stacktrace) {
      log('[MessageProvider] Generic error fetching single message $messageId',
          error: e, stackTrace: stacktrace);
      _fetchedSingleMessages[messageId] = null; // Cache the null result (error)
      return null;
    }
  }

  // Delete message with cache update
  Future<bool> deleteMessage(String messageId, String otherUserId) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      log('[MessageProvider] Cannot delete message: User not logged in.');
      _setChatError(otherUserId, 'Cannot delete message: Not logged in.');
      notifyListeners();
      return false;
    }

    log('[MessageProvider] Attempting to delete message $messageId');

    // 1. Optimistic UI update: Remove from local list
    final List<Message> currentMessages =
        List<Message>.from(_chatMessages[otherUserId] ?? []);
    final originalLength = currentMessages.length;
    // Store the message being deleted in case we need to revert
    Message? messageToDelete = null;
    try {
      messageToDelete =
          currentMessages.firstWhere((msg) => msg.messageId == messageId);
    } catch (e) {
      // Handle case where messageId is not found - messageToDelete remains null
      log('[MessageProvider] Message $messageId not found locally for deletion (expected if already deleted).');
    }

    currentMessages.removeWhere((msg) => msg.messageId == messageId);
    _chatMessages[otherUserId] = currentMessages;
    // Determine if locally removed based on whether messageToDelete was found
    bool locallyRemoved = messageToDelete != null;

    if (locallyRemoved) {
      log('[MessageProvider] Locally removed message $messageId from chat $otherUserId.');
      notifyListeners(); // Update UI immediately
    } else {
      log('[MessageProvider] Message $messageId not found in local list for chat $otherUserId before delete.');
      // Still proceed with network/cache delete attempt
    }

    // 2. Attempt Network Delete
    bool networkDeleteSuccess = false;
    try {
      await _supabase
          .from('messages')
          .delete()
          .eq('message_id', messageId)
          .eq('from_user_id', currentUserId); // Authorization check

      log('[MessageProvider] Message $messageId deleted successfully from network.');
      networkDeleteSuccess = true;
      _isOffline = false; // Mark online if delete succeeds
    } catch (e, stacktrace) {
      log('[MessageProvider] Error deleting message $messageId from network',
          error: e, stackTrace: stacktrace);
      _isOffline = true;
      _setChatError(otherUserId, 'Failed to delete message.');
      // Revert local removal if network failed and message was found locally
      if (locallyRemoved && messageToDelete != null) {
        log('[MessageProvider] Reverting local deletion of $messageId due to network error.');
        // Find original index? Difficult. Just add it back to the start for now.
        currentMessages.insert(0, messageToDelete);
        _chatMessages[otherUserId] = currentMessages;
        notifyListeners(); // Notify to show the message again + error
      } else {
        // If not locally removed, still notify about the error
        notifyListeners();
      }
    }

    // 3. Delete from Cache (only if network delete was successful OR if message wasn't found locally anyway)
    if (networkDeleteSuccess || !locallyRemoved) {
      try {
        await _dbHelper.deleteMessage(messageId);
        log('[MessageProvider] Deleted message $messageId from cache.');
      } catch (e) {
        log('[MessageProvider] Error deleting message $messageId from cache: $e');
        // Log error but don't block
      }
    } else {
      log('[MessageProvider] Skipping cache delete for $messageId because network delete failed and it was removed locally.');
      // This keeps the message in cache in case of network failure, allowing potential future sync
    }

    // 4. Trigger summary refresh (non-blocking)
    fetchMessages(forceRefresh: true);

    return networkDeleteSuccess; // Return status of network operation
  }

  // TODO: Add methods for sending messages, real-time updates for summaries
}
