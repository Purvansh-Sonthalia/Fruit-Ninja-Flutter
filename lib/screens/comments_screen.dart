import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import '../providers/comments_provider.dart';
import '../services/auth_service.dart'; // To check current user

class CommentsScreen extends StatefulWidget {
  final String postId;

  const CommentsScreen({super.key, required this.postId});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController(); // To scroll to bottom

  @override
  void initState() {
    super.initState();
    // Fetch comments when the screen loads
    // Use addPostFrameCallback to ensure provider is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CommentsProvider>(context, listen: false)
          .fetchComments(widget.postId);
    });
  }

  @override
  void dispose() {
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

  void _addComment() async {
    final commentsProvider = Provider.of<CommentsProvider>(context, listen: false);
    final text = _commentController.text.trim();
    if (text.isNotEmpty && !commentsProvider.isAddingComment) {
      final success = await commentsProvider.addComment(widget.postId, text);
      if (success && mounted) {
        _commentController.clear();
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
                    Text(
                       isSelfComment ? 'YOU' : (isAuthorComment ? 'Author (OP)' : 'Anonymous'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isAuthorComment ? 13: 11,
                        //isSelfComment ? 11 : 
                        //isAuthorComment
                        // ? 14
                        // : 11,
                        //11,

                        color: Colors.white.withOpacity(0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
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
              // --- Conditionally add Delete Button ---
              if (isSelfComment)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.redAccent.withOpacity(0.8), size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete Comment',
                   // Prevent action if already deleting another comment
                  onPressed: commentsProvider.isDeletingComment ? null : () {
                     _confirmAndDeleteComment(context, comment.id);
                  },
                ),
              // --- End Delete Button ---
            ], // --- Conditionally add Delete Button ---
          ),
        );
        // --- End comment content widget ---
      },
    );
  }

   // --- Helper for delete confirmation dialog ---
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
                      // No success SnackBar needed, optimistic UI already removed it
                  },
                  child: const Text('Delete'),
                ),
              ],
          );
        },
     );
  }
  // --- End delete confirmation ---

  Widget _buildCommentInputField(CommentsProvider commentsProvider) {
    return Container(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 8.0,
        top: 8.0,
        bottom: MediaQuery.of(context).padding.bottom + 8.0, // Handle safe area
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2)))
      ),
      child: Row(
        children: [
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
              ),
              onSubmitted: (_) => _addComment(), // Allow sending with keyboard action
            ),
          ),
          IconButton(
            icon: commentsProvider.isAddingComment
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,)) 
                : const Icon(Icons.send, color: Colors.white),
            onPressed: commentsProvider.isAddingComment ? null : _addComment,
          ),
        ],
      ),
    );
  }
} 