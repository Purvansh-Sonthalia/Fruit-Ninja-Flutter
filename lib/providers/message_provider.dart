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

class MessageProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService; // Inject AuthService

  // Keep the raw messages list if needed elsewhere, or remove if only summaries are used
  // List<Message> _messages = [];

  // New state for conversation summaries
  List<ConversationSummary> _conversationSummaries = [];

  // State for messages within a specific chat
  Map<String, List<Message>> _chatMessages = {}; // Key: otherUserId
  Map<String, bool> _chatLoading = {};
  Map<String, bool> _chatHasError = {};
  Map<String, String> _chatErrorMessage = {};
  Map<String, DateTime?> _latestMessageTimestampPerChat = {}; // Added: Track latest timestamp per chat

  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  // Constructor requires AuthService
  MessageProvider(this._authService);

  // Getters for UI
  List<ConversationSummary> get conversationSummaries => _conversationSummaries;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;

  // Getter for specific chat messages
  List<Message> getMessagesForChat(String otherUserId) => _chatMessages[otherUserId] ?? [];
  bool isLoadingChat(String otherUserId) => _chatLoading[otherUserId] ?? false;
  bool chatHasError(String otherUserId) => _chatHasError[otherUserId] ?? false;
  String getChatErrorMessage(String otherUserId) => _chatErrorMessage[otherUserId] ?? '';

  // Fetch messages and process them into conversation summaries
  Future<void> fetchMessages({bool forceRefresh = false}) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      log('[MessageProvider] User not logged in. Cannot fetch messages.');
      _conversationSummaries = [];
      _isLoading = false;
      _hasError = true;
      _errorMessage = 'User not logged in.';
      notifyListeners();
      return;
    }

    if (_isLoading && !forceRefresh) return; // Prevent concurrent fetches

    log('[MessageProvider] Fetching messages for user: $currentUserId to generate summaries.');
    _isLoading = true;
    _hasError = false;
    _errorMessage = '';
    if (forceRefresh) {
      _conversationSummaries = []; // Clear existing summaries on refresh
    }
    notifyListeners(); // Notify UI that loading has started

    try {
      // 1. Fetch messages (same as before)
      final messagesResponse = await _supabase
          .from('messages')
          .select('*')
          .or('from_user_id.eq.$currentUserId,to_user_id.eq.$currentUserId')
          .order('created_at', ascending: false) // Fetch newest first
          .limit(200); // Fetch more messages to ensure we get latest from all conversations

      final List<dynamic> messagesData = messagesResponse as List<dynamic>;
      log('[MessageProvider] Fetched ${messagesData.length} raw messages for summary generation.');

      if (messagesData.isEmpty) {
        _conversationSummaries = [];
        _isLoading = false;
        _hasError = false;
        notifyListeners();
        return;
      }

      // 2. Collect unique user IDs (same as before)
      final Set<String> userIds = {};
      for (var msgData in messagesData) {
        userIds.add(msgData['from_user_id'] as String);
        userIds.add(msgData['to_user_id'] as String);
      }
      // Remove current user ID if present, we only need profiles of others
      userIds.remove(currentUserId);

      // 3. Fetch profiles for the collected user IDs (same as before)
      final profilesResponse = await _supabase
          .from('profiles')
          .select('user_id, display_name')
          .inFilter('user_id', userIds.toList());

      final List<dynamic> profilesData = profilesResponse as List<dynamic>;
      log('[MessageProvider] Fetched ${profilesData.length} profiles for display names.');

      // 4. Create a map for quick display name lookup (same as before)
      final Map<String, String> displayNameMap = {
        for (var profileData in profilesData)
          profileData['user_id'] as String: profileData['display_name'] as String? ?? 'Anonymous'
      };

      // 5. Process messages into Conversation Summaries
      // Use a map to store the latest message for each conversation partner
      final Map<String, Message> latestMessages = {};

      for (var msgData in messagesData) {
        final message = Message.fromJson(msgData as Map<String, dynamic>); // No need for display names here yet
        // Determine the other user in this message
        final String otherUserId = (message.fromUserId == currentUserId) ? message.toUserId : message.fromUserId;

        // If this message is newer than the one stored for this other user, update it
        if (!latestMessages.containsKey(otherUserId) || message.createdAt.isAfter(latestMessages[otherUserId]!.createdAt)) {
          latestMessages[otherUserId] = message;
        }
      }

      // 6. Create the list of ConversationSummary objects
      _conversationSummaries = latestMessages.entries.map((entry) {
        final otherUserId = entry.key;
        final latestMessage = entry.value;
        final otherUserName = displayNameMap[otherUserId] ?? 'Unknown User';

        return ConversationSummary(
          otherUserId: otherUserId,
          otherUserDisplayName: otherUserName,
          lastMessageText: latestMessage.messageText ?? '[Media Message]', // Placeholder for media
          lastMessageTimestamp: latestMessage.createdAt,
          lastMessageFromUserId: latestMessage.fromUserId,
        );
      }).toList();

      // Sort summaries by the latest message timestamp (newest first)
      _conversationSummaries.sort((a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));

      log('[MessageProvider] Generated ${_conversationSummaries.length} conversation summaries.');

      _isLoading = false;
      _hasError = false;
    } on PostgrestException catch (e) {
      log('[MessageProvider] PostgrestException generating summaries: ${e.message}', error: e);
      _isLoading = false;
      _hasError = true;
      _errorMessage = 'Error fetching conversations: ${e.message}';
    } catch (e, stacktrace) {
      log('[MessageProvider] Generic error generating summaries: $e', error: e, stackTrace: stacktrace);
      _isLoading = false;
      _hasError = true;
      _errorMessage = 'An unexpected error occurred while loading conversations.';
    } finally {
      if (hasListeners) {
         notifyListeners();
      }
    }
  }

  // Fetch messages for a specific conversation (Initial Fetch)
  Future<void> fetchMessagesForChat(String otherUserId) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) return; // Should be logged in

    // Prevent concurrent fetches for the same chat
    if (_chatLoading[otherUserId] ?? false) return;

    log('[MessageProvider] Fetching initial messages for chat with $otherUserId');
    _chatLoading[otherUserId] = true;
    _chatHasError[otherUserId] = false;
    _chatErrorMessage[otherUserId] = '';
    _latestMessageTimestampPerChat.remove(otherUserId); // Clear timestamp for initial full fetch
    notifyListeners();

    try {
      final response = await _supabase
          .from('messages')
          .select('*') // Select all message columns
          .or('and(from_user_id.eq.$currentUserId,to_user_id.eq.$otherUserId),and(from_user_id.eq.$otherUserId,to_user_id.eq.$currentUserId)')
          .order('created_at', ascending: false) // Fetch newest first
          .limit(100); // Limit fetch size for a single chat

      final List<dynamic> messagesData = response as List<dynamic>;
      log('[MessageProvider] Fetched ${messagesData.length} initial messages for chat $otherUserId.');

      final List<Message> fetchedMessages = messagesData
          .map((msgData) => Message.fromJson(msgData as Map<String, dynamic>))
          .toList();

      _chatMessages[otherUserId] = fetchedMessages;

      // Store the timestamp of the newest message (if any) for incremental fetching
      if (fetchedMessages.isNotEmpty) {
          _latestMessageTimestampPerChat[otherUserId] = fetchedMessages.first.createdAt;
          log('[MessageProvider] Stored latest timestamp for chat $otherUserId: ${_latestMessageTimestampPerChat[otherUserId]}');
      }

      _chatLoading[otherUserId] = false;
      _chatHasError[otherUserId] = false;
    } on PostgrestException catch (e) {
      log('[MessageProvider] PostgrestException fetching initial chat messages: ${e.message}', error: e);
      _chatLoading[otherUserId] = false;
      _chatHasError[otherUserId] = true;
      _chatErrorMessage[otherUserId] = 'Error fetching messages: ${e.message}';
    } catch (e, stacktrace) {
      log('[MessageProvider] Generic error fetching initial chat messages: $e', error: e, stackTrace: stacktrace);
      _chatLoading[otherUserId] = false;
      _chatHasError[otherUserId] = true;
      _chatErrorMessage[otherUserId] = 'An unexpected error occurred.';
    } finally {
      if (hasListeners) {
        notifyListeners();
      }
    }
  }

  // Fetch only NEW messages for a specific conversation (Polling/Incremental Fetch)
  Future<void> fetchNewMessagesForChat(String otherUserId) async {
      final currentUserId = _authService.userId;
      if (currentUserId == null) return; // Should be logged in

      final lastKnownTimestamp = _latestMessageTimestampPerChat[otherUserId];
      // If we don't have a timestamp, we shouldn't be polling yet, maybe trigger initial fetch?
      // For now, just exit if no timestamp exists. Initial fetch should establish it.
      if (lastKnownTimestamp == null) {
          log('[MessageProvider] No last known timestamp for chat $otherUserId. Cannot fetch new messages.');
          // Optionally: Trigger fetchMessagesForChat(otherUserId) here? Or rely on UI logic.
          return;
      }

      // log('[MessageProvider] Polling for new messages in chat $otherUserId since $lastKnownTimestamp');

      try {
          // --- Query 1: Fetch NEW full messages --- 
          final newMessagesResponse = await _supabase
              .from('messages')
              .select('*')
              .or('and(from_user_id.eq.$currentUserId,to_user_id.eq.$otherUserId),and(from_user_id.eq.$otherUserId,to_user_id.eq.$currentUserId)')
              .gt('created_at', lastKnownTimestamp.toIso8601String()) // Fetch messages strictly newer
              .order('created_at', ascending: true); // Fetch oldest new messages first

          final List<dynamic> newMessagesData = newMessagesResponse as List<dynamic>;
          DateTime? latestTimestampInNewBatch;
          final List<Message> newMessages = newMessagesData.map((msgData) {
              final message = Message.fromJson(msgData as Map<String, dynamic>);
              // Track the latest timestamp from this new batch
              if (latestTimestampInNewBatch == null || message.createdAt.isAfter(latestTimestampInNewBatch!)) {
                  latestTimestampInNewBatch = message.createdAt;
              }
              return message;
          }).toList();

          // --- Query 2: Fetch RECENT message IDs (to detect deletions) ---
          const int recentMessageLimit = 100; // How many recent messages to check
          final recentIdsResponse = await _supabase
              .from('messages')
              .select('message_id') // Select only IDs
              .or('and(from_user_id.eq.$currentUserId,to_user_id.eq.$otherUserId),and(from_user_id.eq.$otherUserId,to_user_id.eq.$currentUserId)')
              .order('created_at', ascending: false) // Get the most recent ones
              .limit(recentMessageLimit);
          
          final List<dynamic> recentIdsData = recentIdsResponse as List<dynamic>;
          final Set<String> recentServerIds = recentIdsData
              .map((data) => data['message_id'] as String)
              .toSet();

          // --- Compare local state with server state ---
          final List<Message> currentLocalMessages = List<Message>.from(_chatMessages[otherUserId] ?? []);
          final Set<String> currentLocalIds = currentLocalMessages.map((m) => m.messageId).toSet();

          // Identify deleted messages (present locally, but not in recent server IDs)
          final Set<String> deletedIds = currentLocalIds.difference(recentServerIds);
          // Identify truly new messages (fetched in query 1, but not already present locally)
          final List<Message> trulyNewMessages = newMessages
              .where((newMessage) => !currentLocalIds.contains(newMessage.messageId))
              .toList();

          bool changed = false;
          List<Message> updatedMessages = currentLocalMessages;

          // Apply deletions if any found
          if (deletedIds.isNotEmpty) {
              log('[MessageProvider] Detected ${deletedIds.length} deleted messages in chat $otherUserId: ${deletedIds.join(", ")}');
              updatedMessages = updatedMessages
                  .where((msg) => !deletedIds.contains(msg.messageId))
                  .toList();
              changed = true;
          }

          // Apply additions if any found
          if (trulyNewMessages.isNotEmpty) {
              log('[MessageProvider] Applying ${trulyNewMessages.length} new messages to chat $otherUserId.');
              // Prepend new messages (since ListView is reversed and newMessages were fetched ASC)
              updatedMessages.insertAll(0, trulyNewMessages);
              changed = true;

              // Update the latest known timestamp only if new messages were actually added
              if (latestTimestampInNewBatch != null) {
                   // Make sure the timestamp only moves forward
                   if (_latestMessageTimestampPerChat[otherUserId] == null || 
                       latestTimestampInNewBatch!.isAfter(_latestMessageTimestampPerChat[otherUserId]!)) {
                       _latestMessageTimestampPerChat[otherUserId] = latestTimestampInNewBatch;
                       log('[MessageProvider] Updated latest timestamp for chat $otherUserId: ${_latestMessageTimestampPerChat[otherUserId]}');
                   }
              }
          }

          // --- Update state and notify if changes occurred ---
          if (changed) {
              _chatMessages[otherUserId] = updatedMessages;
              notifyListeners();
              log('[MessageProvider] Notified listeners for chat $otherUserId due to changes.');
          }
          // else { log('[MessageProvider] No changes detected for chat $otherUserId.'); }

      } on PostgrestException catch (e) {
          // Log errors but maybe don't set global error state for background polling?
          log('[MessageProvider] PostgrestException polling chat messages $otherUserId: ${e.message}', error: e);
          // Optionally: Set a temporary polling error flag?
          // _chatPollingError[otherUserId] = true;
      } catch (e, stacktrace) {
          log('[MessageProvider] Generic error polling chat messages $otherUserId: $e', error: e, stackTrace: stacktrace);
           // Optionally: Set a temporary polling error flag?
          // _chatPollingError[otherUserId] = true;
      }
      // No finally/notifyListeners here, only notify if there were actual updates.
  }

  // Method to send a message
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
    String? parentMessageId, // For replies
    Map<String, dynamic>? media, // For future media messages
  }) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      log('[MessageProvider] Cannot send message: User not logged in.');
      return false;
    }

    log('[MessageProvider] Sending message to $toUserId from $currentUserId');
    String? messageId;

    try {
      // Insert and select the new message to get its ID
      final response = await _supabase.from('messages').insert({
        'from_user_id': currentUserId,
        'to_user_id': toUserId,
        'message_text': text.trim(),
        'message_media': media, // null if not provided
        'parent_message_id': parentMessageId, // null if not a reply
      }).select('message_id').single(); // Select the ID

      messageId = response['message_id'] as String?;
      log('[MessageProvider] Message inserted successfully. ID: $messageId');

      if (messageId == null) {
        throw Exception('Failed to retrieve message ID after insert.');
      }

      // --- Send Notification --- 
      // Determine content presence for notification
      final bool hasText = text.trim().isNotEmpty;
      final bool hasImage = media?['type'] == 'image';

      // Locally create the message object AFTER successful DB insertion
      // Use UTC time for consistency, similar to DB
      final DateTime messageTimestamp = DateTime.now().toUtc();
      final Message newMessage = Message(
          messageId: messageId,
          createdAt: messageTimestamp,
          fromUserId: currentUserId,
          toUserId: toUserId,
          messageText: text.trim(),
          messageMedia: media,
          parentMessageId: parentMessageId,
          // Display names aren't needed for local update
      );

      await _sendMessageNotification(
        recipientUserId: toUserId,
        senderUserId: currentUserId,
        messageId: messageId,
        messageText: text.trim(),
        // Pass flags to notification helper
        hasText: hasText,
        hasImage: hasImage,
      );
      // -----------------------

      // --- Update Local State Instead of Full Refresh ---
      final List<Message> currentMessages = List<Message>.from(_chatMessages[toUserId] ?? []);
      // Add the new message to the beginning (since list is reversed in UI)
      currentMessages.insert(0, newMessage);
      _chatMessages[toUserId] = currentMessages;
      // Update the latest timestamp
      _latestMessageTimestampPerChat[toUserId] = messageTimestamp;
      log('[MessageProvider] Locally added new message $messageId to chat $toUserId and updated timestamp.');
      // -----------------------------------------------

      // Trigger summary refresh (still needed)
      fetchMessages(forceRefresh: true);

      // Notify listeners about the local change
      notifyListeners();

      return true;
    } on PostgrestException catch (e) {
      log('[MessageProvider] PostgrestException sending message: ${e.message}', error: e);
      _chatErrorMessage[toUserId] = 'Failed to send message: ${e.message}';
      _chatHasError[toUserId] = true;
      notifyListeners();
      return false;
    } catch (e, stacktrace) {
      log('[MessageProvider] Generic error sending message: $e', error: e, stackTrace: stacktrace);
      _chatErrorMessage[toUserId] = 'An unexpected error occurred while sending.';
      _chatHasError[toUserId] = true;
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
      senderDisplayName = profileResponse['display_name'] as String? ?? 'Someone';
    } catch (e) {
      log('[Notification] Error fetching sender\'s display name ($senderUserId)', error: e);
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
    final String notificationUrl = '$backendBaseUrl/api/send-like-notification'; // If reusing

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
             : (messageText.length > 100 ? '${messageText.substring(0, 97)}...' : messageText);
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
      'notificationTitle': title,   // Use dynamic title
      'notificationBody': body,    // Use dynamic body
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
      log('[Notification] Error sending message notification HTTP request', error: e, stackTrace: stacktrace);
    }
  }

  // Method to fetch a single message by ID (e.g., for reply context)
  Future<Message?> fetchSingleMessage(String messageId) async {
    log('[MessageProvider] Fetching single message: $messageId');
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('message_id', messageId)
          .limit(1)
          .maybeSingle(); // Use maybeSingle to handle null gracefully

      if (response == null) {
        log('[MessageProvider] Single message $messageId not found.');
        return null;
      }

      log('[MessageProvider] Fetched single message successfully.');
      // We don't need display names for the reply snippet usually
      return Message.fromJson(response as Map<String, dynamic>);

    } on PostgrestException catch (e) {
      log('[MessageProvider] PostgrestException fetching single message $messageId', error: e);
      return null;
    } catch (e, stacktrace) {
      log('[MessageProvider] Generic error fetching single message $messageId', error: e, stackTrace: stacktrace);
      return null;
    }
  }

  // Method to delete a message
  Future<bool> deleteMessage(String messageId, String otherUserId) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      log('[MessageProvider] Cannot delete message: User not logged in.');
      return false;
    }

    log('[MessageProvider] Attempting to delete message $messageId');

    try {
      // Perform the delete, ensuring the user owns the message
      await _supabase
          .from('messages')
          .delete()
          .eq('message_id', messageId)
          .eq('from_user_id', currentUserId); // Authorization check

      log('[MessageProvider] Message $messageId deleted successfully from DB.');

      // --- Update Local State Instead of Full Refresh ---
      final List<Message> currentMessages = List<Message>.from(_chatMessages[otherUserId] ?? []);
      final originalLength = currentMessages.length;
      currentMessages.removeWhere((msg) => msg.messageId == messageId);

      // Update the map regardless of whether the item was found locally
      _chatMessages[otherUserId] = currentMessages;

      if (currentMessages.length < originalLength) {
          log('[MessageProvider] Locally removed message $messageId from chat $otherUserId.');
          // Update latest timestamp logic...
          if (currentMessages.isEmpty) {
              _latestMessageTimestampPerChat.remove(otherUserId);
              log('[MessageProvider] Cleared timestamp for chat $otherUserId as it is now empty.');
          }
          // No notifyListeners() here anymore
      } else {
          log('[MessageProvider] Message $messageId not found in local list for chat $otherUserId after delete, but updating state anyway.');
      }

      // Notify listeners AFTER attempting the local removal and updating the map
      notifyListeners();
      // -----------------------------------------------

      // Trigger summary refresh (still needed)
      fetchMessages(forceRefresh: true);

      return true;
    } on PostgrestException catch (e) {
      log('[MessageProvider] PostgrestException deleting message $messageId', error: e);
      // Optionally update chat-specific error state
      _chatErrorMessage[otherUserId] = 'Failed to delete message: ${e.message}';
      _chatHasError[otherUserId] = true;
      notifyListeners();
      return false;
    } catch (e, stacktrace) {
      log('[MessageProvider] Generic error deleting message $messageId', error: e, stackTrace: stacktrace);
      _chatErrorMessage[otherUserId] = 'An unexpected error occurred while deleting.';
      _chatHasError[otherUserId] = true;
      notifyListeners();
      return false;
    }
  }

  // TODO: Add methods for sending messages, real-time updates for summaries
} 