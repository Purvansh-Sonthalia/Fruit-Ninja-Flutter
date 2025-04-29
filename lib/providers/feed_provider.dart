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
// --- Add DatabaseHelper import ---
import '../services/database_helper.dart';

class FeedProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  // --- Add AuthService instance ---
  final AuthService _authService =
      AuthService(); // Assuming default constructor or singleton
  // --- Add DatabaseHelper instance ---
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  final List<Post> _loadedPosts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  int _currentOffset = 0; // Tracks network offset
  static const int _fetchLimit = 10;
  bool _isOffline = false; // Track connectivity status
  String _errorMessage = ''; // Store error messages

  // --- State for liked posts ---
  Set<String> _likedPostIds = {};
  final bool _isLoadingLikes = false;

  // Map to cache fetched display names <userId, displayName>
  final Map<String, String?> _displayNameCache = {};

  // --- Getters for UI ---
  List<Post> get posts =>
      List.unmodifiable(_loadedPosts); // Return unmodifiable list
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMorePosts => _hasMorePosts;
  // Getter for liked post IDs
  Set<String> get likedPostIds => _likedPostIds;
  bool get isOffline => _isOffline; // Getter for offline status
  String get errorMessage => _errorMessage; // Getter for error message

  // --- Data Fetching Logic ---

  // Helper to fetch IDs of posts liked by the current user from Supabase
  Future<Set<String>> _fetchUserLikesFromNetwork() async {
    final userId = _authService.userId;
    if (userId == null) {
      log('[FeedProvider] Cannot fetch likes from network: User not logged in.');
      return {};
    }
    log('[FeedProvider] Fetching user likes from network for user: $userId');
    try {
      final response =
          await _supabase.from('likes').select('post_id').eq('user_id', userId);

      final List<dynamic> data = response ?? [];
      final fetchedIds = data.map((item) => item['post_id'] as String).toSet();
      log('[FeedProvider] Fetched ${fetchedIds.length} liked post IDs from network.');
      return fetchedIds;
    } catch (e) {
      log('[FeedProvider] Error fetching user likes from network: $e');
      // Don't throw, return empty set and let caller handle potential network issues
      return {};
    }
  }

  // Updated fetchInitialPosts to include caching
  Future<void> fetchInitialPosts({bool forceRefresh = false}) async {
    // 1. Check loading state
    if (_isLoading) return; // Prevent concurrent initial loads

    _isLoading = true;
    _isOffline = false; // Assume online initially
    _errorMessage = '';

    // 2. Handle Refresh Scenario
    if (forceRefresh) {
      _loadedPosts.clear();
      _currentOffset = 0;
      _hasMorePosts = true; // Assume more posts until network check fails
      log('[FeedProvider] Force refresh initiated, clearing local posts.');
    } else {
      // 3. Load from Cache (if not forcing refresh)
      // Try loading from cache first ONLY if not forcing a refresh and list is empty
      if (_loadedPosts.isEmpty) {
        await _loadPostsFromCache(isInitialLoad: true);
      }
    }

    // 4. Notify UI about loading state change (and potential cache load)
    notifyListeners();

    // 5. Network Fetch Attempt
    List<Post> fetchedNetworkPosts = [];
    Set<String> fetchedNetworkLikedIds = {};
    bool networkFetchSuccess = false;

    try {
      log('[FeedProvider] Attempting network fetch for initial posts...');
      // Determine if likes need fetching from network
      bool shouldFetchLikes = forceRefresh ||
          (_likedPostIds.isEmpty && _authService.userId != null);

      List<Future> futures = [];
      // Use _fetchPostsFromNetwork
      futures.add(_fetchPostsFromNetwork(limit: _fetchLimit, offset: 0));
      if (shouldFetchLikes) {
        // Use _fetchUserLikesFromNetwork
        futures.add(_fetchUserLikesFromNetwork());
      }

      final results = await Future.wait(futures);

      // Process results
      fetchedNetworkPosts = results[0] as List<Post>;
      if (shouldFetchLikes) {
        fetchedNetworkLikedIds = results[1] as Set<String>;
      } else {
        // Keep existing likes if not forcing refresh and not fetching likes
        fetchedNetworkLikedIds = Set.from(_likedPostIds);
      }

      networkFetchSuccess = true;
      log('[FeedProvider] Successfully fetched initial data from network (${fetchedNetworkPosts.length} posts).');

      // --- Update State & Cache (only on network success) ---
      _loadedPosts.clear(); // Clear existing posts (cache or old data)
      _loadedPosts.addAll(fetchedNetworkPosts);
      _currentOffset = fetchedNetworkPosts.length; // Reset network offset
      _hasMorePosts = fetchedNetworkPosts.length == _fetchLimit;
      _likedPostIds = fetchedNetworkLikedIds; // Update likes from network

      // Cache the newly fetched posts
      await _dbHelper.batchUpsertPosts(fetchedNetworkPosts);
      log('[FeedProvider] Cached ${fetchedNetworkPosts.length} initial posts.');
    } catch (e) {
      log('[FeedProvider] Error during initial network fetch: $e');
      _errorMessage =
          'Failed to fetch latest posts. Displaying cached data if available.'; // Set error message
      _isOffline = true; // Indicate potential offline state
      _hasMorePosts = false; // Can't assume more posts if network failed

      // If forcing refresh and network fails, try loading cache as fallback
      // Also handles the case where initial non-refresh cache load failed but network also failed
      if (_loadedPosts.isEmpty) {
        log('[FeedProvider] Network fetch failed, attempting to load from cache as fallback...');
        await _loadPostsFromCache(isInitialLoad: true);
        if (_loadedPosts.isEmpty) {
          _errorMessage = 'Failed to fetch posts and no cached data available.';
          log('[FeedProvider] Fallback cache load failed or cache was empty.');
        } else {
          log('[FeedProvider] Successfully loaded fallback data from cache.');
        }
      } else {
        log('[FeedProvider] Network fetch failed, but cached data is already displayed.');
      }
      // If not forcing refresh, the cache data loaded earlier (if any) remains visible.
    } finally {
      _isLoading = false;
      // Notify listeners AFTER all potential state updates (network or cache fallback)
      notifyListeners();
    }
  }

  // Helper to load posts from cache
  Future<void> _loadPostsFromCache({required bool isInitialLoad}) async {
    try {
      log('[FeedProvider] Loading posts from cache (isInitialLoad: $isInitialLoad)...');
      // Fetch initial page from cache only on initial load or refresh fallback
      final cachedPosts =
          await _dbHelper.getCachedPosts(limit: _fetchLimit, offset: 0);
      if (cachedPosts.isNotEmpty) {
        if (isInitialLoad) {
          _loadedPosts.clear();
          _loadedPosts.addAll(cachedPosts);
          log('[FeedProvider] Loaded ${cachedPosts.length} posts from cache for initial display.');
          // We don't update offset/hasMore based on cache, let network handle it
        }
        // Don't load more than the first page from cache automatically here
      } else {
        log('[FeedProvider] No posts found in cache.');
      }
    } catch (e) {
      log('[FeedProvider] Error loading posts from cache: $e');
      // Handle cache read error if needed
    }
  }

  // Updated loadMorePosts to handle offline state
  Future<void> loadMorePosts() async {
    // Only attempt network fetch if not already loading, not offline, and potentially has more posts
    if (_isLoadingMore || _isLoading || _isOffline || !_hasMorePosts) {
      // Log why we are not fetching more
      String reason = _isLoadingMore
          ? "already loading more"
          : _isLoading
              ? "initial load in progress"
              : _isOffline
                  ? "offline"
                  : !_hasMorePosts
                      ? "no more posts expected"
                      : "unknown";
      // Avoid excessive logging for "no more posts" as it's expected
      if (reason != "no more posts expected") {
        log('[FeedProvider] Skipping loadMorePosts: $reason');
      }
      return;
    }

    _isLoadingMore = true;
    notifyListeners();

    List<Post> newNetworkPosts = [];
    bool networkFetchSuccess = false;

    try {
      log('[FeedProvider] Attempting network fetch for more posts (offset: $_currentOffset)...');
      // Use _fetchPostsFromNetwork with the current network offset
      newNetworkPosts = await _fetchPostsFromNetwork(
          limit: _fetchLimit, offset: _currentOffset);
      networkFetchSuccess = true;

      // --- Update State & Cache (only on network success) ---
      if (newNetworkPosts.isNotEmpty) {
        _loadedPosts.addAll(newNetworkPosts);
        _currentOffset += newNetworkPosts.length; // Update network offset
        _hasMorePosts = newNetworkPosts.length == _fetchLimit;

        // Cache the newly fetched posts
        await _dbHelper.batchUpsertPosts(newNetworkPosts);
        log('[FeedProvider] Successfully fetched and cached ${newNetworkPosts.length} more posts.');
      } else {
        log('[FeedProvider] Network fetch returned no new posts. Setting hasMorePosts to false.');
        _hasMorePosts = false; // No more posts found on the network
      }
    } catch (e) {
      log('[FeedProvider] Error loading more posts from network: $e');
      _errorMessage = 'Failed to load more posts.';
      _isOffline = true; // Indicate potential offline state
      _hasMorePosts = false; // Stop trying to load more if network failed
      // No need to update _loadedPosts here, keep what was already loaded
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // Renamed: Fetches posts ONLY from the network (Supabase)
  Future<List<Post>> _fetchPostsFromNetwork(
      {required int limit, required int offset}) async {
    log('[FeedProvider] Fetching posts from NETWORK: offset=$offset, limit=$limit');
    // This method now only contains the network fetching logic (Supabase + Profiles)
    // The error handling specific to network failures is managed by the callers (fetchInitialPosts, loadMorePosts)
    try {
      // 1. Fetch basic post data from Supabase
      final response = await _supabase
          .from('posts')
          .select(
            'post_id, user_id, text_content, created_at, media_content, reported, like_count, comment_count',
          )
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      // Check for PostgrestException more explicitly if needed
      if (response == null) {
        // Handle null response if Supabase client can return null on error
        log('[FeedProvider] Network fetch returned null response.');
        throw Exception('Network error fetching posts: Received null response');
      }

      final List<Map<String, dynamic>> postData =
          List<Map<String, dynamic>>.from(response); // No ?? [] here

      if (postData.isEmpty) {
        log('[FeedProvider] No more posts found on network. Offset: $offset');
        return []; // No posts fetched
      }

      log('[FeedProvider] Fetched ${postData.length} raw posts from network.');

      // 2. Extract unique user IDs needing profile lookup (same logic as before)
      final Set<String> userIdsToFetch = postData
          .map((item) => item['user_id'] as String)
          .where((userId) => !_displayNameCache.containsKey(userId))
          .toSet();

      // 3. Fetch profiles from network if needed (same logic as before)
      if (userIdsToFetch.isNotEmpty) {
        log('[FeedProvider] Fetching profiles from network for ${userIdsToFetch.length} users.');
        try {
          final profilesResponse = await _supabase
              .from('profiles')
              .select('user_id, display_name')
              .inFilter('user_id', userIdsToFetch.toList());

          final List<dynamic> profilesData =
              profilesResponse as List<dynamic>? ?? [];
          for (var profile in profilesData) {
            final userId = profile['user_id'] as String;
            final displayName = profile['display_name'] as String?;
            _displayNameCache[userId] =
                displayName; // Store fetched name (or null)
          }
          // Ensure IDs that weren't found are also cached (as null)
          for (var userId in userIdsToFetch) {
            _displayNameCache.putIfAbsent(userId, () => null);
          }
        } catch (profileError) {
          log('[FeedProvider] Error fetching profiles for posts: $profileError');
          // Cache missing profiles as null to avoid refetching constantly
          for (var userId in userIdsToFetch) {
            _displayNameCache.putIfAbsent(userId, () => null);
          }
        }
      }

      // 4. Create Post objects using cached display names (same logic as before)
      final List<Post> posts = [];
      for (var item in postData) {
        try {
          final userId = item['user_id'] as String;
          final fetchedDisplayName = _displayNameCache[userId];
          posts
              .add(Post.fromJson(item, fetchedDisplayName: fetchedDisplayName));
        } catch (e) {
          log('[FeedProvider] Error parsing post item from network data: $item, error: $e');
        }
      }
      log('[FeedProvider] Parsed ${posts.length} posts from network data.');
      return posts;
    } on PostgrestException catch (e, stacktrace) {
      // Catch specific Supabase errors
      log('[FeedProvider] PostgrestException fetching posts from network: ${e.message}\n$stacktrace');
      throw Exception(
          'Network error fetching posts: ${e.message}'); // Rethrow standard Exception
    } catch (e, stacktrace) {
      // Catch other potential errors (parsing, etc.)
      log('[FeedProvider] Generic error fetching posts from network: $e\n$stacktrace');
      rethrow; // Re-throw to be caught by calling methods
    }
  }

  // --- Post Actions (Update to include cache deletion) ---

  // ReportPost remains mostly the same, only network interaction needed
  Future<bool> reportPost(String postId) async {
    log('[FeedProvider] Reporting post with ID: $postId');
    // No change needed for caching here, just reporting status
    try {
      await _supabase
          .from('posts')
          .update({'reported': true}).eq('post_id', postId);
      log('[FeedProvider] Successfully marked post $postId as reported (Provider).');

      // Optimistically update local state
      final index = _loadedPosts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        _loadedPosts[index] = Post(
          // Create new instance
          id: _loadedPosts[index].id,
          userId: _loadedPosts[index].userId,
          textContent: _loadedPosts[index].textContent,
          createdAt: _loadedPosts[index].createdAt,
          imageList: _loadedPosts[index].imageList,
          reported: true,
          likeCount: _loadedPosts[index].likeCount,
          commentCount: _loadedPosts[index].commentCount,
        );
        log('[FeedProvider] Updated local post $postId state to reported=true (Provider)');
        notifyListeners(); // Notify UI of the change
      }
      return true; // Success
    } catch (e) {
      log('[FeedProvider] Error reporting post $postId (Provider): $e');
      return false; // Failure
    }
  }

  // Updated deletePost to remove from cache as well
  Future<bool> deletePost(String postId) async {
    log('[FeedProvider] Attempting to delete post ID: $postId');
    bool networkDeleteSuccess = false;
    try {
      // 1. Attempt network delete
      await _supabase.from('posts').delete().eq('post_id', postId);
      log('[FeedProvider] Supabase delete successful for post ID: $postId');
      networkDeleteSuccess = true;

      // 2. Remove from local list (optimistic UI update)
      final initialLength = _loadedPosts.length;
      _loadedPosts.removeWhere((post) => post.id == postId);
      if (_loadedPosts.length < initialLength) {
        log('[FeedProvider] Post removed from local list state.');
        notifyListeners(); // Notify UI immediately
      }

      // 3. Remove from local cache
      await _dbHelper.deletePost(postId);

      return true; // Overall success
    } catch (e) {
      log('[FeedProvider] Error deleting post $postId: $e');
      // If network failed, but was locally removed, maybe keep it removed? Or revert?
      // For now, just return false. UI won't see it removed if notifyListeners wasn't called.
      // Consider if UI should be notified even on failure.
      if (networkDeleteSuccess) {
        log('[FeedProvider] Network delete succeeded, but cache delete failed for $postId');
        // Post is removed from UI, but might reappear if cache loads before network next time.
      }
      return false; // Failure
    }
  }

  // --- Like/Unlike Methods (No direct caching change needed for likes themselves) ---
  // Likes are fetched with initial posts, caching them separately isn't the primary goal here.
  // The logic for toggling like remains network-focused.

  Future<bool> toggleLikePost(String postId) async {
    final userId = _authService.userId;
    if (userId == null) {
      log('[FeedProvider] Error: User not logged in, cannot like post.');
      return false; // Can't like if not logged in
    }

    final index = _loadedPosts.indexWhere((p) => p.id == postId);
    if (index == -1) {
      log('[FeedProvider] Error: Post $postId not found locally for liking.');
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
        log('[FeedProvider] User $userId is unliking post $postId');
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

          log('[FeedProvider] Successfully unliked post $postId for user $userId');
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
          await _sendLikeNotification(
              post.userId, userId, likerDisplayName, postId);
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
        _loadedPosts[index] = Post(
          // Create a new Post object with the updated count
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
  Future<void> _sendLikeNotification(String postAuthorId, String likerUserId,
      String likerDisplayName, String postId) async {
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
    final String likeNotificationUrl =
        '$backendBaseUrl/api/send-like-notification';
    // -------------------------------

    try {
      // Prepare the notification payload
      // TODO: Consider fetching the liker's display name/username if needed for the notification body
      final String title =
          '$likerDisplayName liked your post!'; // Use display name
      final String body = '$likerDisplayName liked your post.'; // Example body

      final response = await http.post(
        Uri.parse(likeNotificationUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(<String, dynamic>{
          'recipientUserId':
              postAuthorId, // The user ID of the person whose post was liked
          'likerUserId':
              likerUserId, // The user ID of the person who liked the post
          'postId': postId, // The ID of the liked post
          'notificationTitle': title, // Optional: Title for the notification
          'notificationBody':
              body, // Optional: Body/message for the notification
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
