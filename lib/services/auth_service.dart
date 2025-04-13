import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import '../models/user_score.dart'; // Import the UserScore model

class AuthService extends ChangeNotifier {
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  bool _isLoading = false;

  // Key for local display name storage (mirrors HomeScreen)
  static const String _displayNameKey = 'user_display_name'; 

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _supabaseClient.auth.currentUser != null;
  String? get username => _supabaseClient.auth.currentUser?.email;
  String? get userId => _supabaseClient.auth.currentUser?.id;

  // Initialize Supabase
  static Future<void> initialize(String supabaseUrl, String supabaseAnonKey) async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  // Sign in user with email and password
  Future<bool> signIn(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('Sign-in error: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Sign up user with email and password
  Future<bool> signUp(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _supabaseClient.auth.signUp(
        email: email,
        password: password,
      );
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Sign out user
  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _supabaseClient.auth.signOut();

      // Clear local storage for display name on logout
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_displayNameKey);
      print("Cleared local display name on logout.");
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Listen to auth state changes
  void listenToAuthChanges() {
    _supabaseClient.auth.onAuthStateChange.listen((data) {
      notifyListeners();
    });
  }

  // Fetch the current user's display name from Supabase
  Future<String?> getCurrentDisplayName() async {
    if (!isLoggedIn) return null;
    try {
      final response = await _supabaseClient
          .from('profiles')
          .select('display_name')
          .eq('user_id', userId!) // Use user_id based on image
          .maybeSingle(); // Use maybeSingle for potentially null result

      if (response != null && response['display_name'] != null) {
        return response['display_name'] as String?;
      }
      return null;
    } catch (e) {
      print("Error fetching display name: $e");
      return null; // Return null on error
    }
  }

  // Update user's display name in Supabase
  // Returns true on success, false on failure (e.g., name taken, not logged in)
  // Throws exception on Supabase error during update.
  Future<bool> updateDisplayName(String newName) async {
    if (!isLoggedIn || userId == null) {
      print("User not logged in to update display name.");
      return false; // Not logged in
    }
    if (newName.trim().isEmpty) {
      print("Display name cannot be empty.");
      return false; // Name empty
    }

    try {
      _isLoading = true;
      notifyListeners();

      // 1. Check if the name is already taken by *another* user
      final existingNameResponse = await _supabaseClient
          .from('profiles')
          .select('user_id') // Select user_id based on image
          .eq('display_name', newName)
          .neq('user_id', userId!) // Exclude the current user
          .limit(1); // We only need to know if at least one exists


      if (existingNameResponse.isNotEmpty) {
          // Name is taken by someone else
          print("Display name '$newName' is already taken.");
          _isLoading = false;
          notifyListeners();
          return false; 
      }

      // 2. Update or Insert the display name for the current user using upsert
      await _supabaseClient.from('profiles').upsert({
        'user_id': userId!, // Include user_id for matching/inserting
        'display_name': newName,
        // Add other default fields for a new profile if necessary
      }); // Default upsert behavior matches on primary key (user_id)

      print("Display name upserted successfully for user $userId.");
      _isLoading = false;
      notifyListeners();
      return true; // Success

    } catch (e) {
      print('Error updating display name: $e');
      _isLoading = false;
      notifyListeners();
      // Rethrow the exception to be caught by the UI for specific error handling
      throw Exception('Failed to update display name: $e'); 
    }
  }

  // Fetch leaderboard scores from Supabase by fetching scores and profiles separately
  Future<List<UserScore>> getLeaderboardScores({int limit = 100}) async {
    try {
      // 1. Fetch top scores from the 'scores' table
      final scoresResponse = await _supabaseClient
          .from('scores')
          .select('user_id, high_score')
          .order('high_score', ascending: false)
          .limit(limit);

      if (scoresResponse == null) {
        print('Error fetching scores: Response was null');
        return [];
      }

      final List<dynamic> scoresData = scoresResponse as List<dynamic>;
      if (scoresData.isEmpty) {
        return []; // No scores found
      }

      // 2. Extract user IDs from the scores
      final List<String> userIds = scoresData
          .map((score) => score['user_id'] as String)
          .toList();

      // 3. Fetch profiles for these specific user IDs
      final profilesResponse = await _supabaseClient
          .from('profiles')
          .select('user_id, display_name')
          .inFilter('user_id', userIds); // Fetch only profiles for the top scorers

      if (profilesResponse == null) {
        print('Error fetching profiles: Response was null');
        // We can still return scores, but names might be missing
        // Or throw an error, depending on desired behavior
      }

      final List<dynamic> profilesData = profilesResponse as List<dynamic>? ?? [];

      // 4. Create a map for easy lookup of display names by user_id
      final Map<String, String?> profileMap = {
        for (var profile in profilesData) 
          profile['user_id'] as String: profile['display_name'] as String?,
      };

      // 5. Merge scores data with profile data
      final List<UserScore> leaderboardScores = scoresData.map((score) {
        final userId = score['user_id'] as String;
        final highScore = score['high_score'] as int? ?? 0;
        final displayName = profileMap[userId]; // Lookup display name

        return UserScore(
          uid: userId,
          highScore: highScore,
          displayName: displayName, // Might be null if profile fetch failed or no profile exists
          email: null, // Not fetched
        );
      }).toList();

      return leaderboardScores;

    } catch (e) {
      print('Error fetching leaderboard scores: $e');
      if (e is PostgrestException) {
        print('PostgREST Error: ${e.message}');
        print('Hint: ${e.hint}');
        print('Details: ${e.details}');
      }
      throw Exception('Failed to load leaderboard: $e');
    }
  }
} 