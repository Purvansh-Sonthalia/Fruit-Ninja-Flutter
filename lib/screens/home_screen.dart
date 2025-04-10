import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'game_screen.dart';
import 'auth_screen.dart';
import '../services/auth_service.dart';
import 'package:flutter/services.dart';
import 'weather_screen.dart';
import '../services/weather_provider.dart';
import 'settings_screen.dart';
import '../utils/assets_manager.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WeatherProvider>().fetchWeatherIfNeeded();
      context.read<AssetsManager>().playBackgroundMusic();
    });

    return Scaffold(
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
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  const Text(
                    'FRUIT NINJA',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 10.0,
                          color: Colors.red,
                          offset: Offset(5.0, 5.0),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),

                  // Play Button
                  _buildMenuButton(context, 'PLAY', Colors.red, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GameScreen(),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // How to Play Button
                  _buildMenuButton(context, 'HOW TO PLAY', Colors.orange, () {
                    _showHowToPlayDialog(context);
                  }),
                  const SizedBox(height: 20),

                  // Auth Button (Login/SignUp or Logout)
                  Consumer<AuthService>(
                    builder:
                        (ctx, authService, _) => _buildMenuButton(
                          context,
                          authService.isLoggedIn ? 'LOGOUT' : 'LOGIN / SIGN UP',
                          Colors.green,
                          () {
                            if (authService.isLoggedIn) {
                              authService.signOut();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Successfully logged out'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AuthScreen(),
                                ),
                              );
                            }
                          },
                        ),
                  ),
                  const SizedBox(height: 20),

                  // Credits Button
                  _buildMenuButton(context, 'CREDITS', Colors.blue, () {
                    _showCreditsDialog(context);
                  }),
                  const SizedBox(height: 20),

                  // Exit Button (New)
                  _buildMenuButton(context, 'EXIT', Colors.grey[700]!, () {
                    SystemNavigator.pop();
                  }),
                ],
              ),
            ),
            // --- Icons in Corners ---
            // Settings Icon Button (Top-Left)
            Positioned(
              top: 40.0,
              left: 10.0, // Anchor to left
              child: IconButton(
                icon: const Icon(
                  Icons.settings,
                  color: Colors.white,
                  size: 38.0,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
                tooltip: 'Settings',
              ),
            ),

            // Weather Icon Button (Top-Right)
            Positioned(
              top: 40.0,
              right: 10.0, // Keep anchored to right
              // Remove the Row, place IconButton directly
              child: IconButton(
                icon: const Icon(
                  Icons.wb_sunny,
                  color: Colors.orangeAccent,
                  size: 40.0,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WeatherScreen(),
                    ),
                  );
                },
                tooltip: 'Weather',
              ),
            ),
            // --- End Icons ---
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context,
    String text,
    Color color,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: 250,
      height: 70,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 5,
        ),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  void _showHowToPlayDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              'How to Play',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            content: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '1. Swipe across the screen to slice fruits',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '2. Each sliced fruit gives you points',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '3. Missing fruits will cost you quarter of a life',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '4. Avoid slicing bombs or you\'ll lose instantly',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '5. The game gets faster as you progress',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it!'),
              ),
            ],
          ),
    );
  }

  void _showCreditsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              'Credits',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            content: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Fruit Ninja Flutter',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'A clone of the popular Fruit Ninja game, implemented in Flutter.',
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Developed by:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text('Purvansh Sonthalia'),
                  SizedBox(height: 20),
                  Text(
                    'Original Game:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text('Fruit Ninja by Halfbrick Studios'),
                  SizedBox(height: 20),
                  Text(
                    'This is a fan-made clone for educational purposes only.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}
