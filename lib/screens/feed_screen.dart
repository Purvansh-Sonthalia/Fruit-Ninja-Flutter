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
  late Future<List<Post>> _postsFuture;
  final _supabase = Supabase.instance.client;
  // Remove _newPostController as it's unused here

  @override
  void initState() {
    super.initState();
    _postsFuture = _fetchPosts();
  }

  @override
  void dispose() {
    // No need to dispose _newPostController anymore
    super.dispose();
  }

  Future<List<Post>> _fetchPosts() async {
    try {
      final response = await _supabase
          .from('posts')
          .select(
            'post_id, user_id, text_content, created_at, media_content',
          ) // Explicitly select columns
          .order('created_at', ascending: false)
          .limit(50);

      // No need to cast to List<dynamic> if using .select()
      // Supabase client returns List<Map<String, dynamic>> directly
      final List<Map<String, dynamic>> data = response;

      log('Fetched posts data: ${data.length} items');

      if (data.isEmpty) {
        return [];
      }

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
      log('Error fetching posts: $e\n$stacktrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching posts: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return [];
    }
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
        // The SafeArea might be implicitly handled by Scaffold,
        // but if status bar overlap is an issue, we might need
        // to adjust padding within the body later.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFF4682B4)],
          ),
        ),
        child: FutureBuilder<List<Post>>(
          future: _postsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            if (snapshot.hasError) {
              log('Snapshot error in build: ${snapshot.error}');
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Error loading posts. Pull down to retry.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _postsFuture = _fetchPosts();
                  });
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                    const Center(
                      child: Text(
                        'No posts yet. Be the first!',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            final posts = snapshot.data!;

            return RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _postsFuture = _fetchPosts();
                });
              },
              child: ListView.builder(
                // Add cacheExtent to build items further offscreen
                cacheExtent:
                    MediaQuery.of(context).size.height *
                    1.5, // Cache 1.5 screens worth of items
                padding: const EdgeInsets.all(8.0),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  final post = posts[index];
                  final bool hasImages =
                      post.imageList != null && post.imageList!.isNotEmpty;

                  // Get the current user ID
                  final authService = Provider.of<AuthService>(context, listen: false);
                  final currentUserId = authService.userId;
                  final bool isSelfPost = currentUserId != null && post.userId == currentUserId;

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
                              // Only add top padding if there are images above
                              // Adjust spacing based on whether images are present
                              // SizedBox(height: hasImages ? 8 : 0), // Removed this fixed padding, label handles top space now
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
                                '${post.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${post.createdAt.toLocal().minute.toString().padLeft(2, '0')} - ${post.createdAt.toLocal().day}/${post.createdAt.toLocal().month}/${post.createdAt.toLocal().year}',
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
              ),
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreatePostScreen()),
          );
          if (result == true && mounted) {
            setState(() {
              _postsFuture = _fetchPosts();
            });
          }
        },
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New Post'),
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
      ),
    );
  }
}
