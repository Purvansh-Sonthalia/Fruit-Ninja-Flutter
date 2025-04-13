import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import 'dart:typed_data'; // For Uint8List
import 'dart:io'; // For File
import '../providers/comments_provider.dart';
import '../services/auth_service.dart'; // To check current user
import 'package:image_picker/image_picker.dart'; // Import image_picker

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

  @override
  void initState() {
    super.initState();
    log('[CommentsScreen] initState START');
    // Add listener to force rebuild on text change for button state
    _commentController.addListener(_onTextChanged);
    // Fetch comments when the screen loads
    // Use addPostFrameCallback to ensure provider is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
       if (mounted) { // Check if mounted before accessing provider
         Provider.of<CommentsProvider>(context, listen: false).clearComments();
       }
    });
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- Listener method to update state --- 
  void _onTextChanged() {
    // Call setState to rebuild the widget and update button state
    setState(() {}); 
  }
  // -------------------------------------

  // --- Image Picking Logic --- 
  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70); // Added quality setting
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      // Simple size check (e.g., less than 5MB)
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Image too large (max 5MB)'), backgroundColor: Colors.orange),
            );
         }
         return;
      }
      setState(() {
        _selectedImageBytes = bytes;
      });
    } else {
      log('No image selected.');
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImageBytes = null;
    });
  }
  // --- End Image Picking Logic --- 

  void _addComment() async {
    final commentsProvider = Provider.of<CommentsProvider>(context, listen: false);
    final text = _commentController.text.trim();

    // Check if adding is already in progress OR if both text and image are missing
    if (commentsProvider.isAddingComment || (text.isEmpty && _selectedImageBytes == null)) {
      log('Add comment prevented: Already adding or no content provided.');
      // Optionally show a snackbar if no content is provided
      if (text.isEmpty && _selectedImageBytes == null) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Please enter text or select an image.'), backgroundColor: Colors.orange),
         );
      }
      return;
    }

    // Call provider's addComment with text and potentially image bytes
    final success = await commentsProvider.addComment(
      widget.postId, 
      text,
      imageBytes: _selectedImageBytes, // Pass selected image bytes
    );

    if (success && mounted) {
      _commentController.clear();
      _removeImage(); // Clear the selected image preview
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
      final commentsProvider = Provider.of<CommentsProvider>(context, listen: false);
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

  Widget _buildCommentsList(CommentsProvider commentsProvider, String? currentUserId) {
    log('[CommentsScreen] _buildCommentsList called. Provider comments count: ${commentsProvider.comments.length}, isLoading: ${commentsProvider.isLoading}');

    if (commentsProvider.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
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
      padding: const EdgeInsets.only(top: kToolbarHeight + 8, bottom: 8, left: 12, right: 12),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        final bool isSelfComment = currentUserId != null && comment.userId == currentUserId;
        final bool isAuthorComment = comment.isAuthor;
        final Uint8List? imageBytes = comment.imageBytes; 
        final bool hasImage = imageBytes != null;

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
          child: Row( // Use Row to place button next to text
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded( // Make text column take available space
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
                            fontSize: isSelfComment ? 11 : (isAuthorComment ? 13 : 11),
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
                              icon: Icon(Icons.delete_outline, color: Colors.redAccent.withOpacity(0.8), size: 18), // Adjust size
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Delete Comment',
                              // Prevent action if already deleting another comment
                              onPressed: commentsProvider.isDeletingComment ? null : () {
                                _confirmAndDeleteComment(context, comment.id);
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
                                        errorBuilder: (context, error, stackTrace) {
                                          log('Error displaying full comment image: $error');
                                          return const Icon(Icons.broken_image, color: Colors.white54, size: 60);
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
                              maxHeight: MediaQuery.of(context).size.height * 0.3, // Limit image height
                            ),
                            child: Image.memory(
                              imageBytes!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) {
                                log('Error loading comment image preview: $error');
                                return Container(height: 100, alignment: Alignment.center, child: const Icon(Icons.broken_image, color: Colors.white54, size: 40));
                              },
                            ),
                          ),
                        ),
                      ),
                    // Display Text if available
                    if (comment.commentText.isNotEmpty)
                      Text(
                        comment.commentText,
                        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
              backgroundColor: Theme.of(context).canvasColor.withOpacity(0.95),
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 40),
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
                  onPressed: () async { // Make async
                    Navigator.of(dialogContext).pop(); // Close the dialog
                     // Call provider delete method
                     final success = await Provider.of<CommentsProvider>(buildContext, listen: false)
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
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2)))
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Take minimum vertical space
        children: [
          // --- Image Preview Row (if image selected) --- 
          if (_selectedImageBytes != null)
             Padding(
               padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
               child: Row(
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxHeight: 60, maxWidth: 60),
                      child: Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Image selected', style: TextStyle(color: Colors.white70)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      tooltip: 'Remove Image',
                      onPressed: _removeImage,
                    ),
                  ],
               ),
             ),
           // --- Input Row (TextField and Buttons) --- 
          Row(
            crossAxisAlignment: CrossAxisAlignment.end, // Align items to bottom
            children: [
              // --- Add Image Button (only if no image selected) --- 
              if (_selectedImageBytes == null)
                IconButton(
                  icon: const Icon(Icons.image_outlined, color: Colors.white70),
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
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0), // Adjust padding
                    isDense: true, // Make field less tall
                  ),
                  onSubmitted: (_) => _addComment(), // Allow sending with keyboard action
                ),
              ),
              // --- Send Button --- 
              IconButton(
                icon: commentsProvider.isAddingComment
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,)) 
                    : const Icon(Icons.send, color: Colors.white),
                // Disable if adding OR if both text and image are null
                onPressed: commentsProvider.isAddingComment || (_commentController.text.trim().isEmpty && _selectedImageBytes == null) 
                           ? null 
                           : _addComment,
              ),
            ],
          ),
        ],
      ),
    );
  }
} 