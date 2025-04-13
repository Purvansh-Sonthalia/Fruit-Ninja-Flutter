class UserScore {
  final String uid; // User ID from Firebase Auth or similar
  final String? displayName;
  final String? email;
  final int highScore;

  UserScore({
    required this.uid,
    this.displayName,
    this.email,
    required this.highScore,
  });

  // Optional: Factory constructor to create a UserScore from a map (e.g., Firestore data)
  factory UserScore.fromMap(Map<String, dynamic> map, String documentId) {
    return UserScore(
      uid: documentId, // Often the document ID is the user's UID
      displayName: map['displayName'] as String?,
      email: map['email'] as String?, // Supabase might not return email here if RLS hides it
      highScore: map['highScore'] as int? ?? 0,
    );
  }

  // *** NEW: Factory constructor for Supabase data where user_id is a field ***
  factory UserScore.fromSupabaseMap(Map<String, dynamic> map) {
    return UserScore(
      uid: map['user_id'] as String, // Use user_id from the map data
      displayName: map['display_name'] as String?,
      email: map['email'] as String?, // Still might be null depending on RLS
      highScore: map['high_score'] as int? ?? 0,
    );
  }

  // Optional: Method to convert UserScore to a map (e.g., for saving to Firestore)
  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'highScore': highScore,
      // uid is often the document ID, so not always stored as a field
    };
  }
} 