import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'dart:developer'; // For logging
import 'dart:convert'; // Required for base64Decode, jsonDecode
import 'dart:typed_data'; // Required for Uint8List
import 'create_post_screen.dart'; // Import the new screen

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

class _PostImageViewerState extends State<PostImageViewer> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(() {
      if (_pageController.page?.round() != _currentPage) {
        setState(() {
          _currentPage = _pageController.page!.round();
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Helper to decode bytes, same logic as before but instance method now
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

  @override
  Widget build(BuildContext context) {
    final imageCount = widget.imageList.length;
    return AspectRatio(
      aspectRatio: 16 / 9, // Or your desired aspect ratio
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: imageCount,
            itemBuilder: (context, pageIndex) {
              final imageBytes = _getDecodedImageBytes(pageIndex);
              if (imageBytes != null) {
                // Wrap Image.memory with GestureDetector for tap-to-zoom
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
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      log(
                        'Error displaying image $pageIndex for post ${widget.postId}: $error',
                      );
                      return Container(
                        color: Colors.black26,
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white70,
                            size: 50,
                          ),
                        ),
                      );
                    },
                  ),
                );
              } else {
                // Placeholder for decoding errors
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
          // Page Indicator (only show if more than one image)
          if (imageCount > 1)
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
      appBar: AppBar(
        title: const Text('Community Feed'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4682B4), Color(0xFF87CEEB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
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
                padding: const EdgeInsets.all(8.0),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  final post = posts[index];
                  final bool hasImages =
                      post.imageList != null && post.imageList!.isNotEmpty;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    elevation: 0,
                    color: Colors.white.withOpacity(0.25),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                              SizedBox(height: hasImages ? 8 : 0),
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
