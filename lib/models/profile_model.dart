import 'package:flutter/foundation.dart';

@immutable
class Profile {
  final String userId;
  final String displayName;
  // Add other profile fields if needed later (e.g., avatar_url)

  const Profile({
    required this.userId,
    required this.displayName,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      // Use 'id' if it comes from auth.users, 'user_id' if it comes from profiles table
      userId: json['user_id'] as String? ?? json['id'] as String? ?? 'unknown_id',
      displayName: json['display_name'] as String? ?? 'Anonymous',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          runtimeType == other.runtimeType &&
          userId == other.userId;

  @override
  int get hashCode => userId.hashCode;
} 