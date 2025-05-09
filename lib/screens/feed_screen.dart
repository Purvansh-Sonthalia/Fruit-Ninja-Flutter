import 'package:flutter/material.dart';
import 'dart:developer'; // Add back dart:developer
import 'dart:convert'; // Required for base64Decode, jsonDecode
import 'dart:typed_data'; // Required for Uint8List
import 'dart:ui' as ui; // Import for ui.Image
import 'dart:async'; // Import for Completer
import 'create_post_screen.dart'; // Import the new screen
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'package:intl/intl.dart';
import '../providers/feed_provider.dart'; // Import FeedProvider
import '../models/post_model.dart'; // Correct import for Post
import 'comments_screen.dart'; // Import the CommentsScreen
import '../providers/comments_provider.dart'; // Import CommentsProvider
import '../utils/text_parsing.dart'; // <-- Import the text parsing utility

// --- New StatefulWidget for Image Viewer ---
class PostImageViewer extends StatefulWidget {
  final List<Map<String, dynamic>> imageList;
  final String postId; // Pass post ID for logging

  const PostImageViewer({
    super.key,
    required this.imageList,
    required this.postId,
  });

  @override
  State<PostImageViewer> createState() => _PostImageViewerState();
}

// Reintroduce PageController for multiple images & Add dynamic aspect ratio logic
class _PostImageViewerState extends State<PostImageViewer> {
  late PageController _pageController;
  int _currentPage = 0;

  // State for dynamic aspect ratio calculation
  bool _isCalculatingSize = false;
  double? _calculatedAspectRatio;
  static const double _defaultAspectRatio = 16 / 9;

  @override
  void initState() {
    super.initState();
    // Initialize PageController only if there are multiple images
    if (widget.imageList.length > 1) {
      _pageController = PageController();
      _pageController.addListener(() {
        final newPage = _pageController.page?.round();
        if (newPage != null && newPage != _currentPage) {
          setState(() {
            _currentPage = newPage;
          });
        }
      });
      // Start aspect ratio calculation for multiple images
      _calculateAndSetMaxAspectRatio();
    }
  }

  Future<void> _calculateAndSetMaxAspectRatio() async {
    if (!mounted) return;
    setState(() {
      _isCalculatingSize = true;
    });

    double minAspectRatio = _defaultAspectRatio; // Start with default
    bool foundValidImage = false;

    for (int i = 0; i < widget.imageList.length; i++) {
      final imageBytes = _getDecodedImageBytes(i);
      if (imageBytes != null) {
        try {
          final completer =
              Completer<ui.Image>(); // Use Completer from dart:async
          ui.decodeImageFromList(imageBytes, completer.complete);
          final ui.Image imageInfo = await completer.future;

          if (imageInfo.height > 0) {
            final aspectRatio = imageInfo.width / imageInfo.height;
            if (!foundValidImage || aspectRatio < minAspectRatio) {
              minAspectRatio = aspectRatio;
              foundValidImage = true;
            }
          }
        } catch (e) {
          // Replace print with log
          log(
            '[PostImageViewer] Error decoding image $i for aspect ratio calculation (post ${widget.postId}): $e',
          );
          // Ignore this image for calculation, continue with others
        }
      }
    }

    if (!mounted) return;
    setState(() {
      // Use calculated only if we successfully processed at least one image
      _calculatedAspectRatio = foundValidImage ? minAspectRatio : null;
      _isCalculatingSize = false;
    });
  }

  @override
  void dispose() {
    // Dispose PageController only if it was initialized
    if (widget.imageList.length > 1) {
      _pageController.dispose();
    }
    super.dispose();
  }

  // Helper to decode bytes, remains the same
  Uint8List? _getDecodedImageBytes(int index) {
    if (index >= 0 && index < widget.imageList.length) {
      final imageData = widget.imageList[index];
      final base64String = imageData['image_base64'] as String?;
      if (base64String != null && base64String.isNotEmpty) {
        try {
          return base64Decode(base64String);
        } catch (e) {
          // Replace print with log
          log(
            '[PostImageViewer] Error decoding base64 image at index $index for post ${widget.postId}: $e',
          );
          return null;
        }
      }
    }
    return null;
  }

  // --- Helper Function for Single Image Display (with zoom) ---
  Widget _buildSingleImage(Uint8List imageBytes) {
    return GestureDetector(
      onTap: () {
        // Show the zoomed image in a Dialog
        showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(10),
            child: GestureDetector(
              // Tap again to close the dialog
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.memory(
                    imageBytes, // Use the same image bytes
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, st) => const Icon(
                      Icons.broken_image,
                      size: 100,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Image.memory(
        imageBytes,
        fit: BoxFit.contain, // Use contain to maintain aspect ratio
        gaplessPlayback: true, // Smoother loading
        errorBuilder: (context, error, stackTrace) {
          // Replace print with log
          log(
            '[PostImageViewer] Error displaying single image for post ${widget.postId}: $error',
          );
          // Display a placeholder on error
          return Container(
            // Give error placeholder a reasonable height
            height: 150,
            color: Colors.black26,
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.white70, size: 50),
            ),
          );
        },
      ),
    );
  }
  // --- End Single Image Helper ---

  @override
  Widget build(BuildContext context) {
    final imageCount = widget.imageList.length;

    // --- Restore previous logic ---
    // Handle cases: 0, 1, or multiple images
    if (imageCount == 0) {
      return const SizedBox.shrink();
    } else if (imageCount == 1) {
      // Display single image directly (no aspect ratio calculation needed)
      final imageBytes = _getDecodedImageBytes(0);
      if (imageBytes != null) {
        return _buildSingleImage(imageBytes);
      } else {
        // Error placeholder for the single image
        return Container(
          height: 150, // Keep defined height for placeholder
          color: Colors.black26,
          child: const Center(
            child: Icon(Icons.error_outline, color: Colors.white70, size: 50),
          ),
        );
      }
    } else {
      // Multiple images: Use PageView with calculated or default AspectRatio
      Widget pageViewContent;
      if (_isCalculatingSize) {
        // Show placeholder while calculating
        pageViewContent = AspectRatio(
          aspectRatio: _defaultAspectRatio,
          child: Center(
            child: CircularProgressIndicator(color: Colors.white70),
          ),
        );
      } else {
        // Use calculated aspect ratio if available, otherwise default
        pageViewContent = AspectRatio(
          aspectRatio: _calculatedAspectRatio ?? _defaultAspectRatio,
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: imageCount,
                itemBuilder: (context, pageIndex) {
                  final imageBytes = _getDecodedImageBytes(pageIndex);
                  if (imageBytes != null) {
                    return _buildSingleImage(
                        imageBytes); // Reuse zoomable single image builder
                  } else {
                    // Placeholder for decoding errors within PageView
                    return Container(
                      color: Colors.black26,
                      child: const Center(
                        child: Icon(
                          Icons.error_outline,
                          color: Colors.white70,
                          size: 50,
                        ),
                      ),
                    );
                  }
                },
              ),
              // Page Indicator (remains the same)
              Positioned(
                bottom: 8.0,
                right: 8.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Text(
                    '${_currentPage + 1} / $imageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return pageViewContent; // Return either placeholder or the sized PageView
    }
    // --- End of restored logic ---
  }
}
// --- End Image Viewer Widget ---

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  // --- Remove State Variables ---
  // final List<Post> _loadedPosts = [];
  // final _supabase = Supabase.instance.client;
  // bool _isLoading = false;
  // bool _isLoadingMore = false;
  // bool _hasMorePosts = true;
  // int _currentOffset = 0;
  // static const int _fetchLimit = 10;

  // --- Keep ScrollController ---
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Fetch initial posts when the screen loads for the first time
    // Use addPostFrameCallback to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Access provider without listening here, just triggering the fetch
      final feedProvider = Provider.of<FeedProvider>(context, listen: false);
      feedProvider.fetchInitialPosts();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // Listener for scroll events - Calls provider method
  void _onScroll() {
    final feedProvider = Provider.of<FeedProvider>(context, listen: false);
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.9 &&
        !feedProvider.isLoadingMore &&
        feedProvider.hasMorePosts &&
        !feedProvider.isLoading) {
      // Replace print with log
      log('[FeedScreen] Requesting loadMorePosts from provider...');
      feedProvider.loadMorePosts();
    }
  }

  // --- Remove Data Fetching Logic (_fetchInitialPosts, _loadMorePosts, _fetchPosts) ---
  // These are now handled by FeedProvider

  // Helper function to refresh the feed - Calls provider method
  Future<void> _handleRefresh() async {
    await Provider.of<FeedProvider>(context, listen: false)
        .fetchInitialPosts(forceRefresh: true);
  }

  // Helper function to navigate to comments screen
  void _navigateToComments(BuildContext context, Post post) {
    log('[FeedScreen] Comment button pressed for post ${post.id}');
    try {
      log('[FeedScreen] Attempting to access providers for comment navigation...');
      // CommentsProvider might not be strictly needed here unless passing initial data
      // final commentsProvider = Provider.of<CommentsProvider>(context, listen: false);
      final feedProvider = Provider.of<FeedProvider>(context, listen: false);
      log('[FeedScreen] Providers accessed successfully.');

      log('[FeedScreen] Navigating to CommentsScreen for post ${post.id}');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CommentsScreen(postId: post.id),
        ),
      ).then((result) {
        log('[FeedScreen] Returned from CommentsScreen for post ${post.id}. Result: $result');
        if (result is int) {
          final newCount = result;
          log('[FeedScreen] Received valid count: $newCount. Updating FeedProvider.');
          feedProvider.updateLocalCommentCount(post.id, newCount);
        } else {
          log('[FeedScreen] Did not receive a valid count. Result: $result');
        }
      });
    } catch (e, stacktrace) {
      log('[FeedScreen] ********** ERROR in _navigateToComments ********** ');
      log(e.toString());
      log(stacktrace.toString());
      log('[FeedScreen] *******************************************************');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Consumer or context.watch to get data from FeedProvider
    final feedProvider = context.watch<FeedProvider>();
    final loadedPosts = feedProvider.posts;
    final isLoading = feedProvider.isLoading;
    final isLoadingMore = feedProvider.isLoadingMore;
    final hasMorePosts = feedProvider.hasMorePosts;
    final likedPostIds = context.watch<FeedProvider>().likedPostIds;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Community Feed',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFF4682B4)],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: _buildFeedContent(
              loadedPosts, isLoading, isLoadingMore, hasMorePosts), // Pass data
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreatePostScreen()),
          );
          if (result == true && mounted) {
            // Await the refresh triggered via provider
            await _handleRefresh();
          }
        },
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }

  // Helper widget to build the main feed content based on state from provider
  Widget _buildFeedContent(List<Post> loadedPosts, bool isLoading,
      bool isLoadingMore, bool hasMorePosts) {
    // Get liked post IDs from provider (listen: true to rebuild on change)
    final likedPostIds = context.watch<FeedProvider>().likedPostIds;

    // Show loading indicator during initial fetch
    if (isLoading && loadedPosts.isEmpty) {
      // Check if loading AND list is empty
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Show message if no posts after initial load
    if (loadedPosts.isEmpty && !isLoading) {
      // Check list empty AND not loading
      return ListView(
        // Wrap in ListView to enable pull-to-refresh even when empty
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
          const Center(
            child: Text(
              'No posts yet. Be the first!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    }

    // Build the list view
    return ListView.builder(
      controller: _scrollController,
      // Add physics and cacheExtent for stability
      physics: const ClampingScrollPhysics(),
      cacheExtent: 800.0, // Apply cache extent
      padding: const EdgeInsets.only(
          top: kToolbarHeight + 8, bottom: 8, left: 8, right: 8),
      itemCount: loadedPosts.length +
          (hasMorePosts || isLoadingMore
              ? 1
              : 0), // Adjust count based on provider state
      itemBuilder: (context, index) {
        final isLastItem = index == loadedPosts.length;

        if (isLastItem) {
          if (hasMorePosts) {
            return isLoadingMore
                ? const Center(
                    child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: CircularProgressIndicator(color: Colors.white70),
                  ))
                : const SizedBox.shrink();
          } else {
            // Only show end of feed if not loading initially
            return !isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Center(
                      child: Text(
                        '~ End of Feed ~',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink();
          }
        }

        final post = loadedPosts[index];
        final bool hasImages =
            post.imageList != null && post.imageList!.isNotEmpty;
        final authService = Provider.of<AuthService>(context, listen: false);
        final currentUserId = authService.userId;
        final bool isSelfPost =
            currentUserId != null && post.userId == currentUserId;
        final DateFormat dateFormat = DateFormat('HH:mm - dd/MM/yyyy');
        // Access FeedProvider for actions (listen: false for actions)
        final feedProvider = Provider.of<FeedProvider>(context, listen: false);
        // Check if the current user liked this post
        final bool isLikedByCurrentUser = likedPostIds.contains(post.id);

        // Use the new StatefulWidget for the list item
        return _FeedPostListItem(
          key: ValueKey(post.id),
          post: post,
          isSelfPost: isSelfPost,
          isLikedByCurrentUser: isLikedByCurrentUser,
          // Pass callbacks down
          onToggleLike: (postId) => feedProvider.toggleLikePost(postId),
          onShowOptions: _showPostOptions,
          onNavigateToComments: _navigateToComments,
        );
      },
    );
  }

  // --- Update action handlers to use provider and show SnackBars ---

  void _showPostOptions(BuildContext context, Post post, bool isSelfPost) {
    final feedProvider = Provider.of<FeedProvider>(context,
        listen: false); // Get provider instance

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).canvasColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20.0),
              topRight: Radius.circular(20.0),
            ),
          ),
          child: Wrap(
            children: <Widget>[
              if (isSelfPost)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete Post',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context); // Close bottom sheet
                    _confirmAndDeletePost(
                        context, feedProvider, post.id); // Call new helper
                  },
                ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report Post'),
                onTap: () async {
                  // Make async
                  Navigator.pop(context); // Close bottom sheet
                  _handleReportPost(
                      context, feedProvider, post.id); // Call new helper
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper for delete confirmation and action
  void _confirmAndDeletePost(
      BuildContext buildContext, FeedProvider feedProvider, String postId) {
    showDialog(
      context: buildContext, // Use the context passed to the options sheet
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          icon: const Icon(Icons.warning_amber_rounded,
              color: Colors.red, size: 40),
          title: const Text('Delete Post', textAlign: TextAlign.center),
          content: const Text(
            'Are you sure you want to delete this post? This action cannot be undone.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                // Make async
                Navigator.of(dialogContext).pop(); // Close the dialog
                // Call provider delete method
                final success = await feedProvider.deletePost(postId);
                // Show SnackBar based on result - check if context is still valid
                if (mounted) {
                  ScaffoldMessenger.of(buildContext).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'Post deleted successfully.'
                          : 'Error deleting post.'),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  // Helper for reporting post and showing Snackbar
  Future<void> _handleReportPost(BuildContext buildContext,
      FeedProvider feedProvider, String postId) async {
    if (mounted) {
      ScaffoldMessenger.of(buildContext).showSnackBar(
        const SnackBar(
          content: Text('Submitting report...'),
          backgroundColor: Colors.blueAccent,
          duration: Duration(seconds: 1),
        ),
      );
    }
    final success = await feedProvider.reportPost(postId);
    // Show SnackBar based on result - check if context is still valid
    if (mounted) {
      ScaffoldMessenger.of(buildContext).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Post reported successfully. Thank you.'
              : 'Error submitting report.'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  // --- Remove _reportPost and _deletePost methods ---
  // Logic is now in FeedProvider, UI handles SnackBars via helpers
} // End of _FeedScreenState

// --- New StatefulWidget for Feed Post List Item ---
class _FeedPostListItem extends StatefulWidget {
  final Post post;
  final bool isSelfPost;
  final bool isLikedByCurrentUser;
  final Function(String) onToggleLike;
  final Function(BuildContext, Post, bool) onShowOptions;
  final Function(BuildContext, Post) onNavigateToComments;

  const _FeedPostListItem({
    super.key,
    required this.post,
    required this.isSelfPost,
    required this.isLikedByCurrentUser,
    required this.onToggleLike,
    required this.onShowOptions,
    required this.onNavigateToComments,
  });

  @override
  State<_FeedPostListItem> createState() => _FeedPostListItemState();
}

class _FeedPostListItemState extends State<_FeedPostListItem> {
  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final bool hasImages = post.imageList != null && post.imageList!.isNotEmpty;
    final DateFormat dateFormat = DateFormat('HH:mm - dd/MM/yyyy');

    // Define styles for RichText
    final defaultTextStyle = TextStyle(
        color: Colors.white.withOpacity(0.9), fontSize: 15, height: 1.4);
    final mentionTextStyle = TextStyle(
        color: Colors.lightBlue.shade200,
        fontWeight: FontWeight.bold,
        fontSize: 15,
        height: 1.4);

    return Card(
      key: ValueKey(post.id),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      elevation: 0,
      color: post.reported
          ? Colors.deepOrange.withOpacity(0.4)
          : widget.isSelfPost
              ? Colors.yellow.withOpacity(0.3)
              : Colors.green.shade900.withOpacity(0.4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isSelfPost ? 'YOU' : (post.displayName ?? 'ANONYMOUS'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 0.5,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onPressed: () {
                    widget.onShowOptions(context, post, widget.isSelfPost);
                  },
                  tooltip: 'Post options', // Add tooltip
                ),
              ],
            ),
          ),
          // Conditional SizedBox based on hasImages
          SizedBox(height: hasImages ? 0 : 4),
          if (hasImages)
            PostImageViewer(
              imageList: post.imageList!,
              postId: post.id, // Pass postId for logging
            ),
          // --- Display Post Text using RichText ---
          if (post.textContent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                  top: 8.0, bottom: 4.0, left: 16.0, right: 16.0),
              child: RichText(
                text: TextSpan(
                  // Use the helper function to build spans
                  children: buildTextSpansWithMentions(
                    post.textContent,
                    defaultTextStyle,
                    mentionTextStyle,
                  ),
                ),
              ),
            ),
          // --- End Display Post Text ---
          Padding(
            padding: const EdgeInsets.only(
                left: 16.0, right: 16.0, bottom: 8.0, top: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  // Like Button
                  children: [
                    IconButton(
                      icon: Icon(
                        widget.isLikedByCurrentUser
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: widget.isLikedByCurrentUser
                            ? Colors.redAccent
                            : Colors.white70,
                      ),
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(), // Remove extra padding
                      tooltip: widget.isLikedByCurrentUser ? 'Unlike' : 'Like',
                      onPressed: () => widget.onToggleLike(post.id),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.likeCount}', // Display like count
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Comment Button
                    IconButton(
                      icon: const Icon(Icons.mode_comment_outlined),
                      color: Colors.white70,
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(), // Remove extra padding
                      tooltip: 'Comment',
                      onPressed: () =>
                          widget.onNavigateToComments(context, post),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount}', // Display comment count
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                // Date Text
                Text(
                  dateFormat.format(post.createdAt.toLocal()),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// --- End Feed Post List Item Widget ---
