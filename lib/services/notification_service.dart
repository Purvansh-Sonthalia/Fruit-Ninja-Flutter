import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final SupabaseClient _supabase;
  final String? _backendBaseUrl;
  final http.Client _httpClient;

  NotificationService({SupabaseClient? supabaseClient, http.Client? httpClient})
      : _supabase = supabaseClient ?? Supabase.instance.client,
        _httpClient = httpClient ?? http.Client(),
        _backendBaseUrl = dotenv.env['BACKEND_URL'];

  // --- Public Methods (Moved from CommentsProvider) ---

  Future<void> sendCommentNotifications({
    required String postId,
    required String commenterUserId,
    required String commenterDisplayName,
    required String commentId,
    required String commentText,
    required bool hasImage,
    List<String>? taggedUserIds,
  }) async {
    // --- 1. Send Notification to Post Author (if not self-comment) ---
    log('[NotificationService] Preparing notification for comment $commentId on post $postId...');
    String? postAuthorId;
    try {
      final postResponse = await _supabase
          .from('posts')
          .select('user_id')
          .eq('post_id', postId)
          .single();
      postAuthorId = postResponse['user_id'] as String?;

      if (postAuthorId != null && postAuthorId != commenterUserId) {
        log('[NotificationService] Sending comment notification to post author $postAuthorId');
        await _sendNotificationViaBackend(
          recipientUserId: postAuthorId,
          actorUserId: commenterUserId,
          actorDisplayName: commenterDisplayName,
          postId: postId,
          commentId: commentId,
          commentText: commentText,
          hasImage: hasImage,
          notificationType: 'comment', // Type for post author
        );
      } else {
        log('[NotificationService] Post author not found or is the commenter ($postAuthorId). No notification sent to author.');
      }
    } catch (e, stacktrace) {
      log('[NotificationService] Error fetching post author or sending author notification: $e\n$stacktrace');
    }

    // --- 2. Send Notifications to Tagged Users (if any) ---
    if (taggedUserIds != null && taggedUserIds.isNotEmpty) {
      log('[NotificationService] Sending tag notifications to users: $taggedUserIds');
      final uniqueTaggedIds = taggedUserIds.toSet();
      uniqueTaggedIds.remove(commenterUserId);
      if (postAuthorId != null) {
        uniqueTaggedIds.remove(postAuthorId);
      }

      for (final taggedUserId in uniqueTaggedIds) {
        log('[NotificationService] Sending comment tag notification to user $taggedUserId');
        await _sendNotificationViaBackend(
          recipientUserId: taggedUserId,
          actorUserId: commenterUserId,
          actorDisplayName: commenterDisplayName,
          postId: postId,
          commentId: commentId,
          commentText: null,
          hasImage: hasImage,
          notificationType: 'comment_tag',
        );
      }
      log('[NotificationService] Finished sending comment tag notifications.');
    }
  }

  // --- Method to send Like Notification ---
  Future<void> sendLikeNotification({
    required String postAuthorId,
    required String likerUserId,
    required String likerDisplayName,
    required String postId,
  }) async {
    // Prevent self-notification
    if (postAuthorId == likerUserId) {
      log('[NotificationService] User $likerUserId liked their own post $postId. No notification sent.');
      return;
    }

    log('[NotificationService] Preparing like notification: User $likerUserId liked post $postId by user $postAuthorId');

    // Use the existing backend sender, adapting the payload
    await _sendNotificationViaBackend(
      recipientUserId: postAuthorId,
      actorUserId: likerUserId,
      actorDisplayName: likerDisplayName,
      postId: postId,
      notificationType: 'like', // Define a specific type for likes
      // Pass null for comment-specific fields
      commentId: null,
      commentText: null,
      hasImage: null,
    );
  }

  // --- Method to send Message Notification ---
  Future<void> sendMessageNotification({
    required String recipientUserId,
    required String senderUserId,
    required String senderDisplayName,
    required String messageId, // ID of the message itself
    required String messageText, // The text content
    required bool hasText, // Flag indicating if there is text
    required bool hasImage, // Flag indicating if there is an image
  }) async {
    // Prevent self-notification
    if (recipientUserId == senderUserId) {
      log('[NotificationService] Sender and recipient are the same ($senderUserId). No message notification sent.');
      return;
    }

    log('[NotificationService] Preparing message notification: Sender $senderUserId ($senderDisplayName) -> Recipient $recipientUserId, Message $messageId');

    // Dynamically set title and body based on content
    String title = senderDisplayName;
    String body;
    if (hasImage && !hasText) {
      body = '$senderDisplayName sent you an image.';
    } else if (hasImage && hasText) {
      body = messageText.length > 80
          ? '${messageText.substring(0, 77)}... (Image)'
          : '$messageText (Image)';
    } else {
      body = messageText.isEmpty
          ? '$senderDisplayName sent a reply.'
          : (messageText.length > 100
              ? '${messageText.substring(0, 97)}...'
              : messageText);
    }

    // Use the existing backend sender
    await _sendNotificationViaBackend(
      recipientUserId: recipientUserId,
      actorUserId: senderUserId,
      actorDisplayName: senderDisplayName,
      postId: messageId, // Pass messageId as postId for the backend endpoint
      notificationType: 'message', // Define a specific type for messages
      // Pass message-specific details (might be redundant if postId is messageId)
      commentId: messageId,
      commentText: messageText, // Full text
      hasImage: hasImage,
      // Pass dynamic title/body if backend doesn't generate them
      // customTitle: title,
      // customBody: body,
    );
  }

  // --- Centralized Backend Notification Sender (Now Private within Service) ---
  Future<void> _sendNotificationViaBackend({
    required String recipientUserId,
    required String actorUserId,
    required String actorDisplayName,
    required String postId,
    required String notificationType,
    String? commentId,
    String? commentText,
    bool? hasImage,
    String? customTitle, // Optional custom title
    String? customBody, // Optional custom body
  }) async {
    if (_backendBaseUrl == null) {
      log('[NotificationService] Error: BACKEND_URL not found. Cannot send notification.');
      return;
    }
    // Assuming the unified endpoint name based on previous code
    final String notificationUrl =
        '$_backendBaseUrl/api/send-like-notification';

    String title = customTitle ?? ''; // Use custom title if provided
    String body = customBody ?? ''; // Use custom body if provided

    if (title.isEmpty || body.isEmpty) {
      // Generate title/body only if not provided
      switch (notificationType) {
        case 'comment':
          if (hasImage == true &&
              (commentText == null || commentText.isEmpty)) {
            title = '$actorDisplayName sent an image on your post!';
            body = '$actorDisplayName sent an image.';
          } else if (hasImage == true) {
            title = '$actorDisplayName commented with an image!';
            body = commentText != null && commentText.length > 80
                ? '${commentText.substring(0, 77)}... (image attached)'
                : '$commentText (image attached)';
          } else {
            title = '$actorDisplayName commented on your post!';
            body = commentText != null && commentText.length > 100
                ? '${commentText.substring(0, 97)}...'
                : commentText ?? '';
          }
          break;
        case 'comment_tag':
          title = '$actorDisplayName tagged you in a comment';
          body = 'Tap to view the post and comment.';
          if (hasImage == true &&
              (commentText == null || commentText.isEmpty)) {
            body = '$actorDisplayName tagged you in a comment with an image.';
          } else if (hasImage == true) {
            body =
                '$actorDisplayName tagged you in a comment with text and an image.';
          }
          break;
        case 'like': // Add case for 'like' notifications
          title = '$actorDisplayName liked your post!';
          body = '$actorDisplayName liked your post.'; // Simple body
          break;
        case 'message': // Add case for 'message' notifications
          // Generate title/body based on content flags (moved from MessageProvider)
          final msgHasImage = hasImage ?? false;
          final msgHasText = commentText != null && commentText.isNotEmpty;
          final msgText = commentText ?? '';

          title = actorDisplayName;
          if (msgHasImage && !msgHasText) {
            body = '$actorDisplayName sent you an image.';
          } else if (msgHasImage && msgHasText) {
            body = msgText.length > 80
                ? '${msgText.substring(0, 77)}... (Image)'
                : '$msgText (Image)';
          } else {
            body = msgText.isEmpty
                ? '$actorDisplayName sent a reply.'
                : (msgText.length > 100
                    ? '${msgText.substring(0, 97)}...'
                    : msgText);
          }
          break;
        default:
          log('[NotificationService] Warning: Unknown notificationType: $notificationType');
          title = 'New Notification';
          body = 'You have a new notification.';
      }
    }

    try {
      final response = await _httpClient.post(
        Uri.parse(notificationUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(<String, dynamic>{
          'recipientUserId': recipientUserId,
          // Map actor details to expected backend fields
          'likerUserId':
              actorUserId, // Assuming backend uses this field for the actor
          'commenterDisplayName': actorDisplayName,
          'postId': postId,
          'notificationType': notificationType,
          'commentId': commentId,
          'commentText': commentText,
          'hasImage': hasImage,
          'notificationTitle': title,
          'notificationBody': body,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        log('[NotificationService] ($notificationType) Notification sent successfully via backend to $recipientUserId.');
      } else {
        log('[NotificationService] Error sending ($notificationType) notification via backend to $recipientUserId: ${response.statusCode} ${response.reasonPhrase} ${response.body}');
      }
    } catch (e, stacktrace) {
      log('[NotificationService] Exception sending ($notificationType) notification via backend: $e\n$stacktrace');
    }
  }
}
