import 'package:flutter/foundation.dart';

@immutable
class ConversationSummary {
  final String otherUserId;
  final String otherUserDisplayName;
  final String lastMessageText;
  final DateTime lastMessageTimestamp;
  final String lastMessageFromUserId;
  // final bool isRead; // Optional: Add later if needed

  const ConversationSummary({
    required this.otherUserId,
    required this.otherUserDisplayName,
    required this.lastMessageText,
    required this.lastMessageTimestamp,
    required this.lastMessageFromUserId,
    // required this.isRead,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationSummary &&
          runtimeType == other.runtimeType &&
          otherUserId == other.otherUserId; // Identify conversation by the other user

  @override
  int get hashCode => otherUserId.hashCode;
} 