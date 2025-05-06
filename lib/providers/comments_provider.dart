import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import '../models/comment_model.dart';
import '../services/auth_service.dart'; // To get current user ID
import 'feed_provider.dart'; // To potentially update comment count
import '../models/post_model.dart';
import 'dart:convert'; // For jsonEncode and base64Encode
import 'dart:typed_data'; // For Uint8List
import '../services/notification_service.dart'; // Import the new service
import '../services/profile_service.dart'; // Import the profile service

class CommentsProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();
  final FeedProvider _feedProvider; // Reference to update comment count
  final NotificationService _notificationService =
      NotificationService(); // Add instance
  final ProfileService _profileService =
      ProfileService(); // Add ProfileService instance

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
            // Let ProfileService handle caching logic
            // .where((userId) => !_displayNameCache.containsKey(userId))
            .toSet();

        // Add post author ID if available
        if (postAuthorId != null) {
          userIdsToFetch.add(postAuthorId);
        }

        // Fetch profiles using ProfileService if needed
        if (userIdsToFetch.isNotEmpty) {
          log('[CommentsProvider] Prefetching profiles for ${userIdsToFetch.length} users via ProfileService.');
          await _profileService.prefetchDisplayNames(userIdsToFetch);
          log('[CommentsProvider] Finished prefetching profiles.');
        } else {
          log('[CommentsProvider] No new profiles needed according to comment/post data.');
        }

        // Process into the temporary list using ProfileService for names
        log('[CommentsProvider] Starting to process ${commentData.length} comment items.');
        fetchedComments = []; // Initialize list BEFORE loop
        for (var item in commentData) {
          try {
            final commentUserId = item['user_id'] as String;
            final isCommentAuthor =
                postAuthorId != null && commentUserId == postAuthorId;
            // Get display name directly from ProfileService (should be cached now)
            final fetchedDisplayName =
                await _profileService.getDisplayName(commentUserId);

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
      // Fetch commenter display name using ProfileService
      final commenterDisplayName =
          await _profileService.getDisplayName(userId) ?? 'Someone';

      // --- Optimistic UI Update ---
      try {
        // Determine if the commenter is the post author (needed for Comment model)
        final postAuthorIdForCheck =
            await _getPostAuthorId(postId); // Helper needed
        final isCommentAuthor =
            postAuthorIdForCheck != null && userId == postAuthorIdForCheck;

        final newComment = Comment.fromJson(
          response, // Use the response data from the insert
          isCommentAuthor: isCommentAuthor,
          fetchedDisplayName: commenterDisplayName,
        );
        _comments.insert(0, newComment); // Add to the beginning of the list
        log('[CommentsProvider] Optimistically added comment ${newComment.id} locally.');
        // Notify FeedProvider about the new comment count
        _feedProvider.incrementCommentCount(postId);
        log('[CommentsProvider] Incremented comment count in FeedProvider for post $postId.');
      } catch (e, stacktrace) {
        log('[CommentsProvider] Error constructing or adding comment locally after DB insert: $e\\n$stacktrace');
        // Consider refetching if local update fails? Or just log?
        await fetchComments(postId); // Fallback to refetch on error
        return false; // Indicate potential inconsistency
      }
      // --- End Optimistic UI Update ---

      // Call the dedicated NotificationService
      await _notificationService.sendCommentNotifications(
        postId: postId,
        commenterUserId: userId,
        commenterDisplayName: commenterDisplayName,
        commentId: newCommentId,
        commentText: newCommentText,
        hasImage: imageBytes != null,
        taggedUserIds: taggedUserIds, // <-- Pass tagged IDs here
      );
      // -------------------------

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

      // --- Optimistic UI Update ---
      final originalIndex = _comments.indexWhere((c) => c.id == commentId);
      if (originalIndex != -1) {
        _comments.removeAt(originalIndex);
        log('[CommentsProvider] Optimistically removed comment $commentId locally.');
        // Notify FeedProvider about the changed comment count
        _feedProvider.decrementCommentCount(commentToDelete.postId);
        log('[CommentsProvider] Decremented comment count in FeedProvider for post ${commentToDelete.postId}.');
      } else {
        log('[CommentsProvider] Warning: Deleted comment $commentId not found in local list after DB delete.');
        // Fallback to refetch if local state is inconsistent
        await fetchComments(commentToDelete.postId);
        success = true; // Still successful DB op, but UI might jump
        // Note: We exit finally block below, so need to ensure notifyListeners is called
        _isDeletingComment = false;
        notifyListeners(); // Update UI state immediately
        return success;
      }
      // --- End Optimistic UI Update ---

      success = true; // Mark success after DB deletion AND local removal
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

  // Helper to get post author ID (could be cached or fetched)
  // NOTE: This might duplicate logic if fetchComments already gets it.
  // Consider caching post author IDs similar to display names if frequently needed.
  Future<String?> _getPostAuthorId(String postId) async {
    // Simple fetch for now, could be optimized with caching
    try {
      final postResponse = await _supabase
          .from('posts')
          .select('user_id')
          .eq('post_id', postId)
          .maybeSingle(); // Use maybeSingle
      return postResponse?['user_id'] as String?;
    } catch (e) {
      log('[CommentsProvider] Error fetching post author ID for check: $e');
      return null;
    }
  }
}
