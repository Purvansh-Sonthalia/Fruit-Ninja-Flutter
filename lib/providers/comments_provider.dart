import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import '../models/comment_model.dart';
import '../services/auth_service.dart'; // To get current user ID
import 'feed_provider.dart'; // To potentially update comment count
import '../models/post_model.dart';
import 'dart:convert'; // For jsonEncode
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
    // Don't return if already loading, allow refresh
    // if (_isLoading) return; 

    _isLoading = true;
    _currentPostId = postId;
    // --- Remove initial clear and notify --- 
    // _comments = []; 
    // notifyListeners(); 
    // --- UI should rely on _isLoading flag --- 

    log('Fetching comments for post: $postId');
    List<Comment>? fetchedComments; // Use nullable temporary list
    try {
      final response = await _supabase
          .from('comments')
          .select('comment_id, post_id, user_id, comment_text, created_at')
          .eq('post_id', postId) //filter comments by post_id
          .order('created_at', ascending: true); 

      final post = await _supabase
          .from('posts')
          .select('user_id')
          .eq('post_id', postId)
          .single();
      String postAuthor = post['user_id'];

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(response ?? []);
      
      // Process into the temporary list
      fetchedComments = []; 
      for (var item in data) {
        try {
          // Update Comment.fromJson to check if the comment is by the author
          fetchedComments.add(Comment(
            id: item['comment_id'], postId: item['post_id'], userId: item['user_id'], commentText: item['comment_text'],
            createdAt: DateTime.parse(item['created_at']),
            isAuthor: item['user_id'] == postAuthor
          ));
        } catch (e) {
          log('Error parsing comment item: $item, error: $e');
        }
      }
      log('[CommentsProvider] fetchComments FINISHED loading. Fetched ${fetchedComments.length} comments for post $postId');
      // --- Assign ONLY after successful fetch --- 
      _comments = fetchedComments; 
      // -----------------------------------------

    } catch (e) {
      log('Error fetching comments for post $postId: $e');
      _comments = []; // Clear comments on error
      fetchedComments = null; // Indicate error occurred
    } finally {
      _isLoading = false;
      // Final notification happens regardless of success/failure
      notifyListeners(); // Notify UI that loading is finished (list may or may not have changed)
    }
  }

  // Add a new comment
  Future<bool> addComment(String postId, String commentText) async {
    final userId = _authService.userId;
    if (userId == null) {
      log('Error: User not logged in, cannot add comment.');
      return false;
    }
    if (commentText.trim().isEmpty) {
       log('Error: Comment text cannot be empty.');
      return false;
    }
    if (_isAddingComment) return false;

    _isAddingComment = true;
    notifyListeners(); // Notify START loading
    log('Adding comment to post: $postId');

    bool success = false;
    try {
      final response = await _supabase.from('comments').insert({
        'post_id': postId,
        'user_id': userId,
        'comment_text': commentText.trim(),
      }).select() // Select the newly inserted row
      .single(); // Expecting a single row back

      // --- Send Notification --- 
      final newCommentId = response['comment_id'];
      final newCommentText = response['comment_text'];
      await _sendCommentNotification(postId, userId, newCommentId, newCommentText);
      // -------------------------

      log('Successfully added comment to DB for post $postId');
      
      // No need to optimistically update local list if we refetch
      // _feedProvider.incrementCommentCount(postId); // FeedProvider count updated by trigger
      success = true; // Mark as success

      // --- Refetch comments after successful add --- 
      await fetchComments(postId); 
      // -------------------------------------------

    } catch (e) {
      log('Error adding comment to post $postId: $e');
      success = false; // Mark as failure
    } finally {
      _isAddingComment = false;
      // notifyListeners() will be called by fetchComments if it was successful,
      // or here if add failed before calling fetch.
      if (!success) {
         notifyListeners(); // Ensure loading state is updated if fetch wasn't called
      }
    }
    return success;
  }

  // Delete a comment
  Future<bool> deleteComment(String commentId) async {
    final userId = _authService.userId;
    if (userId == null) {
      log('Error: User not logged in, cannot delete comment.');
      return false;
    }
    if (_isDeletingComment) return false; // Prevent multiple simultaneous deletions

    final index = _comments.indexWhere((c) => c.id == commentId);
    if (index == -1) {
      log('Error: Comment $commentId not found locally for deletion.');
      return false; // Comment not found locally
    }

    final commentToDelete = _comments[index];

    // Authorization check: Ensure the current user owns the comment
    if (commentToDelete.userId != userId) {
       log('Error: User $userId is not authorized to delete comment $commentId.');
       return false; // Not authorized
    }

    _isDeletingComment = true;
    notifyListeners(); // Notify UI about deletion STARTING
    log('Attempting to delete comment: $commentId for post: ${commentToDelete.postId}');

    // --- Remove optimistic update --- 
    // _comments.removeAt(index);
    // _feedProvider.decrementCommentCount(commentToDelete.postId);
    // --------------------------------

    bool success = false;
    try {
      await _supabase
          .from('comments')
          .delete()
          .eq('comment_id', commentId);
      log('Successfully deleted comment $commentId from Supabase.');
      success = true; // Mark success

      // --- Refetch comments after successful delete --- 
      await fetchComments(commentToDelete.postId); 
      // ---------------------------------------------

    } catch (e) {
      log('Error deleting comment $commentId from Supabase: $e');
      // --- Remove revert logic --- 
      // _comments.insert(index, commentToDelete); 
      // _feedProvider.incrementCommentCount(commentToDelete.postId); 
      // ---------------------------
      success = false; // Mark failure
    } finally {
      _isDeletingComment = false;
      // notifyListeners() will be called by fetchComments if it was successful,
      // or here if delete failed before calling fetch.
       if (!success) {
         notifyListeners(); // Ensure loading state is updated if fetch wasn't called
       }
    }
    return success;
  }

  // Clear comments when leaving the comments view
  void clearComments() {
    log('[CommentsProvider] clearComments called. Current count: ${_comments.length}'); // Add detailed log
    _comments = [];
    _currentPostId = null;
    _isLoading = false;
    _isAddingComment = false;
    _isDeletingComment = false;
    // Don't notify listeners here usually, as the screen is being disposed
    log('[CommentsProvider] Cleared comments state.');
  }

  // --- Send Comment Notification --- 
  Future<void> _sendCommentNotification(String postId, String commenterUserId, String commentId, String commentText) async {
    log('[Notification] Attempting to send comment notification via /api/send-like-notification for comment $commentId on post $postId by user $commenterUserId'); // Updated log

    String? postAuthorId;
    try {
      // 1. Fetch the post author's ID
      final postResponse = await _supabase
          .from('posts')
          .select('user_id')
          .eq('post_id', postId)
          .single();
      postAuthorId = postResponse['user_id'] as String?;

      if (postAuthorId == null) {
         log('[Notification] Error: Could not find post author for post $postId.');
         return; // Cannot send notification without recipient
      }

      // 2. Prevent self-notification
      if (postAuthorId == commenterUserId) {
        log('[Notification] User $commenterUserId commented on their own post $postId. No notification sent.');
        return;
      }

      // 3. Access the backend URL
      final String? backendBaseUrl = dotenv.env['BACKEND_URL'];
      if (backendBaseUrl == null) {
        log('[Notification] Error: BACKEND_URL not found in .env file.');
        return; // Stop if backend URL is not configured
      }

      // --- Define Backend Endpoint ---
      // IMPORTANT: Using the like notification endpoint for comments as requested.
      final String notificationUrl = '$backendBaseUrl/api/send-like-notification'; // Changed URL
      // -------------------------------

      // 4. Prepare and send the notification payload
      //    Adjusted payload for the unified endpoint.
      final String title = 'New comment on your post!'; // Adjusted title
      // Use the actual comment text, truncated if necessary
      final String body = commentText.length > 100 
          ? '${commentText.substring(0, 97)}...'
          : commentText;

      final response = await http.post(
        Uri.parse(notificationUrl), // Using the unified URL
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(<String, dynamic>{
          // Fields expected by the /api/send-like-notification endpoint (potentially)
          'recipientUserId': postAuthorId,      // Post author
          'likerUserId': commenterUserId, // Sending commenter ID as likerUserId
          'postId': postId,                  // ID of the post
          
          // Additional fields to distinguish comment notifications
          'notificationType': 'comment',     // Explicitly state the type
          'commentId': commentId,            // ID of the new comment
          'commentText': commentText,        // Full comment text

          // Standard notification content fields
          'notificationTitle': title,        // Specific title for comment
          'notificationBody': body,          // Body for the push notification (comment text)
          
          // Add any other relevant data your backend might need
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        log('[Notification] Comment notification sent successfully via /api/send-like-notification.'); // Updated log
      } else {
        log(
          '[Notification] Failed to send comment notification via /api/send-like-notification. Status: ${response.statusCode}, Body: ${response.body}', // Updated log
        );
      }

    } catch (e, stacktrace) {
       log('[Notification] Error sending comment notification (via like endpoint) for post $postId: $e\n$stacktrace'); // Updated log
      // Handle errors gracefully
    }
  }
  // --- End Send Comment Notification ---
} 