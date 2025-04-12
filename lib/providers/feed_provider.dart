import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'dart:convert'; // Add import for jsonDecode, base64Decode
import 'dart:typed_data'; // Add import for Uint8List
// Adjust the import path based on your project structure if needed
import '../models/post_model.dart'; // Assuming Post model might be moved later

// Or if Post is still in feed_screen.dart:
// import '../screens/feed_screen.dart';

class FeedProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final List<Post> _loadedPosts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  int _currentOffset = 0;
  static const int _fetchLimit = 10;

  // --- Getters for UI ---
  List<Post> get posts => List.unmodifiable(_loadedPosts); // Return unmodifiable list
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMorePosts => _hasMorePosts;

  // --- Data Fetching Logic ---

  Future<void> fetchInitialPosts({bool forceRefresh = false}) async {
    // Avoid unnecessary fetches if already loading or if posts exist and not forcing refresh
    if (_isLoading || (_loadedPosts.isNotEmpty && !forceRefresh)) return;

    _isLoading = true;
    if (forceRefresh) {
        _loadedPosts.clear();
        _currentOffset = 0;
        _hasMorePosts = true;
    }
    notifyListeners(); // Notify UI about loading start and potential list clearing

    try {
      final newPosts = await _fetchPosts(limit: _fetchLimit, offset: 0);
       if (forceRefresh) { // Only replace if refreshing
           _loadedPosts.clear(); // Clear again just in case
       }
      _loadedPosts.addAll(newPosts);
      _currentOffset = newPosts.length;
      _hasMorePosts = newPosts.length == _fetchLimit;
    } catch (e) {
      log('Error during initial fetch in Provider: $e');
      // Optionally handle error state here, e.g., set an error message string
      _hasMorePosts = false; // Stop trying to load more on error
    } finally {
      _isLoading = false;
      notifyListeners(); // Notify UI about loading end and data update
    }
  }

  Future<void> loadMorePosts() async {
    if (_isLoadingMore || !_hasMorePosts || _isLoading) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final newPosts = await _fetchPosts(limit: _fetchLimit, offset: _currentOffset);
      _loadedPosts.addAll(newPosts);
      _currentOffset += newPosts.length;
      _hasMorePosts = newPosts.length == _fetchLimit;
    } catch (e) {
      log('Error loading more posts in Provider: $e');
      _hasMorePosts = false; // Stop trying to load more on error
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<List<Post>> _fetchPosts({required int limit, required int offset}) async {
    try {
      final response = await _supabase
          .from('posts')
          .select(
            'post_id, user_id, text_content, created_at, media_content, reported',
          )
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // Response might be null if there's an issue, handle gracefully
      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(response ?? []);

      log('Fetched posts (Provider): offset=$offset, limit=$limit, count=${data.length}');

      final List<Post> posts = [];
      for (var item in data) {
        try {
          posts.add(Post.fromJson(item));
        } catch (e) {
          log('Error parsing post item (Provider): $item, error: $e');
          // Skip invalid items
        }
      }
      log('Parsed posts (Provider): ${posts.length}');
      return posts;
    } catch (e, stacktrace) {
      log('Error fetching posts (Provider) (offset=$offset, limit=$limit): $e\n$stacktrace');
      rethrow; // Re-throw to be caught by calling methods
    }
  }

  // --- Post Actions ---

  // Return bool for success/failure, UI will handle SnackBar
  Future<bool> reportPost(String postId) async {
     log('Reporting post (Provider) with ID: $postId');
     try {
        await _supabase
            .from('posts')
            .update({'reported': true})
            .eq('post_id', postId);
        log('Successfully marked post $postId as reported (Provider).');

        // Optimistically update local state
        final index = _loadedPosts.indexWhere((p) => p.id == postId);
        if (index != -1) {
           _loadedPosts[index] = Post( // Create new instance
             id: _loadedPosts[index].id,
             userId: _loadedPosts[index].userId,
             textContent: _loadedPosts[index].textContent,
             createdAt: _loadedPosts[index].createdAt,
             imageList: _loadedPosts[index].imageList,
             reported: true,
           );
           log('Updated local post $postId state to reported=true (Provider)');
           notifyListeners(); // Notify UI of the change
        }
        return true; // Success
     } catch (e) {
        log('Error reporting post $postId (Provider): $e');
        return false; // Failure
     }
  }

  // Return bool for success/failure
  Future<bool> deletePost(String postId) async {
    log('Attempting to delete post (Provider) with ID: $postId');
    try {
      await _supabase.from('posts').delete().eq('post_id', postId);
      log('Supabase delete successful (Provider) for post ID: $postId');

      // Remove from local list
      final initialLength = _loadedPosts.length;
      _loadedPosts.removeWhere((post) => post.id == postId);
      // Correct the check: see if length decreased
      if (_loadedPosts.length < initialLength) { 
         log('Post removed from local list state (Provider). Count: ${_loadedPosts.length}');
         notifyListeners(); // Notify UI of the removal
      }
      return true; // Success
    } catch (e) {
      log('Error deleting post $postId (Provider): $e');
      return false; // Failure
    }
  }
}
