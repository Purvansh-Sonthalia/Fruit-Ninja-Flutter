import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer'; // For logging
import 'dart:convert'; // Required for base64Decode, jsonDecode
import 'dart:typed_data'; // Required for Uint8List
import 'dart:ui' as ui; // Import for ui.Image
import 'dart:async'; // Import for Completer
import 'create_post_screen.dart'; // Import the new screen
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'package:intl/intl.dart';

// Define a model for the Post data for better type safety
class Post {
  final String id;
  final String userId;
  final String textContent;
  final DateTime createdAt;
  // Store the list of image data maps
  final List<Map<String, dynamic>>? imageList;

  Post({
    required this.id,
    required this.userId,
    required this.textContent,
    required this.createdAt,
    this.imageList,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    // Ensure required fields are present and have correct types
    if (json['post_id'] == null ||
        json['user_id'] == null ||
        json['created_at'] == null) {
      log('Error: Missing required field in post JSON: $json');
      throw FormatException('Invalid post data received: $json');
    }

    List<Map<String, dynamic>>? parsedImageList;
    final dynamic mediaContent =
        json['media_content']; // Use dynamic type for check

    if (mediaContent != null) {
      if (mediaContent is String && mediaContent.isNotEmpty) {
        // New format: JSON string representing a list
        try {
          final decodedList = jsonDecode(mediaContent) as List<dynamic>;
          parsedImageList =
              decodedList.map((item) {
                if (item is Map<String, dynamic>) {
                  return item;
                } else {
                  log(
                    'Warning: Invalid item type in media_content list for post ${json['post_id']}: $item',
                  );
                  return <String, dynamic>{}; // Handle error: empty map
                }
              }).toList();
        } catch (e) {
          log(
            'Error decoding media_content JSON string for post ${json['post_id']}: $e',
          );
          parsedImageList = null; // Handle JSON decoding error
        }
      } else if (mediaContent is Map<String, dynamic>) {
        // Old format: Single JSON object
        // Check if the map is not empty and contains expected keys (optional but good practice)
        if (mediaContent.containsKey('image_base64') ||
            mediaContent.containsKey('image_mime_type')) {
          parsedImageList = [mediaContent]; // Wrap the single map in a list
        } else {
          log(
            'Warning: media_content map is empty or missing expected keys for post ${json['post_id']}',
          );
          parsedImageList = null;
        }
      } else {
        // Unexpected type for media_content
        log(
          'Warning: Unexpected type for media_content for post ${json['post_id']}: ${mediaContent.runtimeType}',
        );
        parsedImageList = null;
      }
    }

    return Post(
      id: json['post_id'] as String,
      userId: json['user_id'] as String,
      textContent:
          json['text_content'] as String? ?? '', // Handle null text better
      createdAt: DateTime.parse(json['created_at'] as String),
      imageList: parsedImageList, // Assign the parsed list
    );
  }

  // Helper to decode Base64 image data from the list by index
  Uint8List? getDecodedImageBytes(int index) {
    if (imageList != null && index >= 0 && index < imageList!.length) {
      final imageData = imageList![index];
      final base64String = imageData['image_base64'] as String?;
      if (base64String != null && base64String.isNotEmpty) {
        try {
          return base64Decode(base64String);
        } catch (e) {
          log('Error decoding base64 image at index $index for post $id: $e');
          return null;
        }
      }
    }
    return null;
  }
}

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
          log(
            'Error decoding image $i for aspect ratio calculation (post ${widget.postId}): $e',
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
          log(
            'Error decoding base64 image at index $index for post ${widget.postId}: $e',
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
          builder:
              (_) => Dialog(
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
                        errorBuilder:
                            (ctx, err, st) => const Icon(
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
          log(
            'Error displaying single image for post ${widget.postId}: $error',
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
          height: 150,
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
        pageViewContent = const AspectRatio(
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
                    // Use the single image builder for zoom etc.
                    return _buildSingleImage(imageBytes);
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
              // Page Indicator
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
  }
}
// --- End Image Viewer Widget ---

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  // State for infinite scrolling
  final List<Post> _loadedPosts = [];
  final _supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false; // Tracks initial load
  bool _isLoadingMore = false; // Tracks loading more posts
  bool _hasMorePosts = true; // Assume there are more posts initially
  int _currentOffset = 0;
  static const int _fetchLimit = 10; // Number of posts to fetch each time

  @override
  void initState() {
    super.initState();
    // Add listener to scroll controller
    _scrollController.addListener(_onScroll);
    // Fetch initial posts
    _fetchInitialPosts();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // Listener for scroll events
  void _onScroll() {
    // Check if nearing the end and not already loading more
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.9 &&
        !_isLoadingMore &&
        _hasMorePosts &&
        !_isLoading // Don't trigger if initial load is still happening
        ) {
      log('Loading more posts...'); // Log message when loading more posts
      _loadMorePosts();
    }
  }

  // Fetch the very first batch of posts
  Future<void> _fetchInitialPosts() async {
    if (_isLoading) return; // Already loading initially

    setState(() {
      _isLoading = true;
      _loadedPosts.clear(); // Clear previous posts on initial fetch/refresh
      _currentOffset = 0; // Reset offset
      _hasMorePosts = true; // Reset flag
    });

    try {
      final newPosts = await _fetchPosts(limit: _fetchLimit, offset: 0);
      if (!mounted) return; // Check if widget is still mounted

      setState(() {
        _loadedPosts.addAll(newPosts);
        _currentOffset = newPosts.length;
        _hasMorePosts = newPosts.length == _fetchLimit; // Check if we got a full batch
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false); // Stop loading indicator on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching initial posts: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      log('Error during initial fetch: $e');
    }
  }

  // Load subsequent batches of posts
  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMorePosts || _isLoading) return; // Exit if already loading, no more posts, or initial load in progress

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final newPosts = await _fetchPosts(limit: _fetchLimit, offset: _currentOffset);
      if (!mounted) return; // Check if widget is still mounted

      setState(() {
        _loadedPosts.addAll(newPosts);
        _currentOffset += newPosts.length;
        _hasMorePosts = newPosts.length == _fetchLimit; // Update based on this fetch
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false); // Stop loading indicator on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading more posts: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      log('Error loading more posts: $e');
    }
  }

  // Modified fetch function to accept limit and offset
  Future<List<Post>> _fetchPosts({required int limit, required int offset}) async {
    try {
      final response = await _supabase
          .from('posts')
          .select(
            'post_id, user_id, text_content, created_at, media_content',
          )
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1); // Use range for pagination

      // Supabase client returns List<Map<String, dynamic>> directly
      final List<Map<String, dynamic>> data = response;

      log('Fetched posts: offset=$offset, limit=$limit, count=${data.length}');

      final List<Post> posts = [];
      for (var item in data) {
        try {
          posts.add(Post.fromJson(item));
        } catch (e) {
          log('Error parsing post item: $item, error: $e');
          // Skip invalid items
        }
      }

      log('Parsed posts: ${posts.length}');
      return posts;
    } catch (e, stacktrace) {
      log('Error fetching posts (offset=$offset, limit=$limit): $e\n$stacktrace');
      // Re-throw the error to be caught by the calling function
      // This allows the UI to show specific error messages for initial/load more
      rethrow;
    }
  }

  // Helper function to refresh the feed
  Future<void> _handleRefresh() async {
    // Trigger the initial fetch process again
    await _fetchInitialPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Allow body to extend behind the AppBar
      extendBodyBehindAppBar: true,
      // Restore AppBar but make it transparent
      appBar: AppBar(
        title: const Text(
          'Community Feed',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        // Make AppBar transparent
        backgroundColor: Colors.transparent,
        // Remove shadow
        elevation: 0,
        // Keep default back button (leading)
      ),
      body: Container(
        // Ensure the gradient covers the whole screen
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFF4682B4)],
          ),
        ),
        // Use RefreshIndicator for pull-to-refresh
        child: RefreshIndicator(
          onRefresh: _handleRefresh, // Use the refresh handler
          child: _buildFeedContent(), // Delegate content building
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreatePostScreen()),
          );
          // Refresh the feed if a post was created
          if (result == true && mounted) {
            await _handleRefresh(); // Await the refresh
          }
        },
        child: const Icon(Icons.add_comment_outlined), // Keep only the icon
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
        shape: const CircleBorder(), // Make it circular
      ),
    );
  }

  // Helper widget to build the main feed content based on state
  Widget _buildFeedContent() {
    // Show loading indicator during initial fetch
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Show message if no posts after initial load
    if (_loadedPosts.isEmpty) {
      return ListView( // Wrap in ListView to enable pull-to-refresh even when empty
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

    // Build the list view with posts and potentially a loading indicator
    return ListView.builder(
      controller: _scrollController, // Attach the scroll controller
      padding: const EdgeInsets.only(top: kToolbarHeight + 8, bottom: 8, left: 8, right: 8), // Adjust top padding for transparent AppBar
      // Add 1 to item count if we might load more or show end message
      itemCount: _loadedPosts.length + (_hasMorePosts || !_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Check if it's the last item index
        final isLastItem = index == _loadedPosts.length;

        if (isLastItem) {
          // If it's the last item, show loading or end message
          if (_hasMorePosts) {
            // Show loading indicator if loading more
            return _isLoadingMore
                ? const Center(
                    child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: CircularProgressIndicator(color: Colors.white70),
                  ))
                : const SizedBox.shrink(); // Or nothing if not currently loading
          } else {
            // Show "End of Feed" message if no more posts
            return const Padding(
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
            );
          }
        }

        // Otherwise, build the post card for the current index
        final post = _loadedPosts[index];
        final bool hasImages =
            post.imageList != null && post.imageList!.isNotEmpty;

        // Get the current user ID
        final authService = Provider.of<AuthService>(context, listen: false);
        final currentUserId = authService.userId;
        final bool isSelfPost = currentUserId != null && post.userId == currentUserId;

        final DateFormat dateFormat = DateFormat('HH:mm - dd/MM/yyyy');

        return Card(
          margin: const EdgeInsets.symmetric(
            vertical: 6,
            horizontal: 4,
          ),
          elevation: 0,
          // Conditional card color
          color: isSelfPost
              ? Colors.yellow.withOpacity(0.3) // Yellow tint for self posts
              : Colors.green.shade900.withOpacity(0.4), // Dark green tint for others
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Add Author Label ---
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
                child: Text(
                  isSelfPost ? 'YOU' : 'ANONYMOUS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // Add a small spacer only if label is present
              const SizedBox(height: 4),
              // --- Use the new PostImageViewer widget ---
              if (hasImages)
                PostImageViewer(
                  imageList: post.imageList!,
                  postId: post.id,
                ),

              // --- Post Content (Text & Timestamp) ---
              Padding(
                padding: const EdgeInsets.all(
                  16.0,
                ), // Add padding around text
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.textContent,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dateFormat.format(post.createdAt.toLocal()),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
