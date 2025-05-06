import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer'; // For logging
import 'dart:collection'; // For SplayTreeMap
import '../models/message_model.dart';
import '../services/auth_service.dart'; // To get the current user ID
import 'dart:convert'; // For jsonEncode
import 'package:http/http.dart' as http; // For HTTP requests
import 'package:flutter_dotenv/flutter_dotenv.dart'; // For environment variables
import '../services/database_helper.dart';
import 'package:uuid/uuid.dart'; // For generating temporary local IDs
import '../services/profile_service.dart'; // Import ProfileService
import '../services/notification_service.dart'; // Import NotificationService
import '../services/conversation_service.dart'; // Import ConversationService
import '../services/chat_service.dart'; // Import ChatService
import 'dart:async'; // For StreamSubscription

// Rename class to ChatProvider
class ChatProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService; // Inject AuthService
  // Remove dependencies now potentially only used by services?
  // final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = Uuid(); // Uncomment Uuid
  // Add Service instances
  final ProfileService _profileService = ProfileService();
  final NotificationService _notificationService = NotificationService();
  // Remove ConversationService - Handled by ConversationListProvider
  // final ConversationService _conversationService = ConversationService();
  final ChatService _chatService; // Inject ChatService

  // Keep track of offline status
  bool _isOffline = false;

  // State for messages within a specific chat (Keep this)
  Map<String, List<Message>> _chatMessages = {}; // Key: otherUserId
  Map<String, bool> _isLoadingChat = {};
  Map<String, bool> _hasErrorChat = {}; // Separate error state per chat
  Map<String, String> _errorChatMessage = {}; // Separate error message per chat
  Map<String, DateTime?> _latestMessageTimestampPerChat = {};

  // Realtime subscription management
  StreamSubscription? _newMessageSubscription;
  StreamSubscription? _deletedMessageSubscription;
  String? _currentlyListeningToChat; // Track which chat is active

  // Constructor requires AuthService and potentially ChatService
  ChatProvider({required AuthService authService, ChatService? chatService})
      : _authService = authService,
        _chatService = chatService ?? ChatService();

  // Getter for specific chat messages (Keep)
  List<Message> getMessagesForChat(String otherUserId) =>
      _chatMessages[otherUserId] ?? [];
  bool isLoadingChat(String otherUserId) =>
      _isLoadingChat[otherUserId] ?? false;
  bool chatHasError(String otherUserId) => _hasErrorChat[otherUserId] ?? false;
  String getChatErrorMessage(String otherUserId) =>
      _errorChatMessage[otherUserId] ?? '';
  bool get isOffline => _isOffline; // Expose offline status

  // Method to Load Chat Messages using ChatService
  Future<void> loadChatMessages(String otherUserId) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      _setErrorState(otherUserId, true, 'User not logged in.');
      notifyListeners();
      return;
    }

    if (_isLoadingChat[otherUserId] ?? false) return;

    _setLoadingState(otherUserId, true);
    _isOffline = false; // Assume online initially
    notifyListeners();

    try {
      final result =
          await _chatService.getMessagesForChat(currentUserId, otherUserId);

      _chatMessages[otherUserId] = result.messages;
      _latestMessageTimestampPerChat[otherUserId] =
          result.latestNetworkTimestamp; // Store timestamp from service
      _setErrorState(otherUserId, result.hasError, result.error);
      _isOffline =
          result.hasError; // Assume offline if there was an error fetching

      log('[MessageProvider] Updated chat state for $otherUserId. Messages: ${result.messages.length}, HasError: ${result.hasError}, Timestamp: ${result.latestNetworkTimestamp}');
    } catch (e, stacktrace) {
      // Catch potential exceptions from the service call itself (though service should handle most)
      log('[MessageProvider] Unexpected error calling ChatService.getMessagesForChat for $otherUserId: $e',
          error: e, stackTrace: stacktrace);
      _setErrorState(otherUserId, true,
          'An unexpected error occurred while loading messages.');
      _isOffline = true;
    } finally {
      _setLoadingState(otherUserId, false);
      notifyListeners();
    }
  }

  // Helper methods for state updates
  void _setLoadingState(String otherUserId, bool isLoading) {
    _isLoadingChat[otherUserId] = isLoading;
    if (isLoading) {
      _hasErrorChat[otherUserId] = false;
      _errorChatMessage[otherUserId] = '';
    }
  }

  void _setErrorState(String otherUserId, bool hasError, String? errorMessage) {
    _hasErrorChat[otherUserId] = hasError;
    _errorChatMessage[otherUserId] = errorMessage ?? '';
    // Don't set loading false here, finally block handles it
  }

  // Call this when entering a chat screen
  void activateChat(String otherUserId) {
    final currentUserId = _authService.userId;
    if (currentUserId == null) return;

    // If switching chats, setup new listeners
    if (_currentlyListeningToChat != otherUserId) {
      inactivateChat(); // Unsubscribe from previous chat

      _currentlyListeningToChat = otherUserId;
      log('[ChatProvider] Activating chat and listeners for $otherUserId');

      // Subscribe service to realtime events
      _chatService.subscribeToChatUpdates(currentUserId, otherUserId);

      // Listen to streams from the service
      _newMessageSubscription =
          _chatService.newMessageStream.listen(_handleNewMessage);
      _deletedMessageSubscription =
          _chatService.deletedMessageIdStream.listen(_handleDeletedMessage);

      // Initial load still needed
      loadChatMessages(otherUserId);
    }
  }

  // Call this when leaving a chat screen
  void inactivateChat() {
    if (_currentlyListeningToChat != null) {
      log('[ChatProvider] Inactivating chat and listeners for $_currentlyListeningToChat');
      _newMessageSubscription?.cancel();
      _deletedMessageSubscription?.cancel();
      _chatService.unsubscribeFromChatUpdates();
      _currentlyListeningToChat = null;
    }
  }

  // Handler for new messages from the stream
  void _handleNewMessage(Message newMessage) {
    final otherUserId = (_authService.userId == newMessage.fromUserId)
        ? newMessage.toUserId
        : newMessage.fromUserId;

    // Only process if it belongs to the currently active chat
    if (otherUserId == _currentlyListeningToChat) {
      log('[ChatProvider] Received new message ${newMessage.messageId} via stream for active chat.');
      final List<Message> currentMessages =
          List<Message>.from(_chatMessages[otherUserId] ?? []);
      // Avoid adding duplicates
      if (!currentMessages.any((m) => m.messageId == newMessage.messageId)) {
        currentMessages.insert(0, newMessage); // Add to beginning
        _chatMessages[otherUserId] = currentMessages;
        // Update latest timestamp if needed
        if (_latestMessageTimestampPerChat[otherUserId] == null ||
            newMessage.createdAt
                .isAfter(_latestMessageTimestampPerChat[otherUserId]!)) {
          _latestMessageTimestampPerChat[otherUserId] = newMessage.createdAt;
        }
        notifyListeners();
      } else {
        log('[ChatProvider] New message ${newMessage.messageId} via stream already exists locally.');
      }
    } else {
      log('[ChatProvider] Received new message ${newMessage.messageId} via stream for INACTIVE chat ($otherUserId).');
      // TODO: Optionally update conversation summary or show badge notification
    }
  }

  // Handler for deleted message IDs from the stream
  void _handleDeletedMessage(String deletedMessageId) {
    log('[ChatProvider] Received deleted message ID $deletedMessageId via stream.');
    bool changed = false;
    // Need to check all active chats this message *might* belong to
    // For simplicity, let's assume it belongs to the active chat if listening
    if (_currentlyListeningToChat != null) {
      final List<Message> currentMessages =
          List<Message>.from(_chatMessages[_currentlyListeningToChat!] ?? []);
      final initialLength = currentMessages.length;
      currentMessages.removeWhere((msg) => msg.messageId == deletedMessageId);
      if (currentMessages.length < initialLength) {
        _chatMessages[_currentlyListeningToChat!] = currentMessages;
        changed = true;
        log('[ChatProvider] Removed deleted message $deletedMessageId from active chat $_currentlyListeningToChat.');
      }
    }
    // If the UI needs to react to deletions in non-active chats, more complex logic needed.
    if (changed) {
      notifyListeners();
    }
  }

  // Method to Send Message using ChatService
  Future<bool> sendMessage({
    required String toUserId,
    required String text,
    String? parentMessageId,
    Map<String, dynamic>? media,
  }) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      _setErrorState(toUserId, true, 'Cannot send message: Not logged in.');
      notifyListeners();
      return false;
    }

    // 1. Create optimistic message with temporary local ID
    final tempMessageId = 'local_${_uuid.v4()}';
    final messageTimestamp = DateTime.now();
    final optimisticMessage = Message(
      messageId: tempMessageId,
      createdAt: messageTimestamp,
      fromUserId: currentUserId,
      toUserId: toUserId,
      messageText: text.trim().isEmpty ? null : text.trim(),
      messageMedia: media,
      parentMessageId: parentMessageId,
      // You might add an isPending or status field here
      // status: MessageStatus.pending,
    );

    // 2. Add optimistic message to local state
    final List<Message> currentMessages =
        List<Message>.from(_chatMessages[toUserId] ?? []);
    currentMessages.insert(0, optimisticMessage); // Add to beginning
    _chatMessages[toUserId] = currentMessages;
    _setErrorState(toUserId, false, null); // Clear previous errors
    _isOffline = false; // Assume online when attempting send
    notifyListeners(); // Update UI immediately

    // 3. Call ChatService to send the message
    try {
      final confirmedMessage = await _chatService.sendMessage(
        currentUserId: currentUserId,
        toUserId: toUserId,
        text: text,
        parentMessageId: parentMessageId,
        media: media,
      );

      // 4. Update local message with confirmed details
      final List<Message> updatedMessages =
          List<Message>.from(_chatMessages[toUserId] ?? []);
      final index =
          updatedMessages.indexWhere((msg) => msg.messageId == tempMessageId);
      if (index != -1) {
        updatedMessages[index] =
            confirmedMessage; // Replace temp with confirmed
        _chatMessages[toUserId] = updatedMessages;

        // Update latest timestamp if this confirmed message is newer
        if (_latestMessageTimestampPerChat[toUserId] == null ||
            confirmedMessage.createdAt
                .isAfter(_latestMessageTimestampPerChat[toUserId]!)) {
          _latestMessageTimestampPerChat[toUserId] = confirmedMessage.createdAt;
        }

        log('[MessageProvider] Confirmed message ${confirmedMessage.messageId} locally.');
        notifyListeners(); // Update UI with confirmed message
      } else {
        // Optimistic message was likely removed by polling before confirmation arrived.
        // Add the confirmed message if it's not already there (edge case).
        if (!updatedMessages
            .any((m) => m.messageId == confirmedMessage.messageId)) {
          updatedMessages.insert(0, confirmedMessage);
          _chatMessages[toUserId] = updatedMessages;
          notifyListeners();
        }
        log('[MessageProvider] Warning: Optimistic message $tempMessageId not found, but received confirmation ${confirmedMessage.messageId}.');
      }
      return true; // Indicate success
    } catch (e, stacktrace) {
      log('[MessageProvider] Error sending message via ChatService: $e',
          error: e, stackTrace: stacktrace);
      _setErrorState(toUserId, true, 'Failed to send message.');
      _isOffline = true;
      // Keep optimistic message, but maybe update its status to failed
      // final index = (_chatMessages[toUserId] ?? []).indexWhere((msg) => msg.messageId == tempMessageId);
      // if (index != -1) {
      //    _chatMessages[toUserId]![index] = optimisticMessage.copyWith(status: MessageStatus.failed);
      // }
      notifyListeners(); // Notify UI about the error/status change
      return false; // Indicate failure
    }
  }

  // Method to Delete Message using ChatService
  Future<bool> deleteMessage(String messageId, String otherUserId) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      _setErrorState(
          otherUserId, true, 'Cannot delete message: Not logged in.');
      notifyListeners();
      return false;
    }

    // 1. Optimistic UI update: Store message and remove locally
    final List<Message> currentMessages =
        List<Message>.from(_chatMessages[otherUserId] ?? []);
    Message? messageToDelete;
    int originalIndex = -1;
    try {
      originalIndex =
          currentMessages.indexWhere((msg) => msg.messageId == messageId);
      if (originalIndex != -1) {
        messageToDelete = currentMessages[originalIndex];
        currentMessages.removeAt(originalIndex);
        _chatMessages[otherUserId] = currentMessages;
        log('[MessageProvider] Optimistically removed message $messageId for chat $otherUserId.');
        notifyListeners(); // Update UI immediately
      } else {
        log('[MessageProvider] Message $messageId not found locally to delete optimistically.');
        // Proceed with network delete anyway
      }
    } catch (e) {
      // Catch potential errors during local removal
      log('[MessageProvider] Error during optimistic removal of $messageId: $e');
      // Proceed with network delete
    }

    // 2. Call ChatService to delete the message
    bool success = false;
    try {
      success = await _chatService.deleteMessage(currentUserId, messageId);
      if (success) {
        log('[MessageProvider] ChatService confirmed deletion of message $messageId.');
        _setErrorState(otherUserId, false, null); // Clear error on success
        _isOffline = false;
        // UI already updated optimistically
      } else {
        log('[MessageProvider] ChatService reported failure deleting message $messageId.');
        _setErrorState(otherUserId, true, 'Failed to delete message.');
        _isOffline = true;
        // Revert optimistic removal if it happened
        if (messageToDelete != null && originalIndex != -1) {
          final revertedMessages =
              List<Message>.from(_chatMessages[otherUserId] ?? []);
          // Ensure we don't add it back if it was removed by polling in the meantime
          if (!revertedMessages.any((m) => m.messageId == messageId)) {
            revertedMessages.insert(originalIndex, messageToDelete);
            _chatMessages[otherUserId] = revertedMessages;
            log('[MessageProvider] Reverted optimistic removal of $messageId.');
            notifyListeners(); // Notify UI about revert + error
          } else {
            notifyListeners(); // Still notify about error
          }
        } else {
          notifyListeners(); // Notify about error even if no revert needed
        }
      }
    } catch (e, stacktrace) {
      log('[MessageProvider] Error calling ChatService.deleteMessage: $e',
          error: e, stackTrace: stacktrace);
      _setErrorState(otherUserId, true, 'Failed to delete message.');
      _isOffline = true;
      // Revert optimistic removal if it happened
      if (messageToDelete != null && originalIndex != -1) {
        final revertedMessages =
            List<Message>.from(_chatMessages[otherUserId] ?? []);
        if (!revertedMessages.any((m) => m.messageId == messageId)) {
          revertedMessages.insert(originalIndex, messageToDelete);
          _chatMessages[otherUserId] = revertedMessages;
          log('[MessageProvider] Reverted optimistic removal of $messageId due to service error.');
          notifyListeners();
        } else {
          notifyListeners();
        }
      } else {
        notifyListeners();
      }
      success = false; // Ensure failure is returned
    }

    return success;
  }

  // Method to Fetch Single Message using ChatService
  Future<Message?> fetchSingleMessage(String messageId) async {
    // Directly call the service method.
    // The service handles caching.
    // The provider doesn't need to store the result of this specific call in its own state,
    // as it's typically used for temporary context (like a reply preview).
    log('[MessageProvider] Requesting single message $messageId from ChatService.');
    try {
      final message = await _chatService.getSingleMessage(messageId);
      // No need to notifyListeners or update provider state here
      return message;
    } catch (e, stacktrace) {
      log('[MessageProvider] Error calling ChatService.getSingleMessage: $e',
          error: e, stackTrace: stacktrace);
      return null; // Return null on error
    }
  }

  // Optional: Method to clear state for a specific chat if needed
  void clearChatState(String otherUserId) {
    _chatMessages.remove(otherUserId);
    _isLoadingChat.remove(otherUserId);
    _hasErrorChat.remove(otherUserId);
    _errorChatMessage.remove(otherUserId);
    _latestMessageTimestampPerChat.remove(otherUserId);
    notifyListeners(); // Or selectively notify if possible
    log('[ChatProvider] Cleared state for chat: $otherUserId');
  }

  // Optional: Clear all chat state (e.g., on logout)
  void clearAllChatStates() {
    _chatMessages.clear();
    _isLoadingChat.clear();
    _hasErrorChat.clear();
    _errorChatMessage.clear();
    _latestMessageTimestampPerChat.clear();
    _isOffline = false; // Reset offline state
    notifyListeners();
    log('[ChatProvider] Cleared all chat states.');
  }

  // Override dispose to ensure cleanup
  @override
  void dispose() {
    log('[ChatProvider] Disposing...');
    inactivateChat(); // Cancel listeners and unsubscribe service
    _chatService.dispose(); // Dispose service controllers if necessary
    super.dispose();
  }
}
