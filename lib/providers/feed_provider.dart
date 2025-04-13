import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
// Add import for jsonDecode, base64Decode
// Add import for Uint8List
// Adjust the import path based on your project structure if needed
import '../models/post_model.dart'; // Assuming Post model might be moved later
import 'dart:convert'; // For jsonEncode
import 'package:http/http.dart' as http; // For HTTP requests
import 'package:flutter_dotenv/flutter_dotenv.dart'; // For environment variables

// Or if Post is still in feed_screen.dart:
// import '../screens/feed_screen.dart';

// --- Add AuthService import ---
import '../services/auth_service.dart';

class FeedProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  // --- Add AuthService instance ---
  final AuthService _authService = AuthService(); // Assuming default constructor or singleton
  final List<Post> _loadedPosts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  int _currentOffset = 0;
  static const int _fetchLimit = 10;

  // --- State for liked posts ---
  Set<String> _likedPostIds = {};
  final bool _isLoadingLikes = false;

  // Map to cache fetched display names <userId, displayName>
  final Map<String, String?> _displayNameCache = {};

  // --- Getters for UI ---
  List<Post> get posts => List.unmodifiable(_loadedPosts); // Return unmodifiable list
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMorePosts => _hasMorePosts;
  // Getter for liked post IDs
  Set<String> get likedPostIds => _likedPostIds;

  // --- Data Fetching Logic ---

  // Helper to fetch IDs of posts liked by the current user
  // Modified to return the set of IDs instead of updating state directly
  Future<Set<String>> _fetchUserLikes() async { // <-- Return Set<String>
    final userId = _authService.userId;
    // Loading state (_isLoadingLikes) is now managed by the caller (fetchInitialPosts)
    if (userId == null) {
      log('Cannot fetch likes: User not logged in.');
      return {}; // Return empty set if no user
    }

    log('Fetching user likes for user: $userId');
    // No need for _isLoadingLikes or notifyListeners here

    Set<String> fetchedIds = {};
    try {
      final response = await _supabase
          .from('likes')
          .select('post_id') // Only fetch the post_id
          .eq('user_id', userId);

      final List<dynamic> data = response ?? [];
      // Create a set of post_id strings
      fetchedIds = data.map((item) => item['post_id'] as String).toSet();
      log('Fetched ${fetchedIds.length} liked post IDs.');
    } catch (e) {
      log('Error fetching user likes: $e');
      // Return empty set on error, let caller decide how to handle
      return {};
    }
    // Return the fetched set, state update happens in the caller
    return fetchedIds;
  }

  Future<void> fetchInitialPosts({bool forceRefresh = false}) async {
    // 1. Early exit if already loading or not forcing refresh on existing data
    if (_isLoading || (_loadedPosts.isNotEmpty && !forceRefresh)) return;

    _isLoading = true;
    notifyListeners(); // Notify loading started (e.g., for pull-to-refresh indicator)

    // Store old state in case of failure during forced refresh
    List<Post> oldPosts = forceRefresh ? List.from(_loadedPosts) : [];
    Set<String> oldLikedPostIds = forceRefresh ? Set.from(_likedPostIds) : {};
    int oldOffset = _currentOffset;
    bool oldHasMore = _hasMorePosts;

    List<Post> fetchedPosts = [];
    Set<String> fetchedLikedIds = {}; // Use current likes as default

    try {
      // --- Fetching ---
      // Determine if likes need fetching
      bool shouldFetchLikes = forceRefresh || (_likedPostIds.isEmpty && _authService.userId != null);

      // Create futures
      List<Future> futures = [];
      futures.add(_fetchPosts(limit: _fetchLimit, offset: 0)); // Always fetch posts
      if (shouldFetchLikes) {
        futures.add(_fetchUserLikes()); // Add likes fetch if needed
      }

      // Await results
      final results = await Future.wait(futures);

      // Process results
      fetchedPosts = results[0] as List<Post>;
      if (shouldFetchLikes) {
        // Likes were fetched (second future)
        fetchedLikedIds = results[1] as Set<String>;
      } else if (!forceRefresh) {
         // If not forcing refresh and not fetching likes, keep existing likes
         fetchedLikedIds = Set.from(_likedPostIds);
      }
      // If forcing refresh but not fetching likes (e.g., logged out user), fetchedLikedIds remains empty {}

      // --- State Update (only on success) ---
      log('Successfully fetched initial data. Updating state.');
      _loadedPosts.clear(); // Clear existing posts *after* successful fetch
      _loadedPosts.addAll(fetchedPosts);
      _currentOffset = fetchedPosts.length;
      _hasMorePosts = fetchedPosts.length == _fetchLimit;
      _likedPostIds = fetchedLikedIds; // Update with fetched or existing likes

      // --- Fetch Profiles for the fetched posts --- 
      // This now happens within _fetchPosts, so no separate call needed here.
      // -------------------------------------------

    } catch (e) {
      log('Error during initial fetch/likes fetch in Provider: $e');
      _hasMorePosts = false; // Assume no more posts on error

      // If the refresh failed, restore the previous state
      if (forceRefresh) {
        log('Refresh failed, restoring previous state.');
        _loadedPosts.clear();
        _loadedPosts.addAll(oldPosts);
        _currentOffset = oldOffset;
        _hasMorePosts = oldHasMore;
        _likedPostIds = oldLikedPostIds;
      }
      // If initial load (not refresh) failed, _loadedPosts remains empty, which is correct.

    } finally {
      _isLoading = false;
      // Notify listeners AFTER all potential state updates are done
      notifyListeners();
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
      // --- Fetch Profiles for the new posts --- 
      // This now happens within _fetchPosts, so no separate call needed here.
      // ------------------------------------------
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
      // 1. Fetch basic post data
      final response = await _supabase
          .from('posts')
          .select(
            'post_id, user_id, text_content, created_at, media_content, reported, like_count, comment_count',
          )
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final List<Map<String, dynamic>> postData = List<Map<String, dynamic>>.from(response ?? []);
      if (postData.isEmpty) {
        return []; // No posts fetched
      }

      log('Fetched basic posts (Provider): offset=$offset, limit=$limit, count=${postData.length}');

      // 2. Extract unique user IDs needing profile lookup
      final Set<String> userIdsToFetch = postData
          .map((item) => item['user_id'] as String)
          // Only fetch if not already cached
          .where((userId) => !_displayNameCache.containsKey(userId))
          .toSet();

      // 3. Fetch profiles if needed
      if (userIdsToFetch.isNotEmpty) {
        log('Fetching profiles for ${userIdsToFetch.length} users.');
        try {
           final profilesResponse = await _supabase
            .from('profiles')
            .select('user_id, display_name')
            .inFilter('user_id', userIdsToFetch.toList());
          
           final List<dynamic> profilesData = profilesResponse as List<dynamic>? ?? [];
           // Update cache
           for (var profile in profilesData) {
             final userId = profile['user_id'] as String;
             final displayName = profile['display_name'] as String?;
             _displayNameCache[userId] = displayName; // Store fetched name (or null)
           }
           // Ensure IDs that weren't found are also cached (as null)
           for (var userId in userIdsToFetch) {
              _displayNameCache.putIfAbsent(userId, () => null);
           }
        } catch (profileError) {
            log('Error fetching profiles for posts: $profileError');
            // Cache missing profiles as null to avoid refetching constantly
            for (var userId in userIdsToFetch) {
               _displayNameCache.putIfAbsent(userId, () => null);
            }
        }
      }

      // 4. Create Post objects using cached display names
      final List<Post> posts = [];
      for (var item in postData) {
        try {
          final userId = item['user_id'] as String;
          final fetchedDisplayName = _displayNameCache[userId]; // Get from cache (might be null)
          posts.add(Post.fromJson(item, fetchedDisplayName: fetchedDisplayName));
        } catch (e) {
          log('Error parsing post item (Provider): $item, error: $e');
          // Skip invalid items
        }
      }
      log('Parsed posts with display names (Provider): ${posts.length}');
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
             likeCount: _loadedPosts[index].likeCount,
             commentCount: _loadedPosts[index].commentCount,
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

  // --- New Like/Unlike Methods ---

  // Toggles the like status for a post
  Future<bool> toggleLikePost(String postId) async {
    final userId = _authService.userId;
    if (userId == null) {
      log('Error: User not logged in, cannot like post.');
      return false; // Can't like if not logged in
    }

    final index = _loadedPosts.indexWhere((p) => p.id == postId);
    if (index == -1) {
      log('Error: Post $postId not found locally for liking.');
      return false; // Post not found locally
    }

    final post = _loadedPosts[index];

    // Check if the user has already liked this post by querying the 'likes' table
    try {
      final likeResponse = await _supabase
          .from('likes')
          .select('like_id') // Select minimal data
          .eq('post_id', postId)
          .eq('user_id', userId)
          .maybeSingle(); // Use maybeSingle to handle 0 or 1 result

      final bool isCurrentlyLiked = likeResponse != null;

      if (isCurrentlyLiked) {
        // --- Unlike --- 
        log('User $userId is unliking post $postId');
        _likedPostIds.remove(postId); // Update local set optimistically
        _loadedPosts[index] = Post(
          id: post.id,
          userId: post.userId,
          textContent: post.textContent,
          createdAt: post.createdAt,
          imageList: post.imageList,
          reported: post.reported,
          likeCount: (post.likeCount > 0) ? post.likeCount - 1 : 0, // Decrement
          commentCount: post.commentCount,
        );
        notifyListeners(); // Notify UI of change

        // Perform Supabase delete
        try {
          await _supabase
              .from('likes')
              .delete()
              .match({'post_id': postId, 'user_id': userId});

          // Optional: Decrement like_count in posts table (if no triggers)
          // await _supabase.rpc('decrement_like_count', params: {'pid': postId});

          log('Successfully unliked post $postId for user $userId');
          return true; // Indicate success
        } catch (e) {
          log('Error unliking post $postId in Supabase: $e');
          // Revert optimistic update on failure
          _likedPostIds.add(postId); // Add back to set
          _loadedPosts[index] = post; // Put the original post back
          notifyListeners();
          return false;
        }
      } else {
        // --- Like ---
        log('User $userId is liking post $postId');
        _likedPostIds.add(postId); // Update local set optimistically
        _loadedPosts[index] = Post(
          id: post.id,
          userId: post.userId,
          textContent: post.textContent,
          createdAt: post.createdAt,
          imageList: post.imageList,
          reported: post.reported,
          likeCount: post.likeCount + 1, // Increment
          commentCount: post.commentCount,
        );
        notifyListeners(); // Notify UI of change

        // Perform Supabase insert
        try {
          await _supabase.from('likes').insert({
            'post_id': postId,
            'user_id': userId,
          });

          // Optional: Increment like_count in posts table (if no triggers)
          // await _supabase.rpc('increment_like_count', params: {'pid': postId});

          log('Successfully liked post $postId for user $userId');
          // --- Send Notification ---
          final likerDisplayName = _displayNameCache[userId] ?? 'Someone';
          await _sendLikeNotification(post.userId, userId, likerDisplayName, postId);
          // -------------------------
          return true; // Indicate success
        } catch (e) {
          log('Error liking post $postId in Supabase: $e');
          // Revert optimistic update on failure
          _likedPostIds.remove(postId); // Remove from set
          _loadedPosts[index] = post; // Put the original post back
          notifyListeners();
          return false;
        }
      }
    } catch (e) {
      log('Error checking like status for post $postId: $e');
      return false; // Failed to determine like status
    }
  }

  // --- Method to update comment count locally (Increment) ---
  void incrementCommentCount(String postId) {
    final index = _loadedPosts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = _loadedPosts[index];
      _loadedPosts[index] = Post(
        id: post.id,
        userId: post.userId,
        textContent: post.textContent,
        createdAt: post.createdAt,
        imageList: post.imageList,
        reported: post.reported,
        likeCount: post.likeCount, 
        commentCount: post.commentCount + 1, // Increment count
      );
      log('Incremented local comment count for post $postId');
      notifyListeners(); // Notify feed screen UI
    }
  }

  // --- Method to update comment count locally (Decrement) ---
  void decrementCommentCount(String postId) {
    final index = _loadedPosts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = _loadedPosts[index];
      // Ensure count doesn't go below zero visually
      final newCount = (post.commentCount > 0) ? post.commentCount - 1 : 0;
      _loadedPosts[index] = Post(
        id: post.id,
        userId: post.userId,
        textContent: post.textContent,
        createdAt: post.createdAt,
        imageList: post.imageList,
        reported: post.reported,
        likeCount: post.likeCount, 
        commentCount: newCount, // Decrement count
      );
      log('Decremented local comment count for post $postId');
      notifyListeners(); // Notify feed screen UI
    }
  }

  // --- Method to update comment count based on value from CommentsScreen ---
  void updateLocalCommentCount(String postId, int newCount) {
    log('[FeedProvider] Updating local comment count for post $postId to $newCount');
    final index = _loadedPosts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = _loadedPosts[index];
      // Update only if the count has actually changed
      if (post.commentCount != newCount) {
        _loadedPosts[index] = Post( // Create a new Post object with the updated count
          id: post.id,
          userId: post.userId,
          textContent: post.textContent,
          createdAt: post.createdAt,
          imageList: post.imageList,
          reported: post.reported,
          likeCount: post.likeCount,
          commentCount: newCount, // Use the count passed from CommentsScreen
        );
        log('[FeedProvider] Updated local comment count for post $postId to $newCount via updateLocalCommentCount');
        notifyListeners(); // Notify UI to rebuild
      } else {
         log('[FeedProvider] Local comment count for post $postId is already $newCount.');
      }
    } else {
       log('[FeedProvider] Post $postId not found locally to update comment count via updateLocalCommentCount.');
    }
  }

  // --- Placeholder for Sending Like Notification ---
  Future<void> _sendLikeNotification(String postAuthorId, String likerUserId, String likerDisplayName, String postId) async {
    // Prevent self-notification
    if (postAuthorId == likerUserId) {
       log('[Notification] User $likerUserId liked their own post $postId. No notification sent.');
       return;
    }

    log('[Notification] Attempting to send like notification via backend: User $likerUserId liked post $postId by user $postAuthorId');

    // Access the backend URL from environment variables
    final String? backendBaseUrl = dotenv.env['BACKEND_URL'];
    if (backendBaseUrl == null) {
      log('[Notification] Error: BACKEND_URL not found in .env file.');
      return; // Stop if backend URL is not configured
    }

    // --- Define Backend Endpoint ---
    // IMPORTANT: Replace with your actual backend endpoint for like notifications
    final String likeNotificationUrl = '$backendBaseUrl/api/send-like-notification';
    // -------------------------------

    try {
       // Prepare the notification payload
       // TODO: Consider fetching the liker's display name/username if needed for the notification body
       final String title = '$likerDisplayName liked your post!'; // Use display name
       final String body = '$likerDisplayName liked your post.'; // Example body

      final response = await http.post(
        Uri.parse(likeNotificationUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(<String, dynamic>{
          'recipientUserId': postAuthorId, // The user ID of the person whose post was liked
          'likerUserId': likerUserId,    // The user ID of the person who liked the post
          'postId': postId,              // The ID of the liked post
          'notificationTitle': title,    // Optional: Title for the notification
          'notificationBody': body,      // Optional: Body/message for the notification
          // Add any other relevant data your backend needs
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        log('[Notification] Like notification sent successfully via backend.');
      } else {
        log(
          '[Notification] Failed to send like notification via backend. Status: ${response.statusCode}, Body: ${response.body}',
        );
        // Optional: Add more robust error handling or user feedback if needed
      }
    } catch (e, stacktrace) {
      log('[Notification] Error calling like notification backend endpoint: $e\n$stacktrace');
      // Optional: Add more robust error handling
    }
  }
  // --- End Like/Unlike Methods ---
}
