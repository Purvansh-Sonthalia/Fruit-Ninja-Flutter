// Service to handle fetching, caching, sending, and deleting individual chat messages
import 'dart:async'; // Import for StreamController
import 'package:supabase_flutter/supabase_flutter.dart';
// REMOVE Explicitly import Realtime components
// import 'package:realtime_client/realtime_client.dart';
import '../models/message_model.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer';

class ChatService {
  final SupabaseClient _supabase;
  final DatabaseHelper _dbHelper;
  final ProfileService _profileService;
  final NotificationService _notificationService;
  final Uuid _uuid;

  // Realtime Subscription Management
  RealtimeChannel? _chatChannel; // Holds the current chat subscription
  String? _currentSubscribedUserId;
  String? _currentSubscribedOtherUserId;
  final StreamController<Message> _newMessageController =
      StreamController<Message>.broadcast();
  final StreamController<String> _deletedMessageIdController =
      StreamController<String>.broadcast();

  // Public streams for Provider to listen to
  Stream<Message> get newMessageStream => _newMessageController.stream;
  Stream<String> get deletedMessageIdStream =>
      _deletedMessageIdController.stream;

  // Cache for single message lookups (can be part of the service)
  final Map<String, Message?> _fetchedSingleMessagesCache = {};

  ChatService({
    SupabaseClient? supabaseClient,
    DatabaseHelper? dbHelper,
    ProfileService? profileService,
    NotificationService? notificationService,
    Uuid? uuid,
  })  : _supabase = supabaseClient ?? Supabase.instance.client,
        _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _profileService = profileService ?? ProfileService(),
        _notificationService = notificationService ?? NotificationService(),
        _uuid = uuid ?? Uuid();

  // --- Subscription Management ---
  void subscribeToChatUpdates(String currentUserId, String otherUserId) {
    // Unsubscribe from previous channel if switching chats
    if (_chatChannel != null &&
        (_currentSubscribedUserId != currentUserId ||
            _currentSubscribedOtherUserId != otherUserId)) {
      unsubscribeFromChatUpdates();
    }

    // Avoid duplicate subscriptions
    if (_chatChannel != null &&
        _currentSubscribedUserId == currentUserId &&
        _currentSubscribedOtherUserId == otherUserId) {
      log('[ChatService] Already subscribed to chat between $currentUserId and $otherUserId.');
      return;
    }

    log('[ChatService] Subscribing to realtime updates for chat between $currentUserId and $otherUserId.');
    _currentSubscribedUserId = currentUserId;
    _currentSubscribedOtherUserId = otherUserId;

    // Create the channel first, applying RLS filter logic implicitly via channel name/RLS policies
    _chatChannel = _supabase.channel(
        'chat:$currentUserId:$otherUserId'); // Simplified unique channel name

    // Listen for INSERT events using the new API
    _chatChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      // Filter is implicitly handled by RLS policy and channel subscription scope
      // based on the users involved (currentUserId, otherUserId)
      // filter: PostgresChangeFilter( ... ) // Not needed if RLS is correctly set up
      callback: (PostgresChangePayload payload) {
        log('[ChatService] Realtime INSERT received: ${payload.toString()}'); // Log raw payload
        try {
          if (payload.newRecord != null) {
            final newMessage = Message.fromJson(payload.newRecord!);
            // Check if the message actually belongs to this chat (double-check)
            if ((newMessage.fromUserId == _currentSubscribedUserId &&
                    newMessage.toUserId == _currentSubscribedOtherUserId) ||
                (newMessage.fromUserId == _currentSubscribedOtherUserId &&
                    newMessage.toUserId == _currentSubscribedUserId)) {
              _newMessageController.add(newMessage);
              // Cache the new message
              _dbHelper.batchUpsertMessages([newMessage]).catchError((e) {
                log('[ChatService] Error caching realtime message ${newMessage.messageId}: $e');
              });
            } else {
              log('[ChatService] Realtime INSERT ignored: Message users (${newMessage.fromUserId}, ${newMessage.toUserId}) do not match subscribed chat ($_currentSubscribedUserId, $_currentSubscribedOtherUserId)');
            }
          } else {
            log('[ChatService] Realtime INSERT payload missing newRecord.');
          }
        } catch (e, stacktrace) {
          log('[ChatService] Error processing realtime INSERT payload: $e',
              stackTrace: stacktrace);
        }
      },
    );

    // Listen for DELETE events on the same channel using the new API
    _chatChannel!.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'messages',
      // Filter implicitly handled by RLS/channel scope
      callback: (PostgresChangePayload payload) {
        log('[ChatService] Realtime DELETE received: ${payload.toString()}'); // Log raw payload
        try {
          // Extract the ID of the deleted message from the old record
          final oldRecord = payload.oldRecord;
          final deletedId = oldRecord?['message_id'] as String?;

          if (deletedId != null) {
            // Optionally verify the deleted message belonged to this chat before processing
            final fromUserId = oldRecord?['from_user_id'] as String?;
            final toUserId = oldRecord?['to_user_id'] as String?;
            if ((fromUserId == _currentSubscribedUserId &&
                    toUserId == _currentSubscribedOtherUserId) ||
                (fromUserId == _currentSubscribedOtherUserId &&
                    toUserId == _currentSubscribedUserId)) {
              _deletedMessageIdController.add(deletedId);
              // Delete from cache
              _dbHelper.deleteMessage(deletedId).catchError((e) {
                log('[ChatService] Error deleting message $deletedId from cache via realtime: $e');
              });
            } else {
              log('[ChatService] Realtime DELETE ignored: Message users ($fromUserId, $toUserId) do not match subscribed chat ($_currentSubscribedUserId, $_currentSubscribedOtherUserId)');
            }
          } else {
            log('[ChatService] Realtime DELETE payload missing message_id in oldRecord.');
          }
        } catch (e, stacktrace) {
          log('[ChatService] Error processing realtime DELETE payload: $e',
              stackTrace: stacktrace);
        }
      },
    );

    // Subscribe to the channel once after setting up listeners
    _chatChannel!.subscribe((RealtimeSubscribeStatus status, [Object? error]) {
      log('[ChatService] Realtime subscription status for chat $currentUserId-$otherUserId: $status');
      if (error != null) {
        log('[ChatService] Realtime subscription error: $error');
        // Handle subscription errors if needed (e.g., trigger a fallback poll?)
      }
    });
  }

  void unsubscribeFromChatUpdates() {
    if (_chatChannel != null) {
      log('[ChatService] Unsubscribing from realtime chat updates for $_currentSubscribedUserId-$_currentSubscribedOtherUserId.');
      _supabase.removeChannel(_chatChannel!); // Use removeChannel
      _chatChannel = null;
      _currentSubscribedUserId = null;
      _currentSubscribedOtherUserId = null;
    } else {
      log('[ChatService] No active chat subscription to unsubscribe from.');
    }
  }

  // --- End Subscription Management ---

  // Fetches messages for a chat, trying network first and falling back to cache.
  // Returns a result object containing messages and latest network timestamp.
  Future<ChatMessagesResult> getMessagesForChat(
    String currentUserId,
    String otherUserId, {
    bool forceRefresh =
        false, // Not directly used here, but might influence caller
  }) async {
    log('[ChatService] getMessagesForChat called for user: $currentUserId, otherUser: $otherUserId');

    // --- Network Fetch Attempt ---
    try {
      log('[ChatService] Fetching initial messages for chat $otherUserId from network...');
      final response = await _supabase
          .from('messages')
          .select('*')
          .or('and(from_user_id.eq.$currentUserId,to_user_id.eq.$otherUserId),and(from_user_id.eq.$otherUserId,to_user_id.eq.$currentUserId)')
          .order('created_at', ascending: false)
          .limit(100); // Limit can be adjusted

      final List<dynamic> messagesData = response as List<dynamic>? ?? [];
      log('[ChatService] Fetched ${messagesData.length} initial messages for chat $otherUserId from network.');

      final List<Message> networkMessages = messagesData
          .map((msgData) => Message.fromJson(msgData as Map<String, dynamic>))
          .toList();

      // Update cache with fetched messages
      if (networkMessages.isNotEmpty) {
        try {
          await _dbHelper.batchUpsertMessages(networkMessages);
          log('[ChatService] Cached ${networkMessages.length} messages for chat $otherUserId from network.');
        } catch (cacheError) {
          log('[ChatService] Error caching messages for chat $otherUserId from network: $cacheError');
        }
      } else {
        // If network is empty, maybe clear cache for this chat?
        // Or rely on polling/deletion logic later?
        log('[ChatService] Network returned no messages for chat $otherUserId.');
      }

      // Determine the latest timestamp from this network fetch
      DateTime? latestTimestamp =
          networkMessages.isNotEmpty ? networkMessages.first.createdAt : null;

      return ChatMessagesResult(
        messages: networkMessages,
        latestNetworkTimestamp: latestTimestamp,
        error: null, // No error
      );
    } catch (e, stacktrace) {
      log('[ChatService] Error fetching initial chat messages from network for $otherUserId: $e',
          error: e, stackTrace: stacktrace);

      // --- Cache Fallback on Network Error ---
      log('[ChatService] Network error, attempting to load chat $otherUserId from cache...');
      try {
        final cachedMessages =
            await _loadMessagesForChatFromCache(otherUserId, currentUserId);
        if (cachedMessages.isNotEmpty) {
          log('[ChatService] Returning ${cachedMessages.length} messages from cache for chat $otherUserId due to network error.');
          return ChatMessagesResult(
            messages: cachedMessages,
            latestNetworkTimestamp:
                null, // Indicate network failure by lack of timestamp
            error:
                'Failed to fetch latest messages. Displaying cached data.', // Pass error message
          );
        }
      } catch (cacheError) {
        log('[ChatService] Error loading chat $otherUserId from cache during fallback: $cacheError');
      }

      // If network and cache fallback both fail
      return ChatMessagesResult(
        messages: [], // Return empty list
        latestNetworkTimestamp: null,
        error:
            'Failed to load messages. No cached data available.', // Error message
      );
    }
  }

  // Helper to load chat messages from cache (moved from MessageProvider)
  Future<List<Message>> _loadMessagesForChatFromCache(
      String otherUserId, String currentUserId) async {
    log('[ChatService] Loading messages for chat $otherUserId from cache...');
    // Let errors bubble up to be handled by the caller (getMessagesForChat)
    final cachedMessages = await _dbHelper
        .getCachedMessagesForChat(otherUserId, currentUserId, limit: 100);
    log('[ChatService] Found ${cachedMessages.length} messages in cache for chat $otherUserId.');
    return cachedMessages;
  }

  // Sends a message, handles optimistic creation, network send, and notifications.
  // Returns the confirmed message (with network ID/timestamp) on success.
  // Throws an exception on network failure.
  Future<Message> sendMessage({
    required String currentUserId,
    required String toUserId,
    required String text,
    String? parentMessageId,
    Map<String, dynamic>? media,
  }) async {
    log('[ChatService] sendMessage called: To $toUserId');

    // 1. Create optimistic message details (without ID initially)
    final messageTimestamp = DateTime.now();
    final messageDataToSend = {
      'from_user_id': currentUserId,
      'to_user_id': toUserId,
      'message_text':
          text.trim().isEmpty ? null : text.trim(), // Handle empty text
      'message_media': media,
      'parent_message_id': parentMessageId,
    };

    // Generate temporary ID for potential local caching if needed immediately
    // String tempMessageId = 'local_${_uuid.v4()}';
    // We might not need the temp ID if optimistic update happens in Provider

    // 2. Attempt to send message to network
    try {
      log('[ChatService] Sending message data to network...');
      final response = await _supabase
          .from('messages')
          .insert(messageDataToSend)
          .select(
              '*') // Select all fields to construct the final Message object
          .single();

      // Construct the confirmed message from the network response
      final Message confirmedMessage =
          Message.fromJson(response as Map<String, dynamic>);
      log('[ChatService] Network send successful. Confirmed ID: ${confirmedMessage.messageId}');

      // 3. Cache the confirmed message (fire and forget is often ok)
      try {
        await _dbHelper.batchUpsertMessages([confirmedMessage]);
        log('[ChatService] Cached confirmed message ${confirmedMessage.messageId}.');
      } catch (e) {
        log('[ChatService] Error caching confirmed message ${confirmedMessage.messageId}: $e');
      }

      // 4. Send Notification
      final senderDisplayName =
          await _profileService.getDisplayName(currentUserId) ?? 'Someone';
      await _notificationService.sendMessageNotification(
        recipientUserId: toUserId,
        senderUserId: currentUserId,
        senderDisplayName: senderDisplayName,
        messageId: confirmedMessage.messageId,
        messageText: confirmedMessage.messageText ?? '',
        hasText: confirmedMessage.messageText?.isNotEmpty ?? false,
        hasImage: confirmedMessage.messageMedia?['type'] == 'image',
      );

      // 5. Return the confirmed message
      return confirmedMessage;
    } on PostgrestException catch (e) {
      log('[ChatService] PostgrestException sending message: ${e.message}',
          error: e);
      // Rethrow a more specific or generic exception for the Provider to handle
      throw Exception('Failed to send message: ${e.message}');
    } catch (e, stacktrace) {
      log('[ChatService] Generic error sending message: $e',
          error: e, stackTrace: stacktrace);
      throw Exception('Failed to send message: $e');
    }
  }

  // Deletes a message from network and cache.
  // Returns true on network success, false otherwise.
  Future<bool> deleteMessage(String currentUserId, String messageId) async {
    log('[ChatService] Attempting to delete message $messageId for user $currentUserId');

    bool networkDeleteSuccess = false;
    try {
      // 1. Attempt Network Delete with Authorization Check
      await _supabase
          .from('messages')
          .delete()
          .eq('message_id', messageId)
          .eq('from_user_id', currentUserId); // Ensure user owns the message

      log('[ChatService] Message $messageId deleted successfully from network.');
      networkDeleteSuccess = true;
    } on PostgrestException catch (e) {
      // Handle specific case where RLS fails or message not found/not owned
      if (e.code == 'PGRST204') {
        // Not found / RLS prevented delete
        log('[ChatService] Delete failed for message $messageId: Not found or not owned by $currentUserId.');
      } else {
        log('[ChatService] PostgrestException deleting message $messageId: ${e.message}',
            error: e);
      }
      networkDeleteSuccess = false; // Explicitly false on Postgrest error
    } catch (e, stacktrace) {
      log('[ChatService] Generic error deleting message $messageId from network',
          error: e, stackTrace: stacktrace);
      networkDeleteSuccess = false;
    }

    // 2. Delete from Cache regardless of network success?
    //    Or only if network succeeds? If network fails due to auth,
    //    local message shouldn't have existed anyway (ideally).
    //    If network fails due to connectivity, keeping cache might be desired.
    //    Let's delete from cache ONLY if network delete was confirmed.
    if (networkDeleteSuccess) {
      try {
        await _dbHelper.deleteMessage(messageId);
        log('[ChatService] Deleted message $messageId from cache.');
      } catch (e) {
        log('[ChatService] Error deleting message $messageId from cache after network success: $e');
        // Log error but don't change overall success status
      }
    } else {
      log('[ChatService] Skipping cache delete for $messageId due to network delete failure.');
    }

    return networkDeleteSuccess;
  }

  // Fetches a single message by ID, with caching.
  Future<Message?> getSingleMessage(String messageId) async {
    // Check cache first
    if (_fetchedSingleMessagesCache.containsKey(messageId)) {
      log('[ChatService] Returning cached single message: $messageId');
      return _fetchedSingleMessagesCache[messageId]; // Return cached value
    }

    log('[ChatService] Fetching single message from DB: $messageId');
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('message_id', messageId)
          .limit(1)
          .maybeSingle(); // Use maybeSingle

      if (response == null) {
        log('[ChatService] Single message $messageId not found.');
        _fetchedSingleMessagesCache[messageId] = null; // Cache null (not found)
        return null;
      }

      final message = Message.fromJson(response as Map<String, dynamic>);
      _fetchedSingleMessagesCache[messageId] = message; // Cache the result
      log('[ChatService] Fetched and cached single message $messageId.');
      return message;
    } on PostgrestException catch (e) {
      log('[ChatService] PostgrestException fetching single message $messageId',
          error: e);
      _fetchedSingleMessagesCache[messageId] = null; // Cache null (error)
      return null;
    } catch (e, stacktrace) {
      log('[ChatService] Generic error fetching single message $messageId',
          error: e, stackTrace: stacktrace);
      _fetchedSingleMessagesCache[messageId] = null; // Cache null (error)
      return null;
    }
  }

  // Optional: Method to clear single message cache if needed
  void clearSingleMessageCache() {
    _fetchedSingleMessagesCache.clear();
    log('[ChatService] Cleared single message cache.');
  }

  // Dispose stream controllers when service is no longer needed (e.g., app close)
  // Note: This might be managed by how the service lifecycle is handled in your app.
  void dispose() {
    log('[ChatService] Disposing stream controllers and unsubscribing...');
    unsubscribeFromChatUpdates(); // Ensure cleanup
    _newMessageController.close();
    _deletedMessageIdController.close();
  }
}

// Helper class to return results from getMessagesForChat
class ChatMessagesResult {
  final List<Message> messages;
  final DateTime?
      latestNetworkTimestamp; // Timestamp of newest message from *this specific network fetch*
  final String? error; // Error message if fetching failed

  ChatMessagesResult({
    required this.messages,
    required this.latestNetworkTimestamp,
    this.error,
  });

  bool get hasError => error != null;
}
