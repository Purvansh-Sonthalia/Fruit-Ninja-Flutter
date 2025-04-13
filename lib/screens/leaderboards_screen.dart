import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart'; // Assuming AuthService handles leaderboard data
import '../models/user_score.dart'; // Assuming a model for score data

class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen> {
  late Future<List<UserScore>> _leaderboardFuture;

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  void _fetchLeaderboard() {
    final authService = Provider.of<AuthService>(context, listen: false);
    // Assuming AuthService has a method like getLeaderboardScores()
    // You might need to add this method to AuthService if it doesn't exist
    _leaderboardFuture = authService.getLeaderboardScores(); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboards'),
        backgroundColor: Colors.blueGrey, // Or match your theme
      ),
      body: Container(
         decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF87CEEB), // Sky blue
                Color(0xFF4682B4), // Steel blue
              ],
            ),
          ),
        child: FutureBuilder<List<UserScore>>(
          future: _leaderboardFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              print("Leaderboard Error: ${snapshot.error}"); // Log the error
              return Center(
                  child: Text(
                      'Error loading leaderboard: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                  ),
              );
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No scores yet!'));
            }

            final scores = snapshot.data!;

            // Sort scores descending
            scores.sort((a, b) => b.highScore.compareTo(a.highScore));

            return ListView.builder(
              itemCount: scores.length,
              itemBuilder: (context, index) {
                final userScore = scores[index];
                final rank = index + 1;
                
                // Determine display name (prefer displayName, fallback to email)
                final displayName = userScore.displayName?.isNotEmpty == true 
                    ? userScore.displayName!
                    : (userScore.email?.isNotEmpty == true ? userScore.email! : 'Anonymous');

                // Determine avatar background color based on rank
                Color avatarColor;
                switch (rank) {
                  case 1:
                    avatarColor = Colors.amber; // Gold
                    break;
                  case 2:
                    avatarColor = Colors.grey.shade400; // Silver
                    break;
                  case 3:
                    avatarColor = Colors.brown.shade400; // Bronze
                    break;
                  default:
                    avatarColor = Colors.white; // White for the rest
                }

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  color: Colors.white.withOpacity(0.85),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: avatarColor, // Use rank-based color
                      child: Text(
                        '$rank', 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                    ),
                    title: Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black, // Set display name color to black
                      ),
                      ),
                    trailing: Text(
                      '${userScore.highScore}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
} 