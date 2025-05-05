import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'dart:developer';
import 'dart:io'; // Required for File
import 'dart:convert'; // Required for base64Encode, jsonEncode
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'package:http/http.dart' as http; // Import http package
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import dotenv
import 'package:google_generative_ai/google_generative_ai.dart'; // Import Gemini SDK
import 'package:flutter/foundation.dart'; // For kDebugMode and Uint8List
import 'dart:async'; // For Timer (debouncing)

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
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker(); // Image picker instance
  bool _isEnhanceButtonEnabled = false; // State for AI button
  bool _isEnhancing = false; // State for AI loading

  // --- State for Mentions ---
  bool _isShowingMentionsList = false;
  String _mentionQuery = '';
  bool _mentionSearchLoading = false;
  List<Map<String, dynamic>> _mentionResults = [];
  final List<String> _taggedUserIds = []; // Store IDs of tagged users
  Timer? _debounce;
  // --- End State for Mentions ---

  @override
  void initState() {
    super.initState();
    // Listen to text changes to update button state
    _postTextController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel(); // Cancel debounce timer
    _postTextController.removeListener(_onTextChanged); // Remove listener
    _postTextController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _updateEnhanceButtonState(); // Keep this for the AI button state

    // --- Mention Detection Logic ---
    final text = _postTextController.text;
    final cursorPos = _postTextController.selection.baseOffset;

    // Check if cursor is valid and text is not empty
    if (cursorPos < 0 || text.isEmpty) {
      _hideMentionsList();
      return;
    }

    // Find the start of the potential mention query (last '@' before cursor)
    final textBeforeCursor = text.substring(0, cursorPos);
    final lastAtSymbolIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtSymbolIndex != -1) {
      // Ensure '@' is not preceded by a non-whitespace character (avoid email-like patterns)
      bool isStartOfWord = lastAtSymbolIndex == 0 ||
          textBeforeCursor[lastAtSymbolIndex - 1].trim().isEmpty;

      if (isStartOfWord) {
        final query = textBeforeCursor.substring(lastAtSymbolIndex + 1);
        // Check if the query contains spaces or is too long - stop mentioning if so
        if (!query.contains(RegExp(r'\s')) && query.length <= 20) {
          if (query != _mentionQuery || !_isShowingMentionsList) {
            setState(() {
              _isShowingMentionsList = true;
              _mentionQuery = query;
              _mentionSearchLoading = true; // Show loading immediately
              _mentionResults = []; // Clear previous results
            });
            // Debounce the search
            if (_debounce?.isActive ?? false) _debounce!.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () {
              if (_mentionQuery == query && _isShowingMentionsList) {
                // Check if query is still the same
                _searchUsers(_mentionQuery);
              }
            });
          }
          return; // Found valid mention query, exit
        }
      }
    }

    // If no valid mention pattern is found at the cursor
    _hideMentionsList();
    // --- End Mention Detection Logic ---
  }

  void _hideMentionsList() {
    if (_isShowingMentionsList) {
      setState(() {
        _isShowingMentionsList = false;
        _mentionQuery = '';
        _mentionResults = [];
        _mentionSearchLoading = false;
      });
    }
    _debounce?.cancel(); // Cancel any pending search
  }

  // --- Update AI Button State ---
  void _updateEnhanceButtonState() {
    final bool canEnhance = _postTextController.text.trim().isNotEmpty ||
        _selectedImages.isNotEmpty;
    if (_isEnhanceButtonEnabled != canEnhance) {
      setState(() {
        _isEnhanceButtonEnabled = canEnhance;
      });
    }
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
        _updateEnhanceButtonState(); // Update button state
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
        _updateEnhanceButtonState(); // Update button state
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
      _updateEnhanceButtonState(); // Update button state
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  // --- Send Reminder Notification (KEEP this for general new post reminders) ---
  Future<void> _sendReminderNotification(
    String textContent,
    bool hasImages,
  ) async {
    // Access the backend URL from environment variables
    final String? backendBaseUrl = dotenv.env['BACKEND_URL'];

    if (backendBaseUrl == null) {
      log('Error: BACKEND_URL not found in .env file.');
      return;
    }

    final String reminderUrl = '$backendBaseUrl/api/send-reminder';
    String title = 'New Post Created!';
    String body;
    if (textContent.isNotEmpty) {
      body = textContent.length > 100
          ? '${textContent.substring(0, 97)}...'
          : textContent;
      if (hasImages) {
        body += ' (+ images)';
      }
    } else if (hasImages) {
      body = 'A new post with images was added.';
    } else {
      log('Attempted to send reminder for an empty post.');
      return;
    }
    try {
      final response = await http.post(
        Uri.parse(reminderUrl),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(<String, String>{'title': title, 'body': body}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        log('Reminder notification sent successfully.');
      } else {
        log('Failed to send reminder notification. Status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      log('Error sending reminder notification: $e');
    }
  }
  // --- End Send Reminder Notification ---

  // --- Send Tag Notifications ---
  Future<void> _sendTagNotifications(
      String newPostId, String posterUserId, List<String> taggedIds) async {
    if (taggedIds.isEmpty) return; // No one to notify

    log('[Notification] Preparing to send tag notifications for post $newPostId by $posterUserId to users: $taggedIds');

    // 1. Fetch Poster's Display Name (cache it if possible, but simple fetch for now)
    String posterDisplayName = 'Someone'; // Default
    try {
      final profileResponse = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('user_id', posterUserId)
          .maybeSingle(); // Use maybeSingle in case profile doesn't exist
      if (profileResponse != null && profileResponse['display_name'] != null) {
        posterDisplayName = profileResponse['display_name'] as String;
      }
      log('[Notification] Fetched poster display name: $posterDisplayName');
    } catch (e) {
      log('[Notification] Error fetching poster display name: $e');
      // Proceed with default name
    }

    // 2. Get Backend URL
    final String? backendBaseUrl = dotenv.env['BACKEND_URL'];
    if (backendBaseUrl == null) {
      log('[Notification] Error: BACKEND_URL not found in .env file. Cannot send tag notifications.');
      return;
    }
    // Use the SAME endpoint as comments/likes for simplicity
    final String notificationUrl = '$backendBaseUrl/api/send-like-notification';

    // 3. Loop and Send Notification for each tagged user
    for (final taggedUserId in taggedIds) {
      // Avoid self-tag notification (shouldn't happen with current search logic, but good practice)
      if (taggedUserId == posterUserId) continue;

      log('[Notification] Sending tag notification to user: $taggedUserId');
      try {
        final String title = '$posterDisplayName tagged you in a post';
        final String body = 'Tap to view the post.'; // Simple body

        final response = await http.post(
          Uri.parse(notificationUrl),
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode(<String, dynamic>{
            'recipientUserId': taggedUserId, // The person being tagged
            'likerUserId': posterUserId, // The person who tagged (poster)
            'postId': newPostId, // The ID of the new post
            'notificationType':
                'tag', // *** IMPORTANT: Use 'tag' or 'mention' ***
            'commenterDisplayName': posterDisplayName, // Send poster's name
            // Comment specific fields are null/omitted
            'commentId': null,
            'commentText': null,
            'hasImage': null,
            'notificationTitle': title, // Dynamic title
            'notificationBody': body, // Dynamic body
          }),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          log('[Notification] Tag notification sent successfully to $taggedUserId.');
        } else {
          log('[Notification] Failed to send tag notification to $taggedUserId. Status: ${response.statusCode}, Body: ${response.body}');
        }
      } catch (e) {
        log('[Notification] Error sending tag notification to $taggedUserId: $e');
      }
      // Optional: Add a small delay between notifications if needed
      // await Future.delayed(const Duration(milliseconds: 100));
    }
    log('[Notification] Finished sending tag notifications.');
  }
  // --- End Send Tag Notifications ---

  // --- Placeholder for AI Enhancement ---
  Future<void> _enhanceWithAI() async {
    if (_isEnhancing) return; // Prevent concurrent calls

    setState(() {
      _isEnhancing = true;
    });

    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      log('Error: GEMINI_API_KEY not found in .env file.');
      if (mounted) {
        _showErrorSnackBar('AI Enhancement is not configured.');
      }
      setState(() {
        _isEnhancing = false;
      });
      return;
    }

    // Use the gemini-1.5-flash model
    final model =
        GenerativeModel(model: 'gemini-1.5-flash-latest', apiKey: apiKey);
    final textContent = _postTextController.text.trim();
    final bool hasText = textContent.isNotEmpty;
    final bool hasImages = _selectedImages.isNotEmpty;

    List<DataPart> imageParts = [];
    if (hasImages) {
      try {
        for (final imageFile in _selectedImages) {
          final bytes = await File(imageFile.path).readAsBytes();
          // Attempt to infer MIME type, default to jpeg if unknown
          final mimeType = imageFile.mimeType ?? 'image/jpeg';
          imageParts.add(DataPart(mimeType, bytes));
          log('Prepared image ${imageFile.name} ($mimeType) for AI.');
        }
      } catch (e) {
        log('Error reading image file for AI: $e');
        if (mounted) {
          _showErrorSnackBar('Error processing images for AI.');
        }
        setState(() {
          _isEnhancing = false;
        });
        return;
      }
    }

    String prompt;
    List<Content> content = [];

    if (hasText && hasImages) {
      prompt =
          'Rewrite the following text for a social media post, making it more engaging and considering the context from the attached image(s). Provide only the single, final enhanced text, including relevant hashtags. Original text: "$textContent"';
      content = [
        Content.multi([TextPart(prompt), ...imageParts])
      ];
    } else if (hasText) {
      prompt =
          'Rewrite the following text for a social media post, making it more engaging, clear, or creative. Include relevant hashtags if appropriate. Provide only the single, final enhanced text. Original text: "$textContent"';
      content = [Content.text(prompt)];
    } else if (hasImages) {
      prompt =
          'Write *one* creative and engaging caption for the attached image(s) for a social media post. Include relevant hashtags. Provide only the single caption text.';
      content = [
        Content.multi([TextPart(prompt), ...imageParts])
      ];
    } else {
      // Should not happen due to button enablement logic, but handle defensively
      log('Enhance AI called with no text or images.');
      setState(() {
        _isEnhancing = false;
      });
      return;
    }

    try {
      log('Sending request to Gemini...');
      final response = await model.generateContent(content);

      if (response.text != null) {
        log('Gemini response received: ${response.text}');
        setState(() {
          // Update the text field with the enhanced content
          _postTextController.text = response.text!;
          // Ensure the cursor is at the end
          _postTextController.selection = TextSelection.fromPosition(
            TextPosition(offset: _postTextController.text.length),
          );
        });
        if (mounted) {
          _showSuccessSnackBar('Content enhanced by AI!');
        }
      } else {
        log('Gemini response was empty.');
        if (mounted) {
          _showErrorSnackBar('AI enhancement failed: No response received.');
        }
      }
    } catch (e) {
      log('Error calling Gemini API: $e');
      // Check for specific API errors if needed
      // e.g., if (e is GenerativeAIException) { ... }
      if (mounted) {
        _showErrorSnackBar('AI enhancement failed: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEnhancing = false;
        });
      }
    }
  }
  // --- End Placeholder ---

  // --- User Search for Mentions ---
  Future<void> _searchUsers(String query) async {
    // If query is empty, fetch initial users. Otherwise, filter.
    // No need to check for empty query here anymore, logic below handles it.

    setState(() {
      // We always set loading to true when a search is initiated
      _mentionSearchLoading = true;
    });

    log(query.isEmpty
        ? 'Fetching initial users for mention...'
        : 'Searching for users matching: $query');

    final currentUserId = _supabase.auth.currentUser?.id;

    try {
      // Start building the query
      var request = _supabase
          .from('profiles')
          .select('user_id, display_name') // Select needed columns
          .neq('user_id', currentUserId ?? ''); // Exclude self

      // Add filtering only if the query is NOT empty
      if (query.isNotEmpty) {
        request = request.ilike(
            'display_name', '$query%'); // Case-insensitive starts-with
      }

      // Apply limit and execute
      final response = await request.limit(10); // Limit results

      if (mounted) {
        setState(() {
          _mentionResults = List<Map<String, dynamic>>.from(response);
          _mentionSearchLoading = false;
          log(query.isEmpty
              ? 'Fetched ${_mentionResults.length} initial users.'
              : 'Found ${_mentionResults.length} users matching query.');
        });
      }
    } on PostgrestException catch (e) {
      log('Supabase error searching users: ${e.message}');
      if (mounted) {
        setState(() {
          _mentionSearchLoading = false;
          _mentionResults = [];
        });
      }
    } catch (e) {
      log('Error searching users: $e');
      if (mounted) {
        setState(() {
          _mentionSearchLoading = false;
          _mentionResults = [];
        });
      }
    }
  }
  // --- End User Search ---

  // --- Handle Mention Selection ---
  void _onUserMentionSelected(Map<String, dynamic> user) {
    final userId = user['user_id'] as String; // Use user_id
    final displayName = user['display_name'] as String; // Use display_name
    log('Selected user: $displayName (ID: $userId)');

    final currentText = _postTextController.text;
    final currentSelection = _postTextController.selection;

    final textBeforeCursor =
        currentText.substring(0, currentSelection.baseOffset);
    final lastAtSymbolIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtSymbolIndex != -1) {
      final startIndex = lastAtSymbolIndex;
      final endIndex = currentSelection.baseOffset;

      final mentionText = '@$displayName '; // Use display_name here
      final newText =
          currentText.replaceRange(startIndex, endIndex, mentionText);
      final newCursorPos = startIndex + mentionText.length;

      setState(() {
        if (!_taggedUserIds.contains(userId)) {
          _taggedUserIds.add(userId);
        }
        _postTextController.text = newText;
        _postTextController.selection = TextSelection.fromPosition(
          TextPosition(offset: newCursorPos),
        );
        _hideMentionsList();
      });
      log('Tagged users: $_taggedUserIds');
    } else {
      log('Error: Could not find @ symbol to replace mention.');
      _hideMentionsList();
    }
  }
  // --- End Mention Selection ---

  Future<void> _submitPost() async {
    final textContent = _postTextController.text.trim();
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.userId;

    if (userId == null) {
      _showErrorSnackBar('You must be logged in to post.');
      return;
    }

    if (textContent.isEmpty && _selectedImages.isEmpty) {
      _showErrorSnackBar('Please enter text or select at least one image.');
      return;
    }

    // Capture tagged IDs before clearing potentially
    final List<String> currentTaggedIds = List.from(_taggedUserIds);

    setState(() {
      _isLoading = true;
    });

    List<Map<String, String>> mediaDataList = [];

    try {
      // --- Image Processing (existing logic) ---
      if (_selectedImages.isNotEmpty) {
        for (var imageFile in _selectedImages) {
          try {
            final imageBytes = await File(imageFile.path).readAsBytes();
            final base64Image = base64Encode(imageBytes);
            final mimeType = imageFile.mimeType ?? 'image/jpeg';
            mediaDataList.add({
              'image_base64': base64Image,
              'image_mime_type': mimeType,
            });
            log('Image converted to Base64 (length: ${base64Image.length})');
          } catch (e) {
            log('Error converting image ${imageFile.name} to Base64: $e');
            _showErrorSnackBar('Error processing image: ${imageFile.name}');
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }
      }
      // --- End Image Processing ---

      final postData = {
        'user_id': userId,
        'text_content': textContent,
        'media_content':
            mediaDataList.isEmpty ? null : jsonEncode(mediaDataList),
        'tagged_user_ids':
            currentTaggedIds.isNotEmpty ? currentTaggedIds : null,
      };
      log('Submitting post data: $postData');

      // Insert and select the new post data to get the ID
      final response =
          await _supabase.from('posts').insert(postData).select().single();

      final newPostId = response['post_id'] as String?;
      log('Post created successfully with ID: $newPostId');

      if (mounted) {
        _showSuccessSnackBar('Post created successfully!');

        // Send general reminder (existing)
        _sendReminderNotification(textContent, _selectedImages.isNotEmpty);

        // Send notifications to tagged users (new)
        if (newPostId != null) {
          _sendTagNotifications(newPostId, userId, currentTaggedIds);
        } else {
          log('Error: Could not get new post ID, cannot send tag notifications.');
        }

        Navigator.pop(context, true); // Indicate success
      }
    } on PostgrestException catch (e) {
      log('Supabase error adding post: ${e.message} (Code: ${e.code})');
      _showErrorSnackBar('Failed to create post: ${e.message}');
    } catch (e, stacktrace) {
      log('Error adding post: $e\n$stacktrace');
      _showErrorSnackBar('An unexpected error occurred: ${e.toString()}');
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
                          autofocus: _selectedImages
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
                            hintText:
                                "What's on your mind? Use @ to mention users...",
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none, // Remove underline
                          ),
                        ),
                      ),

                      // --- Mentions List ---
                      if (_isShowingMentionsList)
                        _buildMentionsList(), // Extracted widget for clarity
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // --- Action Buttons Row ---
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly, // Distribute space
                children: [
                  // --- Enhance with AI Button ---
                  Tooltip(
                    message: 'Enhance with AI',
                    child: IconButton(
                      icon: _isEnhancing // Show loader when enhancing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(
                              Icons.auto_awesome, // Sparkle icon
                              color: _isEnhanceButtonEnabled
                                  ? Colors.white.withOpacity(0.9)
                                  : Colors.grey
                                      .withOpacity(0.6), // Dim if disabled
                            ),
                      // Disable if already enhancing OR if button is generally disabled
                      onPressed: _isEnhancing || !_isEnhanceButtonEnabled
                          ? null
                          : _enhanceWithAI,
                    ),
                  ),

                  // --- Add Image Button ---
                  TextButton.icon(
                    onPressed:
                        _showImageSourceActionSheet, // Still shows the modal sheet
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    label: Text(
                      _selectedImages.isEmpty
                          ? 'Add Images'
                          : 'Add More Images',
                      style: TextStyle(color: Colors.white.withOpacity(0.9)),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ],
              ),
              // --- End Action Buttons Row ---
              const SizedBox(height: 10),
              // --- Post Button ---
              ElevatedButton(
                onPressed:
                    _isLoading || // Also disable if neither text nor image present initially
                            (!_isEnhanceButtonEnabled && // If enhance is disabled
                                _postTextController.text.trim().isEmpty &&
                                _selectedImages.isEmpty)
                        ? null
                        : _submitPost,
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
                  // Dim the button slightly if disabled
                  disabledBackgroundColor: Colors.orangeAccent.withOpacity(0.5),
                  disabledForegroundColor: Colors.white70,
                ),
                child: _isLoading
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

  // --- Helper Widget for Mentions List ---
  Widget _buildMentionsList() {
    // Determine content based on loading state and results
    Widget listContent;
    if (_mentionSearchLoading) {
      listContent = const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
        ),
      );
    } else if (_mentionResults.isEmpty) {
      listContent = const Padding(
        padding: EdgeInsets.all(12.0),
        child: Text('No users found.', style: TextStyle(color: Colors.white70)),
      );
    } else {
      // Build the list of users
      listContent = ListView.builder(
        padding: EdgeInsets.zero, // Remove ListView default padding
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: _mentionResults.length,
        itemBuilder: (context, index) {
          final user = _mentionResults[index];
          final displayName = user['display_name'] ?? 'N/A'; // Use display_name
          return Material(
            // Need Material for InkWell splash effect
            color: Colors.transparent, // Inherit background
            child: InkWell(
              onTap: () => _onUserMentionSelected(user),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12.0, vertical: 12.0),
                child: Text(
                  displayName, // Display the display_name
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        },
      );
    }

    // Return the list container with background and border
    return Container(
      constraints: const BoxConstraints(
        maxHeight: 150, // Limit height to prevent excessive expansion
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3), // Semi-transparent background
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: listContent,
    );
  }
  // --- End Helper Widget ---
}
