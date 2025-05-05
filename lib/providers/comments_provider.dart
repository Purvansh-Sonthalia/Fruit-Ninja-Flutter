import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import '../models/comment_model.dart';
import '../services/auth_service.dart'; // To get current user ID
import 'feed_provider.dart'; // To potentially update comment count
import '../models/post_model.dart';
import 'dart:convert'; // For jsonEncode and base64Encode
import 'dart:typed_data'; // For Uint8List
import 'package:http/http.dart' as http; // For HTTP requests
import 'package:flutter_dotenv/flutter_dotenv.dart'; // For environment variables

class CommentsProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();
  final FeedProvider _feedProvider; // Reference to update comment count

  List<Comment> _comments = [];
  bool _isLoading = false;
  bool _isAddingComment = false;
  bool _isDeletingComment = false; // Add deleting state
  String? _currentPostId;

  // Map to cache fetched display names <userId, displayName>
  final Map<String, String?> _displayNameCache = {};

  // Constructor requires FeedProvider
  CommentsProvider(this._feedProvider);

  // --- Getters ---
  List<Comment> get comments => List.unmodifiable(_comments);
  bool get isLoading => _isLoading;
  bool get isAddingComment => _isAddingComment;
  bool get isDeletingComment => _isDeletingComment; // Getter for deleting state
  String? get currentPostId => _currentPostId;

  // --- Methods ---

  // Fetch comments for a specific post
  Future<void> fetchComments(String postId) async {
    log('[CommentsProvider] fetchComments STARTING for postId: $postId. Current count: ${_comments.length}, isLoading: $_isLoading');

    _isLoading = true;
    _currentPostId = postId;
    notifyListeners(); // Notify that loading has STARTED

    log('[CommentsProvider] Fetching comments AND post author for post: $postId');
    List<Comment>? fetchedComments;
    String? postAuthorId;

    try {
      // Fetch comments and post author concurrently
      final results = await Future.wait([
        _supabase
            .from('comments')
            // Select comment_media instead of image_url
            .select(
                'comment_id, post_id, user_id, comment_text, created_at, comment_media')
            .eq('post_id', postId)
            .order('created_at', ascending: true),
        _supabase
            .from('posts')
            .select('user_id')
            .eq('post_id', postId)
            .maybeSingle(),
      ]);

      log('[CommentsProvider] Supabase fetch complete for comments and post author.');

      // Directly cast results to their correct types
      final List<Map<String, dynamic>> commentData =
          (results[0] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final Map<String, dynamic>? postData =
          results[1] as Map<String, dynamic>?;

      log('[CommentsProvider] Raw comment data count: ${commentData.length}');

      postAuthorId = postData?['user_id'] as String?;
      log('[CommentsProvider] Post author ID: $postAuthorId');

      if (commentData.isEmpty) {
        log('[CommentsProvider] No comments found in DB. Setting local comments to empty.');
        _comments = []; // No comments found
        fetchedComments = []; // Explicitly set fetchedComments too
      } else {
        // Extract unique user IDs from comments needing profile lookup
        final Set<String> userIdsToFetch = commentData
            .map((item) => item['user_id'] as String)
            .where((userId) => !_displayNameCache.containsKey(userId))
            .toSet();
        // Add post author ID if not already cached
        if (postAuthorId != null &&
            !_displayNameCache.containsKey(postAuthorId)) {
          userIdsToFetch.add(postAuthorId);
        }

        // Fetch profiles if needed
        if (userIdsToFetch.isNotEmpty) {
          log('[CommentsProvider] Fetching profiles for ${userIdsToFetch.length} users in comments.');
          try {
            final profilesResponse = await _supabase
                .from('profiles')
                .select('user_id, display_name')
                .inFilter('user_id', userIdsToFetch.toList());

            final List<dynamic> profilesData =
                profilesResponse as List<dynamic>? ?? [];
            log('[CommentsProvider] Raw profiles data count: ${profilesData.length}');
            // Update cache
            for (var profile in profilesData) {
              final userId = profile['user_id'] as String;
              final displayName = profile['display_name'] as String?;
              _displayNameCache[userId] = displayName;
            }
            // Cache missing profiles as null
            for (var userId in userIdsToFetch) {
              _displayNameCache.putIfAbsent(userId, () => null);
            }
            log('[CommentsProvider] Finished caching profiles. Cache size: ${_displayNameCache.length}');
          } catch (profileError) {
            log('[CommentsProvider] ERROR fetching profiles for comments: $profileError');
            // Cache missing profiles as null
            for (var userId in userIdsToFetch) {
              _displayNameCache.putIfAbsent(userId, () => null);
            }
          }
        } else {
          log('[CommentsProvider] No new profiles needed for comments.');
        }

        // Process into the temporary list using cached names
        log('[CommentsProvider] Starting to process ${commentData.length} comment items.');
        fetchedComments = []; // Initialize list BEFORE loop
        for (var item in commentData) {
          try {
            final commentUserId = item['user_id'] as String;
            final isCommentAuthor =
                postAuthorId != null && commentUserId == postAuthorId;
            final fetchedDisplayName = _displayNameCache[commentUserId];

            fetchedComments.add(Comment.fromJson(
              item,
              isCommentAuthor: isCommentAuthor,
              fetchedDisplayName: fetchedDisplayName,
            ));
          } catch (e) {
            log('[CommentsProvider] Error PARSING comment item: $item, error: $e'); // Specific log for parsing error
          }
        }
        log('[CommentsProvider] Finished processing comments. Parsed count: ${fetchedComments.length}');
        _comments = fetchedComments; // Assign the fully processed list
        log('[CommentsProvider] Assigned fetchedComments to _comments. New count: ${_comments.length}');
      }
    } catch (e, stacktrace) {
      // Catch stacktrace
      log('[CommentsProvider] CRITICAL ERROR fetching comments for post $postId: $e\n$stacktrace');
      _comments = []; // Clear comments on error
      fetchedComments = null; // Indicate error occurred
      log('[CommentsProvider] Cleared _comments due to error.');
    } finally {
      _isLoading = false;
      log('[CommentsProvider] Setting isLoading=false. Final comment count: ${_comments.length}');
      notifyListeners(); // Notify UI that loading is finished (list may or may not have changed)
    }
  }

  // Add a new comment
  Future<bool> addComment(
    String postId,
    String commentText, {
    Uint8List? imageBytes,
    List<String>? taggedUserIds, // <-- Add taggedUserIds parameter
  }) async {
    final userId = _authService.userId;
    if (userId == null) {
      log('Error: User not logged in, cannot add comment.');
      return false;
    }
    if (commentText.trim().isEmpty && imageBytes == null) {
      log('Error: Comment text cannot be empty if no image is provided.');
      return false;
    }
    if (_isAddingComment) return false;

    _isAddingComment = true;
    notifyListeners();
    log('Adding comment to post: $postId (with image: ${imageBytes != null}, tags: ${taggedUserIds?.length ?? 0})');

    String? imageBase64;

    try {
      if (imageBytes != null) {
        log('Encoding comment image to Base64...');
        try {
          imageBase64 = base64Encode(imageBytes);
          log('Image encoded successfully. Base64 length: ${imageBase64.length}');
        } catch (e) {
          log('Error encoding image to Base64: $e');
          _isAddingComment = false;
          notifyListeners();
          return false;
        }
      }

      log('Inserting comment data into DB...');
      final commentToInsert = {
        'post_id': postId,
        'user_id': userId,
        'comment_text': commentText.trim().isEmpty ? null : commentText.trim(),
        'comment_media': imageBase64,
        'tagged_user_ids': taggedUserIds?.isNotEmpty ?? false
            ? taggedUserIds
            : null, // <-- Add tagged IDs
      };
      // Avoid logging full base64 and potentially large tag list
      log('Comment data to insert (Base64: ${imageBase64 != null}, Tags: ${taggedUserIds?.length ?? 0})...');

      final response = await _supabase
          .from('comments')
          .insert(commentToInsert)
          .select()
          .single();
      // Avoid logging response data directly
      log('Successfully added comment to DB for post $postId. New comment ID: ${response['comment_id']}');

      // --- Send Notifications ---
      final newCommentId = response['comment_id'] as String;
      final newCommentText = response['comment_text'] as String? ?? '';
      // Fetch commenter display name (might already be cached from fetchComments)
      final commenterDisplayName = _displayNameCache[userId] ??
          await _fetchDisplayName(userId) ??
          'Someone';
      await _sendCommentNotifications(
        postId: postId,
        commenterUserId: userId,
        commenterDisplayName: commenterDisplayName,
        commentId: newCommentId,
        commentText: newCommentText,
        hasImage: imageBytes != null,
        taggedUserIds: taggedUserIds, // <-- Pass tagged IDs here
      );
      // -------------------------

      await fetchComments(postId);
      return true;
    } catch (e, stacktrace) {
      log('Error during addComment process (post $postId): $e\n$stacktrace');
      return false;
    } finally {
      _isAddingComment = false;
      if (!isAddingComment) {
        notifyListeners();
      }
    }
  }

  // Delete a comment
  Future<bool> deleteComment(String commentId) async {
    final userId = _authService.userId;
    if (userId == null) {
      log('Error: User not logged in, cannot delete comment.');
      return false;
    }
    if (_isDeletingComment)
      return false; // Prevent multiple simultaneous deletions

    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index == -1) {
      log('Error: Comment $commentId not found locally for deletion.');
      return false; // Comment not found locally
    }

    final commentToDelete = _comments[index];
    // No need to track imageUrlToDelete anymore

    // Authorization check: Ensure the current user owns the comment
    if (commentToDelete.userId != userId) {
      log('Error: User $userId is not authorized to delete comment $commentId.');
      return false; // Not authorized
    }

    _isDeletingComment = true;
    notifyListeners(); // Notify UI about deletion STARTING
    log('Attempting to delete comment: $commentId for post: ${commentToDelete.postId}');

    bool success = false;
    try {
      // Delete comment from Database
      await _supabase.from('comments').delete().eq('comment_id', commentId);
      log('Successfully deleted comment $commentId from Supabase.');

      // No need to delete from Storage anymore

      success = true; // Mark success after DB deletion

      // --- Refetch comments after successful delete ---
      await fetchComments(commentToDelete.postId);
      // ---------------------------------------------
    } catch (e, stacktrace) {
      log('Error deleting comment $commentId from Supabase: $e\n$stacktrace');
      success = false; // Mark failure
    } finally {
      _isDeletingComment = false;
      if (!success) {
        notifyListeners(); // Ensure loading state is updated if fetch wasn't called
      }
    }
    return success;
  }

  // Clear comments when leaving the comments view
  void clearComments() {
    log('[CommentsProvider] clearComments called. Current count: ${_comments.length}');
    _comments = [];
    _currentPostId = null;
    _isLoading = false;
    _isAddingComment = false;
    _isDeletingComment = false;
    log('[CommentsProvider] Cleared comments state.');
  }

  // Helper to fetch display name if not in cache (used in notification sending)
  Future<String?> _fetchDisplayName(String userIdToFetch) async {
    if (_displayNameCache.containsKey(userIdToFetch)) {
      return _displayNameCache[
          userIdToFetch]; // Return cached value if available
    }
    log('[DisplayNameCache] Cache miss for $userIdToFetch, fetching from DB.');
    try {
      final response = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('user_id', userIdToFetch)
          .maybeSingle();
      if (response != null && response['display_name'] != null) {
        final name = response['display_name'] as String;
        _displayNameCache[userIdToFetch] = name; // Cache the fetched name
        return name;
      } else {
        _displayNameCache[userIdToFetch] = null; // Cache null if not found
        return null;
      }
    } catch (e) {
      log('[DisplayNameCache] Error fetching display name for $userIdToFetch: $e');
      _displayNameCache[userIdToFetch] = null; // Cache null on error
      return null;
    }
  }

  // Renamed and updated function to handle multiple notification types
  Future<void> _sendCommentNotifications({
    required String postId,
    required String commenterUserId,
    required String commenterDisplayName,
    required String commentId,
    required String commentText,
    required bool hasImage,
    List<String>? taggedUserIds,
  }) async {
    // --- 1. Send Notification to Post Author (if not self-comment) ---
    log('[Notification] Preparing notification for comment $commentId on post $postId...');
    String? postAuthorId;
    try {
      final postResponse = await _supabase
          .from('posts')
          .select('user_id')
          .eq('post_id', postId)
          .single();
      postAuthorId = postResponse['user_id'] as String?;

      if (postAuthorId != null && postAuthorId != commenterUserId) {
        log('[Notification] Sending comment notification to post author $postAuthorId');
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
        log('[Notification] Post author not found or is the commenter ($postAuthorId). No notification sent to author.');
      }
    } catch (e, stacktrace) {
      log('[Notification] Error fetching post author or sending author notification: $e\n$stacktrace');
    }

    // --- 2. Send Notifications to Tagged Users (if any) ---
    if (taggedUserIds != null && taggedUserIds.isNotEmpty) {
      log('[Notification] Sending tag notifications to users: $taggedUserIds');
      // Use Set to avoid notifying the same user multiple times if tagged multiple times (and exclude author/commenter)
      final uniqueTaggedIds = taggedUserIds.toSet();
      uniqueTaggedIds
          .remove(commenterUserId); // Don't notify commenter of their own tag
      if (postAuthorId != null) {
        uniqueTaggedIds.remove(
            postAuthorId); // Don't send separate tag notification if they are the author
      }

      for (final taggedUserId in uniqueTaggedIds) {
        log('[Notification] Sending comment tag notification to user $taggedUserId');
        await _sendNotificationViaBackend(
          recipientUserId: taggedUserId,
          actorUserId: commenterUserId,
          actorDisplayName: commenterDisplayName,
          postId: postId,
          commentId: commentId,
          // Comment text might be less relevant for a tag notification
          commentText:
              null, // Or maybe a snippet: commentText.substring(0, min(commentText.length, 30)) + (commentText.length > 30 ? '...' : ''),
          hasImage: hasImage, // Still relevant to know if image was involved
          notificationType:
              'comment_tag', // *** IMPORTANT: Type for tagged user ***
        );
        // Optional delay
        // await Future.delayed(const Duration(milliseconds: 50));
      }
      log('[Notification] Finished sending comment tag notifications.');
    }
  }

  // --- Centralized Backend Notification Sender ---
  Future<void> _sendNotificationViaBackend({
    required String recipientUserId,
    required String actorUserId, // User performing the action (commenter)
    required String actorDisplayName,
    required String postId,
    required String notificationType, // e.g., 'comment', 'comment_tag'
    String? commentId, // Nullable for non-comment specific tags if needed later
    String? commentText, // Nullable
    bool? hasImage, // Nullable
  }) async {
    final String? backendBaseUrl = dotenv.env['BACKEND_URL'];
    if (backendBaseUrl == null) {
      log('[Notification] Error: BACKEND_URL not found. Cannot send notification.');
      return;
    }
    final String notificationUrl =
        '$backendBaseUrl/api/send-like-notification'; // Using the unified endpoint

    // --- Dynamic Title/Body based on Type ---
    String title;
    String body;
    switch (notificationType) {
      case 'comment':
        if (hasImage == true && (commentText == null || commentText.isEmpty)) {
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
              : commentText ?? ''; // Default to empty string if somehow null
        }
        break;
      case 'comment_tag':
        title = '$actorDisplayName tagged you in a comment';
        body = 'Tap to view the post and comment.'; // Generic body for tag
        // Optionally include comment snippet or image indication
        if (hasImage == true && (commentText == null || commentText.isEmpty)) {
          body = '$actorDisplayName tagged you in a comment with an image.';
        } else if (hasImage == true) {
          body =
              '$actorDisplayName tagged you in a comment with text and an image.';
        }
        break;
      default: // Fallback for unknown types
        log('[Notification] Warning: Unknown notificationType: $notificationType');
        title = 'New Notification';
        body = 'You have a new notification.';
    }
    // --- End Dynamic Title/Body ---

    try {
      final response = await http.post(
        Uri.parse(notificationUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(<String, dynamic>{
          'recipientUserId': recipientUserId,
          'likerUserId': actorUserId, // Using this field for the actor
          'postId': postId,
          'notificationType': notificationType,
          'commenterDisplayName': actorDisplayName, // Name of the actor
          'commentId': commentId,
          'commentText': commentText,
          'hasImage': hasImage,
          'notificationTitle': title,
          'notificationBody': body,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        log('[Notification] ($notificationType) Notification sent successfully to $recipientUserId.');
      } else {
        log('[Notification] ($notificationType) Failed to send notification to $recipientUserId. Status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e, stacktrace) {
      log('[Notification] ($notificationType) Error sending notification to $recipientUserId: $e\n$stacktrace');
    }
  }
  // --- End Centralized Sender ---
}
