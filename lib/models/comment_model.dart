import 'dart:developer';

// Define a model for the Comment data
class Comment {
  final String id;
  final String postId;
  final String userId;
  final String commentText;
  final DateTime createdAt;
  // final String? parentCommentId; // Optional: for threaded replies

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.commentText,
    required this.createdAt,
    // this.parentCommentId,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    // Basic validation
    if (json['comment_id'] == null ||
        json['post_id'] == null ||
        json['user_id'] == null ||
        json['comment_text'] == null ||
        json['created_at'] == null) {
      log('Error: Missing required field in comment JSON: $json');
      throw FormatException('Invalid comment data received: $json');
    }

    return Comment(
      id: json['comment_id'] as String,
      postId: json['post_id'] as String,
      userId: json['user_id'] as String,
      commentText: json['comment_text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      // parentCommentId: json['parent_comment_id'] as String?, // Parse if using
    );
  }
} 