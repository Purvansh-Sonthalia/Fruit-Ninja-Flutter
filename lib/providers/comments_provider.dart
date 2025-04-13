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
          .select('comment_id, post_id, user_id, comment_text, created_at, comment_media') 
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
      final List<Map<String, dynamic>> commentData = (results[0] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final Map<String, dynamic>? postData = results[1] as Map<String, dynamic>?;
      
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
        if (postAuthorId != null && !_displayNameCache.containsKey(postAuthorId)) {
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
              
              final List<dynamic> profilesData = profilesResponse as List<dynamic>? ?? [];
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
            final isCommentAuthor = postAuthorId != null && commentUserId == postAuthorId;
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

    } catch (e, stacktrace) { // Catch stacktrace
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
  Future<bool> addComment(String postId, String commentText, {Uint8List? imageBytes}) async {
    final userId = _authService.userId;
    if (userId == null) {
      log('Error: User not logged in, cannot add comment.');
      return false;
    }
    // Allow empty text if image is present
    if (commentText.trim().isEmpty && imageBytes == null) {
       log('Error: Comment text cannot be empty if no image is provided.');
      return false;
    }
    if (_isAddingComment) return false;

    _isAddingComment = true;
    notifyListeners(); // Notify START loading
    log('Adding comment to post: $postId (with image: ${imageBytes != null})');

    String? imageBase64; // Variable to store the base64 string

    try {
      // --- Encode Image to Base64 if provided --- 
      if (imageBytes != null) {
        log('Encoding comment image to Base64...');
        try {
          imageBase64 = base64Encode(imageBytes);
          log('Image encoded successfully. Base64 length: ${imageBase64.length}');
          // Optional: Check Base64 string length if needed (e.g., against DB limits)
        } catch (e) {
           log('Error encoding image to Base64: $e');
           _isAddingComment = false;
           notifyListeners(); // Update loading state
           return false; // Indicate failure due to encoding error
        }
      }
      // --- End Image Encoding --- 

      // --- Insert Comment Data --- 
      log('Inserting comment data into DB...');
      final commentToInsert = {
        'post_id': postId,
        'user_id': userId,
        'comment_text': commentText.trim().isEmpty ? null : commentText.trim(),
        'comment_media': imageBase64, // Add the Base64 string here (null if no image)
      };
      log('Comment data to insert (Base64 length: ${imageBase64?.length ?? 0})...'); // Avoid logging full base64

      final response = await _supabase
        .from('comments')
        .insert(commentToInsert)
        .select() // Select the newly inserted row
        .single(); // Expecting a single row back
      log('Successfully added comment to DB for post $postId.'); // Avoid logging response data
      // --- End Insert Comment --- 

      // --- Send Notification --- 
      final newCommentId = response['comment_id'];
      final newCommentText = response['comment_text'] ?? ''; // Handle null
      final commenterDisplayName = _displayNameCache[userId] ?? 'Someone';
      await _sendCommentNotification(
        postId,
        userId,
        commenterDisplayName,
        newCommentId,
        newCommentText,
        hasImage: imageBytes != null, // <-- Pass whether image exists
      );
      // -------------------------

      // --- Refetch comments after successful add --- 
      await fetchComments(postId); 
      // -------------------------------------------
      return true; // Return true for overall success

    } catch (e, stacktrace) {
      log('Error during addComment process (post $postId): $e\n$stacktrace');
       return false; // Return false if any part fails
    } finally {
      _isAddingComment = false;
      // Notify listeners will be called by fetchComments if successful, 
      // or explicitly if an error happened before fetchComments
      if (!isAddingComment) {
          notifyListeners(); // Ensure UI updates if there was an early return error
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
    if (_isDeletingComment) return false; // Prevent multiple simultaneous deletions

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
      await _supabase
          .from('comments')
          .delete()
          .eq('comment_id', commentId);
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

  // --- Update Send Comment Notification --- 
  Future<void> _sendCommentNotification(String postId, String commenterUserId, String commenterDisplayName, String commentId, String commentText, {required bool hasImage}) async {
    log('[Notification] Attempting to send comment notification via /api/send-like-notification for comment $commentId on post $postId by user $commenterUserId ($commenterDisplayName), hasImage: $hasImage'); 

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
      final String notificationUrl = '$backendBaseUrl/api/send-like-notification'; // Changed URL
      // -------------------------------

      // 4. Prepare and send the notification payload
      // --- Adjust title and body based on image presence --- 
      String title;
      String body;
      if (hasImage && commentText.isEmpty) {
          title = '$commenterDisplayName sent an image on your post!';
          body = '$commenterDisplayName sent an image.'; // Simple body for image-only
      } else if (hasImage) {
          title = '$commenterDisplayName commented with an image!';
          // Keep comment text in body, maybe truncate differently or add indicator?
          body = commentText.length > 80 
               ? '${commentText.substring(0, 77)}... (image attached)'
               : '$commentText (image attached)'; 
      } else {
          // Original logic for text-only comments
          title = '$commenterDisplayName commented on your post!';
          body = commentText.length > 100 
              ? '${commentText.substring(0, 97)}...'
              : commentText;
      }
      // --- End title/body adjustment --- 

      final response = await http.post(
        Uri.parse(notificationUrl), // Using the unified URL
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(<String, dynamic>{
          'recipientUserId': postAuthorId,      // Post author
          'likerUserId': commenterUserId, // Sending commenter ID as likerUserId
          'postId': postId,                  // ID of the post
          'notificationType': 'comment',     // Explicitly state the type
          'commenterDisplayName': commenterDisplayName, 
          'commentId': commentId,            // ID of the new comment
          'commentText': commentText,        // Full comment text (backend can decide what to use)
          'hasImage': hasImage,              // <-- Send hasImage flag to backend
          'notificationTitle': title,        // Use the dynamically generated title
          'notificationBody': body,          // Use the dynamically generated body
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        log('[Notification] Comment notification sent successfully via /api/send-like-notification.'); 
      } else {
        log(
          '[Notification] Failed to send comment notification via /api/send-like-notification. Status: ${response.statusCode}, Body: ${response.body}', 
        );
      }

    } catch (e, stacktrace) {
       log('[Notification] Error sending comment notification (via like endpoint) for post $postId: $e\n$stacktrace'); 
      // Handle errors gracefully
    }
  }
  // --- End Send Comment Notification ---
} 