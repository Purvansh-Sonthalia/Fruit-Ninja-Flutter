import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import 'dart:typed_data'; // For Uint8List
import 'dart:io'; // For File
import '../providers/comments_provider.dart';
import '../services/auth_service.dart'; // To check current user
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'dart:async'; // For Timer (debouncing)
import 'package:supabase_flutter/supabase_flutter.dart'; // Import supabase_flutter
import '../utils/text_parsing.dart'; // <-- Import the text parsing utility
import 'package:google_generative_ai/google_generative_ai.dart'; // Import Gemini SDK
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import dotenv

class CommentsScreen extends StatefulWidget {
  final String postId;

  const CommentsScreen({super.key, required this.postId});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // --- State for selected image ---
  Uint8List? _selectedImageBytes;
  final ImagePicker _picker = ImagePicker();
  // --------------------------------

  // --- State for Mentions ---
  bool _isShowingMentionsList = false;
  String _mentionQuery = '';
  bool _mentionSearchLoading = false;
  List<Map<String, dynamic>> _mentionResults = [];
  final List<String> _taggedUserIds = []; // Store IDs of tagged users
  Timer? _debounce;
  final _supabase = Supabase.instance.client; // Add supabase client instance
  // --- End State for Mentions ---

  // --- State for AI Enhancement ---
  bool _isEnhanceButtonEnabled = false;
  bool _isEnhancing = false;
  // --- End State for AI Enhancement ---

  @override
  void initState() {
    super.initState();
    log('[CommentsScreen] initState START');
    // Add listener to force rebuild on text change for button state
    _commentController.addListener(_onTextChanged);
    // Initialize button state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateEnhanceButtonState(); // Call initially
      // Fetch comments when the screen loads
      // Use addPostFrameCallback to ensure provider is available
      log('[CommentsScreen] addPostFrameCallback executing');
      try {
        log('[CommentsScreen] Attempting to access CommentsProvider...');
        Provider.of<CommentsProvider>(context, listen: false)
            .fetchComments(widget.postId);
        log('[CommentsScreen] Successfully called fetchComments.');
      } catch (e, stacktrace) {
        log('[CommentsScreen] ********** ERROR accessing CommentsProvider or calling fetchComments **********');
        log(e.toString());
        log(stacktrace.toString());
        log('[CommentsScreen] ****************************************************************************');
      }
    });
  }

  @override
  void dispose() {
    // Remove listener!
    _commentController.removeListener(_onTextChanged);
    // Clear comments state when the screen is disposed
    // Use addPostFrameCallback to ensure it runs after build completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Check if mounted before accessing provider
        Provider.of<CommentsProvider>(context, listen: false).clearComments();
      }
    });
    _commentController.dispose();
    _scrollController.dispose();
    _debounce?.cancel(); // Cancel debounce timer
    super.dispose();
  }

  // --- Listener method to update state ---
  void _onTextChanged() {
    // Call setState to rebuild the widget and update button state
    setState(() {});
    _updateEnhanceButtonState(); // Update AI button state

    // --- Mention Detection Logic (adapted from create_post_screen) ---
    final text = _commentController.text;
    final cursorPos = _commentController.selection.baseOffset;

    if (cursorPos < 0 || text.isEmpty) {
      _hideMentionsList();
      return;
    }

    final textBeforeCursor = text.substring(0, cursorPos);
    final lastAtSymbolIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtSymbolIndex != -1) {
      bool isStartOfWord = lastAtSymbolIndex == 0 ||
          textBeforeCursor[lastAtSymbolIndex - 1].trim().isEmpty;

      if (isStartOfWord) {
        final query = textBeforeCursor.substring(lastAtSymbolIndex + 1);
        if (!query.contains(RegExp(r'\s')) && query.length <= 20) {
          if (query != _mentionQuery || !_isShowingMentionsList) {
            setState(() {
              _isShowingMentionsList = true;
              _mentionQuery = query;
              _mentionSearchLoading = true;
              _mentionResults = [];
            });
            if (_debounce?.isActive ?? false) _debounce!.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () {
              if (_mentionQuery == query && _isShowingMentionsList) {
                _searchUsers(_mentionQuery);
              }
            });
          }
          return;
        }
      }
    }
    _hideMentionsList();
    // --- End Mention Detection Logic ---
  }
  // -------------------------------------

  // --- Update AI Button State ---
  void _updateEnhanceButtonState() {
    final bool canEnhance = _commentController.text.trim().isNotEmpty ||
        _selectedImageBytes != null;
    if (_isEnhanceButtonEnabled != canEnhance) {
      // Ensure setState is called only if the state actually changes
      if (mounted) {
        // Add mounted check for safety
        setState(() {
          _isEnhanceButtonEnabled = canEnhance;
        });
      }
    }
  }
  // --- End Update AI Button State ---

  // --- Add Mention Helper Functions (Adapted from create_post_screen) ---
  void _hideMentionsList() {
    if (_isShowingMentionsList) {
      setState(() {
        _isShowingMentionsList = false;
        _mentionQuery = '';
        _mentionResults = [];
        _mentionSearchLoading = false;
      });
    }
    _debounce?.cancel();
  }

  Future<void> _searchUsers(String query) async {
    setState(() {
      _mentionSearchLoading = true;
    });

    log(query.isEmpty
        ? '[CommentsScreen] Fetching initial users...'
        : '[CommentsScreen] Searching for users matching: $query');

    final currentUserId =
        Provider.of<AuthService>(context, listen: false).userId;

    try {
      var request = _supabase
          .from('profiles')
          .select('user_id, display_name')
          .neq('user_id', currentUserId ?? '');

      if (query.isNotEmpty) {
        request = request.ilike('display_name', '$query%');
      }

      final response = await request.limit(10);

      if (mounted) {
        setState(() {
          _mentionResults = List<Map<String, dynamic>>.from(response);
          _mentionSearchLoading = false;
          log('[CommentsScreen] Found ${_mentionResults.length} users.');
        });
      }
    } catch (e) {
      log('[CommentsScreen] Error searching users: $e');
      if (mounted) {
        setState(() {
          _mentionSearchLoading = false;
          _mentionResults = [];
        });
      }
    }
  }

  void _onUserMentionSelected(Map<String, dynamic> user) {
    final userId = user['user_id'] as String;
    final displayName = user['display_name'] as String;
    log('[CommentsScreen] Selected user: $displayName (ID: $userId)');

    final currentText = _commentController.text;
    final currentSelection = _commentController.selection;
    final textBeforeCursor =
        currentText.substring(0, currentSelection.baseOffset);
    final lastAtSymbolIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtSymbolIndex != -1) {
      final startIndex = lastAtSymbolIndex;
      final endIndex = currentSelection.baseOffset;
      final mentionText = '@$displayName ';
      final newText =
          currentText.replaceRange(startIndex, endIndex, mentionText);
      final newCursorPos = startIndex + mentionText.length;

      setState(() {
        if (!_taggedUserIds.contains(userId)) {
          _taggedUserIds.add(userId);
        }
        _commentController.text = newText;
        _commentController.selection = TextSelection.fromPosition(
          TextPosition(offset: newCursorPos),
        );
        _hideMentionsList();
      });
      log('[CommentsScreen] Tagged users: $_taggedUserIds');
    } else {
      log('[CommentsScreen] Error: Could not find @ symbol to replace mention.');
      _hideMentionsList();
    }
  }
  // --- End Mention Helper Functions ---

  // --- Image Picking Logic ---
  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70); // Added quality setting
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      // Simple size check (e.g., less than 5MB)
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Image too large (max 5MB)'),
                backgroundColor: Colors.orange),
          );
        }
        return;
      }
      setState(() {
        _selectedImageBytes = bytes;
      });
      _updateEnhanceButtonState(); // Update AI button state
    } else {
      log('No image selected.');
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImageBytes = null;
    });
    _updateEnhanceButtonState(); // Update AI button state
  }
  // --- End Image Picking Logic ---

  // --- AI Enhancement Logic (Adapted from create_post_screen) ---
  Future<void> _enhanceCommentWithAI() async {
    if (_isEnhancing) return;

    setState(() {
      _isEnhancing = true;
    });

    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      log('[CommentsScreen] Error: GEMINI_API_KEY not found.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('AI Enhancement is not configured.'),
              backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isEnhancing = false;
      });
      return;
    }

    final model =
        GenerativeModel(model: 'gemini-1.5-flash-latest', apiKey: apiKey);
    final textContent = _commentController.text.trim();
    final bool hasText = textContent.isNotEmpty;
    final bool hasImage = _selectedImageBytes != null;

    List<DataPart> imageParts = [];
    if (hasImage) {
      try {
        // Assume JPEG for comments, as we don't have MIME type from Uint8List easily
        imageParts.add(DataPart('image/jpeg', _selectedImageBytes!));
        log('[CommentsScreen] Prepared comment image for AI.');
      } catch (e) {
        log('[CommentsScreen] Error preparing image data for AI: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Error processing image for AI.'),
                backgroundColor: Colors.red),
          );
        }
        setState(() {
          _isEnhancing = false;
        });
        return;
      }
    }

    String prompt;
    List<Content> content = [];

    if (hasText && hasImage) {
      prompt =
          'Rewrite the following comment for a social media post, making it more engaging or clear, considering the context from the attached image. Provide only the single, final enhanced text. Original comment: "$textContent"';
      content = [
        Content.multi([TextPart(prompt), ...imageParts])
      ];
    } else if (hasText) {
      prompt =
          'Rewrite the following comment for a social media post to be more engaging, clear, or concise. Provide only the single, final enhanced text. Original comment: "$textContent"';
      content = [Content.text(prompt)];
    } else if (hasImage) {
      prompt =
          'Write *one* short, relevant comment for the attached image, suitable for a social media reply. Provide only the single comment text.';
      content = [
        Content.multi([TextPart(prompt), ...imageParts])
      ];
    } else {
      log('[CommentsScreen] Enhance AI called with no text or image.');
      setState(() {
        _isEnhancing = false;
      });
      return;
    }

    try {
      log('[CommentsScreen] Sending request to Gemini...');
      final response = await model.generateContent(content);

      if (response.text != null) {
        log('[CommentsScreen] Gemini response received: ${response.text}');
        setState(() {
          _commentController.text = response.text!;
          _commentController.selection = TextSelection.fromPosition(
            TextPosition(offset: _commentController.text.length),
          );
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Comment enhanced by AI!'),
                backgroundColor: Colors.green),
          );
        }
      } else {
        log('[CommentsScreen] Gemini response was empty.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('AI enhancement failed: No response.'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      log('[CommentsScreen] Error calling Gemini API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('AI enhancement failed: ${e.toString()}'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEnhancing = false;
        });
      }
    }
  }
  // --- End AI Enhancement Logic ---

  void _addComment() async {
    final commentsProvider =
        Provider.of<CommentsProvider>(context, listen: false);
    final text = _commentController.text.trim();
    // Capture tagged IDs before potential clear
    final List<String> currentTaggedIds = List.from(_taggedUserIds);

    // Check if adding is already in progress OR if both text and image are missing
    if (commentsProvider.isAddingComment ||
        (text.isEmpty && _selectedImageBytes == null)) {
      log('Add comment prevented: Already adding or no content provided.');
      // Optionally show a snackbar if no content is provided
      if (text.isEmpty && _selectedImageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please enter text or select an image.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    // Call provider's addComment with text and potentially image bytes
    final success = await commentsProvider.addComment(
      widget.postId,
      text,
      imageBytes: _selectedImageBytes, // Pass selected image bytes
      taggedUserIds: currentTaggedIds, // <-- Pass tagged IDs
    );

    if (success && mounted) {
      _commentController.clear();
      _removeImage(); // Clear the selected image preview
      _taggedUserIds.clear(); // <-- Clear tagged IDs on success
      // --- Scroll after frame build ---
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      // ---------------------------------
    } else if (!success && mounted) {
      // Show error SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to add comment. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsProvider = context.watch<CommentsProvider>();
    log('[CommentsScreen] build() called. Provider comments count: ${commentsProvider.comments.length}, isLoading: ${commentsProvider.isLoading}, isAdding: ${commentsProvider.isAddingComment}');
    final authService = context.watch<AuthService>(); // Get auth service
    final currentUserId = authService.userId;

    // Function to handle popping with the current comment count
    void popWithCommentCount() {
      final commentsProvider =
          Provider.of<CommentsProvider>(context, listen: false);
      final currentCount = commentsProvider.comments.length;
      log('[CommentsScreen] Popping with comment count: $currentCount');
      Navigator.pop(context, currentCount);
    }

    // Use WillPopScope to intercept the system back button
    return WillPopScope(
      onWillPop: () async {
        popWithCommentCount();
        return false; // Prevent default back navigation
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Comments'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          // --- Add custom leading action ---
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            tooltip: 'Back',
            onPressed: () {
              popWithCommentCount(); // Ensure the custom pop function is called
            },
          ),
        ),
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF87CEEB), Color(0xFF4682B4)], // Same as feed
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: _buildCommentsList(commentsProvider, currentUserId),
              ),
              _buildCommentInputField(commentsProvider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsList(
      CommentsProvider commentsProvider, String? currentUserId) {
    log('[CommentsScreen] _buildCommentsList called. Provider comments count: ${commentsProvider.comments.length}, isLoading: ${commentsProvider.isLoading}');

    if (commentsProvider.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    if (commentsProvider.comments.isEmpty && !commentsProvider.isLoading) {
      return const Center(
        child: Text(
          'No comments yet. Be the first!',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    final comments = commentsProvider.comments;
    final DateFormat dateFormat = DateFormat('HH:mm - dd/MM/yy');

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
          top: kToolbarHeight + 8, bottom: 8, left: 12, right: 12),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        final bool isSelfComment =
            currentUserId != null && comment.userId == currentUserId;
        final bool isAuthorComment = comment.isAuthor;
        final Uint8List? imageBytes = comment.imageBytes;
        final bool hasImage = imageBytes != null;

        // --- Define styles for RichText ---
        final defaultCommentStyle =
            const TextStyle(color: Colors.white, fontSize: 15, height: 1.3);
        final mentionCommentStyle = TextStyle(
            color: Colors.lightBlue.shade200,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            height: 1.3);
        // -----------------------------------

        // --- The actual comment content widget ---
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
          decoration: BoxDecoration(
            color: isSelfComment
                ? Colors.blueGrey.withOpacity(0.3)
                : Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Row(
            // Use Row to place button next to text
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // Make text column take available space
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Info Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          // Priority: YOU > Author (OP) > Display Name > Anonymous
                          isSelfComment
                              ? 'YOU'
                              : (isAuthorComment
                                  ? 'Author (OP)'
                                  : (comment.displayName ?? 'Anonymous')),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isSelfComment
                                ? 11
                                : (isAuthorComment ? 13 : 11),
                            color: Colors.white.withOpacity(0.8),
                            letterSpacing: 0.5,
                          ),
                        ),
                        // Conditionally add Delete Button to this row
                        if (isSelfComment)
                          SizedBox(
                            height: 24, // Constrain height
                            width: 24, // Constrain width
                            child: IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Colors.redAccent.withOpacity(0.8),
                                  size: 18), // Adjust size
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Delete Comment',
                              // Prevent action if already deleting another comment
                              onPressed: commentsProvider.isDeletingComment
                                  ? null
                                  : () {
                                      _confirmAndDeleteComment(
                                          context, comment.id);
                                    },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Display Image if available
                    if (hasImage)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                        child: GestureDetector(
                          onTap: () {
                            // --- Show full image dialog ---
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: const EdgeInsets.all(10),
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: InteractiveViewer(
                                    child: Center(
                                      child: Image.memory(
                                        imageBytes!,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          log('Error displaying full comment image: $error');
                                          return const Icon(Icons.broken_image,
                                              color: Colors.white54, size: 60);
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                            // --- End full image dialog ---
                          },
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(context).size.height *
                                  0.3, // Limit image height
                            ),
                            child: Image.memory(
                              imageBytes!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) {
                                log('Error loading comment image preview: $error');
                                return Container(
                                    height: 100,
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.broken_image,
                                        color: Colors.white54, size: 40));
                              },
                            ),
                          ),
                        ),
                      ),
                    // Display Text if available using RichText
                    if (comment.commentText.isNotEmpty)
                      RichText(
                        text: TextSpan(
                          children: buildTextSpansWithMentions(
                            comment.commentText,
                            defaultCommentStyle,
                            mentionCommentStyle,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      dateFormat.format(comment.createdAt.toLocal()),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // --- Remove Delete Button from here ---
            ],
          ),
        );
        // --- End comment content widget ---
      },
    );
  }

  // --- Helper for delete confirmation dialog (no changes needed) ---
  void _confirmAndDeleteComment(BuildContext buildContext, String commentId) {
    showDialog(
      context: buildContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          backgroundColor: Theme.of(context).canvasColor.withOpacity(0.95),
          icon: const Icon(Icons.warning_amber_rounded,
              color: Colors.red, size: 40),
          title: const Text('Delete Comment', textAlign: TextAlign.center),
          content: const Text(
            'Are you sure you want to delete this comment? This action cannot be undone.',
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
                final success = await Provider.of<CommentsProvider>(
                        buildContext,
                        listen: false)
                    .deleteComment(commentId);
                // Show SnackBar based on result - check if context is still valid
                if (!success && mounted) {
                  ScaffoldMessenger.of(buildContext).showSnackBar(
                    const SnackBar(
                      content: Text('Error deleting comment.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
                // No success SnackBar needed, the list will refresh via provider
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
  // --- End delete confirmation ---

  // --- Helper Widget for Mentions List (Adapted from create_post_screen) ---
  Widget _buildMentionsList() {
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
      listContent = ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: _mentionResults.length,
        itemBuilder: (context, index) {
          final user = _mentionResults[index];
          final displayName = user['display_name'] ?? 'N/A';
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _onUserMentionSelected(user),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12.0, vertical: 12.0), // Keep increased padding
                child: Text(
                  displayName,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        },
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: listContent,
    );
  }
  // --- End Helper Widget ---

  // --- Update Input Field Builder ---
  Widget _buildCommentInputField(CommentsProvider commentsProvider) {
    return Container(
      padding: EdgeInsets.only(
        left: 8.0, // Adjust padding
        right: 8.0,
        top: 8.0,
        bottom: MediaQuery.of(context).padding.bottom + 8.0, // Handle safe area
      ),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.1),
          border:
              Border(top: BorderSide(color: Colors.white.withOpacity(0.2)))),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Take minimum vertical space
        children: [
          // --- Image Preview Row (if image selected) ---
          if (_selectedImageBytes != null)
            Padding(
              padding:
                  const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
              child: Row(
                children: [
                  Container(
                    constraints:
                        const BoxConstraints(maxHeight: 60, maxWidth: 60),
                    child:
                        Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Image selected',
                        style: TextStyle(color: Colors.white70)),
                  ),
                  // --- AI Enhance Button (in preview row) ---
                  Tooltip(
                    message: 'Enhance with AI',
                    child: IconButton(
                      icon: _isEnhancing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white70))
                          : Icon(Icons.auto_awesome,
                              color: _isEnhanceButtonEnabled
                                  ? Colors.white70
                                  : Colors.grey.withOpacity(0.5)),
                      onPressed: _isEnhancing || !_isEnhanceButtonEnabled
                          ? null
                          : _enhanceCommentWithAI,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    tooltip: 'Remove Image',
                    onPressed: _removeImage,
                  ),
                ],
              ),
            ),
          // --- Input Column (TextField + Mentions List) ---
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Mentions List ---
              if (_isShowingMentionsList) _buildMentionsList(),
              // --- Input Row (TextField + Buttons) ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // --- Add Image OR AI Button (if no image) ---
                  if (_selectedImageBytes == null)
                    Tooltip(
                      message: 'Enhance with AI',
                      child: IconButton(
                        icon: _isEnhancing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white70))
                            : Icon(Icons.auto_awesome,
                                color: _isEnhanceButtonEnabled
                                    ? Colors.white70
                                    : Colors.grey.withOpacity(0.5)),
                        onPressed: _isEnhancing || !_isEnhanceButtonEnabled
                            ? null
                            : _enhanceCommentWithAI,
                      ),
                    ),
                  if (_selectedImageBytes == null)
                    IconButton(
                      icon: const Icon(Icons.image_outlined,
                          color: Colors.white70),
                      tooltip: 'Add Image',
                      onPressed: _pickImage,
                    ),
                  // --- Text Field ---
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a comment... Use @ to mention',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.6)),
                        border: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10.0, horizontal: 8.0), // Adjust padding
                        isDense: true, // Make field less tall
                      ),
                      onSubmitted: (_) =>
                          _addComment(), // Allow sending with keyboard action
                    ),
                  ),
                  // --- Send Button ---
                  IconButton(
                    icon: commentsProvider.isAddingComment
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ))
                        : const Icon(Icons.send, color: Colors.white),
                    // Disable if adding OR if both text and image are null
                    onPressed: commentsProvider.isAddingComment ||
                            (_commentController.text.trim().isEmpty &&
                                _selectedImageBytes == null)
                        ? null
                        : _addComment,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
