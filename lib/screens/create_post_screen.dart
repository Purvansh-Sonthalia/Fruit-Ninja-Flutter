import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'dart:developer';
import 'dart:io'; // Required for File
import 'dart:convert'; // Required for base64Encode, jsonEncode
import 'package:image_picker/image_picker.dart'; // Import image_picker

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _postTextController = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool _isLoading = false; // To show loading indicator on the button
  // Change to a list to hold multiple images
  List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker(); // Image picker instance

  @override
  void dispose() {
    _postTextController.dispose();
    super.dispose();
  }

  // --- Image Picking Logic ---

  // Function to pick multiple images from gallery
  Future<void> _pickMultiImageFromGallery() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1080,
        imageQuality: 85,
      );

      if (pickedFiles.isNotEmpty) {
        setState(() {
          // Append new images, consider adding checks for duplicates if needed
          _selectedImages.addAll(pickedFiles);
        });
        log('${pickedFiles.length} images selected from gallery.');
      } else {
        log('No images selected from gallery.');
      }
    } catch (e) {
      log('Error picking multiple images: $e');
      if (mounted) {
        _showErrorSnackBar('Error picking images: ${e.toString()}');
      }
    }
  }

  // Function to pick a single image from camera
  Future<void> _pickSingleImageFromCamera() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImages.add(pickedFile); // Add the single image
        });
        log('Image selected from camera.');
      } else {
        log('No image selected from camera.');
      }
    } catch (e) {
      log('Error picking image from camera: $e');
      if (mounted) {
        _showErrorSnackBar('Error using camera: ${e.toString()}');
      }
    }
  }

  // Remove an image at a specific index
  void _removeImage(int index) {
    if (index >= 0 && index < _selectedImages.length) {
      setState(() {
        _selectedImages.removeAt(index);
      });
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Photo Library (Select Multiple)'),
                  onTap: () {
                    _pickMultiImageFromGallery(); // Use the multi-image picker
                    Navigator.of(context).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Camera'),
                  onTap: () {
                    _pickSingleImageFromCamera(); // Use the single image camera picker
                    Navigator.of(context).pop();
                  },
                ),
                // Remove the general 'Remove Image' option - removal is per image now
              ],
            ),
          ),
    );
  }
  // --- End Image Picking Logic ---

  // Helper for showing snackbars
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _submitPost() async {
    final textContent = _postTextController.text.trim();
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.userId;

    if (userId == null) {
      _showErrorSnackBar('You must be logged in to post.');
      return;
    }

    // Text content is optional if at least one image is selected
    if (textContent.isEmpty && _selectedImages.isEmpty) {
      // Check if the list is empty
      _showErrorSnackBar('Please enter text or select at least one image.');
      return;
    }

    setState(() {
      _isLoading = true; // Start loading indicator
    });

    List<Map<String, String>> mediaDataList = []; // List to hold image data

    try {
      // 1. Convert all selected images to Base64
      if (_selectedImages.isNotEmpty) {
        for (var imageFile in _selectedImages) {
          try {
            final imageBytes = await File(imageFile.path).readAsBytes();
            final base64Image = base64Encode(imageBytes);
            final mimeType =
                imageFile.mimeType ?? 'image/jpeg'; // Default MIME type

            mediaDataList.add({
              'image_base64': base64Image,
              'image_mime_type': mimeType,
            });
            log('Image converted to Base64 (length: ${base64Image.length})');
          } catch (e) {
            log('Error converting image ${imageFile.name} to Base64: $e');
            // Decide if you want to stop or just skip the failed image
            // Showing error and stopping for now:
            if (mounted) {
              _showErrorSnackBar('Error processing image: ${imageFile.name}');
            }
            setState(() {
              _isLoading = false;
            });
            return; // Stop processing
          }
        }
      }

      // 2. Insert post data (including the list of media content)
      await _supabase.from('posts').insert({
        'user_id': userId,
        'text_content': textContent, // Can be empty if images exist
        'media_content':
            mediaDataList.isEmpty
                ? null
                : jsonEncode(mediaDataList), // Encode the list as JSON
      });

      if (mounted) {
        _showSuccessSnackBar('Post created successfully!');
        Navigator.pop(context, true); // Indicate success
      }
    } on PostgrestException catch (e) {
      log('Supabase error adding post: ${e.message} (Code: ${e.code})');
      if (mounted) {
        _showErrorSnackBar('Failed to create post: ${e.message}');
      }
    } catch (e, stacktrace) {
      log('Error adding post: $e\n$stacktrace');
      if (mounted) {
        _showErrorSnackBar('An unexpected error occurred: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Post'),
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
        leading: IconButton(
          // Add a back button explicitly
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        // Consistent gradient background
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFF4682B4)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25), // Frosted glass
                    borderRadius: BorderRadius.circular(15.0),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 1,
                    ), // Subtle border
                  ),
                  child: Column(
                    // Wrap TextField in Column for Image Preview
                    children: [
                      // --- Image Preview List ---
                      if (_selectedImages.isNotEmpty)
                        SizedBox(
                          height: 100, // Adjust height as needed
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _selectedImages.length,
                            itemBuilder: (context, index) {
                              final imageFile = _selectedImages[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8.0),
                                      child: Image.file(
                                        File(imageFile.path),
                                        width: 100, // Thumbnail width
                                        height: 100, // Thumbnail height
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    // Small remove button
                                    Container(
                                      margin: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: InkWell(
                                        onTap: () => _removeImage(index),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      if (_selectedImages.isNotEmpty)
                        const SizedBox(height: 8), // Spacer
                      // --- Text Field ---
                      Expanded(
                        child: TextField(
                          controller: _postTextController,
                          autofocus:
                              _selectedImages
                                  .isEmpty, // Autofocus only if no images
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.4,
                          ), // White text, adjusted line height
                          maxLines: null, // Allows unlimited lines
                          expands: true, // Makes TextField fill the container
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: "What's on your mind?",
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none, // Remove underline
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // --- Add Image Button ---
              TextButton.icon(
                onPressed:
                    _showImageSourceActionSheet, // Still shows the modal sheet
                icon: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: Colors.white.withOpacity(0.8),
                ),
                label: Text(
                  // Update label based on whether images are selected
                  _selectedImages.isEmpty ? 'Add Images' : 'Add More Images',
                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed:
                    _isLoading
                        ? null
                        : _submitPost, // Disable button when loading
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent, // Match FAB color
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 15,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child:
                    _isLoading
                        ? const SizedBox(
                          // Show loading indicator inside button
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                        : const Text('Post It!'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
