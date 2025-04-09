import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ScoresService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  
  // Get the current user's high score
  Future<int> getUserHighScore() async {
    try {
      final userId = _supabaseClient.auth.currentUser?.id;
      
      if (userId == null) {
        if (kDebugMode) {
          print('getUserHighScore: User not logged in');
        }
        return 0; // Not logged in, return default score
      }
      
      final response = await _supabaseClient
          .from('scores')
          .select('high_score')
          .eq('user_id', userId)
          .maybeSingle();
      
      if (response == null) {
        if (kDebugMode) {
          print('getUserHighScore: No record found for user $userId');
        }
        return 0; // No record found
      }
      
      final highScore = response['high_score'] as int;
      if (kDebugMode) {
        print('getUserHighScore: Fetched high score: $highScore for user $userId');
      }
      return highScore;
    } catch (e) {
      // Handle error
      if (kDebugMode) {
        print('Error fetching high score: $e');
      }
      return 0;
    }
  }
  
  // Update the user's high score
  Future<bool> updateUserHighScore(int score) async {
    try {
      final userId = _supabaseClient.auth.currentUser?.id;
      
      if (userId == null) {
        if (kDebugMode) {
          print('updateUserHighScore: User not logged in, can\'t update score');
        }
        return false; // Not logged in, can't update
      }
      
      // Check if user already has a score record
      final existingRecord = await _supabaseClient
          .from('scores')
          .select('high_score')
          .eq('user_id', userId)
          .maybeSingle();
      
      if (existingRecord == null) {
        // Create new record if none exists
        if (kDebugMode) {
          print('updateUserHighScore: Creating new record for user $userId with score $score');
        }
        
        final response = await _supabaseClient
            .from('scores')
            .insert({
              'user_id': userId,
              'high_score': score
            })
            .select();
            
        if (kDebugMode) {
          print('updateUserHighScore: Created record response: $response');
        }
        return true;
      } else if (score > (existingRecord['high_score'] as int)) {
        // Update only if new score is higher
        final oldScore = existingRecord['high_score'] as int;
        if (kDebugMode) {
          print('updateUserHighScore: Updating high score from $oldScore to $score for user $userId');
        }
        
        final response = await _supabaseClient
            .from('scores')
            .update({'high_score': score})
            .eq('user_id', userId)
            .select();
            
        if (kDebugMode) {
          print('updateUserHighScore: Update response: $response');
        }
        return true;
      } else {
        // Current score is not higher than high score
        if (kDebugMode) {
          print('updateUserHighScore: Current score $score is not higher than existing high score ${existingRecord['high_score']}');
        }
        return false;
      }
    } catch (e) {
      // Handle error
      if (kDebugMode) {
        print('Error updating high score: $e');
      }
      return false;
    }
  }
} 