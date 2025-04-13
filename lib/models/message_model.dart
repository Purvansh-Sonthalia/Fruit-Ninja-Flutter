import 'package:flutter/foundation.dart';

@immutable
class Message {
  final String messageId;
  final DateTime createdAt;
  final String fromUserId;
  final String toUserId;
  final String? messageText;
  final Map<String, dynamic>? messageMedia; // Assuming JSON is decoded into a Map
  final String? parentMessageId;
  // Add fields for display names if needed (fetched separately)
  final String? fromUserDisplayName;
  final String? toUserDisplayName;

  const Message({
    required this.messageId,
    required this.createdAt,
    required this.fromUserId,
    required this.toUserId,
    this.messageText,
    this.messageMedia,
    this.parentMessageId,
    this.fromUserDisplayName, // Optional, to be populated later
    this.toUserDisplayName, // Optional, to be populated later
  });

  // Factory constructor to create a Message from JSON (database row)
  factory Message.fromJson(
    Map<String, dynamic> json,
    {
      String? fromDisplayName, // Added parameter
      String? toDisplayName,   // Added parameter
    }
  ) {
    // Basic parsing
    return Message(
      messageId: json['message_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      fromUserId: json['from_user_id'] as String,
      toUserId: json['to_user_id'] as String,
      messageText: json['message_text'] as String?,
      messageMedia: json['message_media'] as Map<String, dynamic>?,
      parentMessageId: json['parent_message_id'] as String?,
      // Use the passed parameters for display names
      fromUserDisplayName: fromDisplayName, // Use parameter
      toUserDisplayName: toDisplayName,   // Use parameter
    );
  }


  // Optional: Add a method to convert back to JSON if needed
  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'created_at': createdAt.toIso8601String(),
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'message_text': messageText,
      'message_media': messageMedia,
      'parent_message_id': parentMessageId,
      // Add other fields if necessary for sending data back
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId;

  @override
  int get hashCode => messageId.hashCode;
} 