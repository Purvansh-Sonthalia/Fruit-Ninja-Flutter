import 'dart:developer';
import 'dart:convert'; // For base64
import 'dart:typed_data'; // For Uint8List

// Define a model for the Comment data
class Comment {
  final String id;
  final String postId;
  final String userId;
  final String commentText;
  final DateTime createdAt;
  final bool isAuthor;
  final String? displayName;
  final String? commentMediaBase64; // <-- Field for Base64 image data
  // final String? parentCommentId; // Optional: for threaded replies

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.commentText,
    required this.createdAt,
    required this.isAuthor,
    this.displayName,
    this.commentMediaBase64, // <-- Add to constructor
    // this.parentCommentId,
  });

  factory Comment.fromJson(Map<String, dynamic> json, {String? fetchedDisplayName, required bool isCommentAuthor}) {
    // Basic validation
    if (json['comment_id'] == null ||
        json['post_id'] == null ||
        json['user_id'] == null ||
        // comment_text can be null/empty if there's only an image
        // json['comment_text'] == null || 
        json['created_at'] == null) {
      log('Error: Missing required field in comment JSON: $json');
      throw FormatException('Invalid comment data received: $json');
    }

    return Comment(
      id: json['comment_id'] as String,
      postId: json['post_id'] as String,
      userId: json['user_id'] as String,
      // Handle potentially null comment text
      commentText: json['comment_text'] as String? ?? '', 
      createdAt: DateTime.parse(json['created_at'] as String),
      isAuthor: isCommentAuthor,
      displayName: fetchedDisplayName,
      commentMediaBase64: json['comment_media'] as String?, // <-- Parse comment_media
      // parentCommentId: json['parent_comment_id'] as String?, // Parse if using
    );
  }

  // Helper to get image bytes from Base64, returns null on error or if no data
  Uint8List? get imageBytes {
    if (commentMediaBase64 == null || commentMediaBase64!.isEmpty) {
      return null;
    }
    try {
      return base64Decode(commentMediaBase64!);
    } catch (e) {
      log('Error decoding Base64 comment media (comment $id): $e');
      return null;
    }
  }
} 