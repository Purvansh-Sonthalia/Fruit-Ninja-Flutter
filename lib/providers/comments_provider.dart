import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import '../models/comment_model.dart';
import '../services/auth_service.dart'; // To get current user ID
import 'feed_provider.dart'; // To potentially update comment count

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
          .eq('post_id', postId)
          .order('created_at', ascending: true); 

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(response ?? []);
      
      // Process into the temporary list
      fetchedComments = []; 
      for (var item in data) {
        try {
          fetchedComments.add(Comment.fromJson(item));
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

      // Parse the newly added comment
      // final newComment = Comment.fromJson(response);
      // _comments.add(newComment); // Remove optimistic add
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
} 