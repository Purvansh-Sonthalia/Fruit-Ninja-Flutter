import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game_screen.dart';
import 'auth_screen.dart';
import '../services/auth_service.dart';
import 'package:flutter/services.dart';
import 'weather_screen.dart';
import '../services/weather_provider.dart';
import 'settings_screen.dart';
import '../utils/assets_manager.dart';
import '../services/firebase_messaging_service.dart';
import 'feed_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Preference Key from SettingsScreen
  static const String _notificationsKey = 'settings_notifications_enabled';

  @override
  void initState() {
    super.initState();
    // Ensure build is complete before accessing providers or doing heavy work
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check and sync FCM token on entering the main menu
      _checkAndSyncFcmToken();

      // Existing logic moved here
      if (mounted) { // Check if the widget is still in the tree
        context.read<WeatherProvider>().fetchWeatherIfNeeded();
        context.read<AssetsManager>().playBackgroundMusic();
      }
    });
  }

  // New method to check login/notification status and sync FCM token
  Future<void> _checkAndSyncFcmToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsEnabled = prefs.getBool(_notificationsKey) ?? false;

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      print(
        'Checking FCM sync: LoggedIn=${user != null}, NotificationsEnabled=$notificationsEnabled',
      );

      // Only sync if user is logged in AND notifications are enabled in settings
      if (user != null && notificationsEnabled) {
        final fcmService = FirebaseMessagingService();
        final fcmToken = await fcmService.getFcmToken();

        if (fcmToken != null) {
          print('Syncing FCM token on home screen for user ${user.id}');
          await supabase.from('FCM-tokens').upsert({
            'user_id': user.id,
            'fcm_token': fcmToken,
          });
        } else {
          print('Could not get FCM token for sync.');
        }
      }
    } catch (e) {
      print("Error checking/syncing FCM token on home screen: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    // Calculate a responsive icon size, ensuring it's not too small or too large
    final double iconSize = (screenWidth * 0.08).clamp(30.0, 45.0);
    // Define top padding relative to safe area
    const double edgePadding = 10.0;

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
        child: SafeArea(
          // Ensure content respects safe areas (notches, etc.)
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
                    const SizedBox(height: 20),

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
                            authService.isLoggedIn
                                ? 'LOGOUT'
                                : 'LOGIN / SIGN UP',
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
                top: edgePadding, // Use calculated padding from safe area top
                left: edgePadding, // Anchor to left safe area edge
                child: IconButton(
                  icon: Icon(
                    Icons.settings,
                    color: Colors.grey,
                    size: iconSize, // Use responsive size
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
                top: edgePadding, // Use calculated padding from safe area top
                right: edgePadding, // Keep anchored to right safe area edge
                child: IconButton(
                  icon: Icon(
                    Icons.wb_sunny,
                    color: Colors.orangeAccent,
                    size: iconSize, // Use responsive size
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
               // Feed Icon Button (Next to Weather)
              Consumer<AuthService>(
                builder: (context, authService, _) {
                  if (authService.isLoggedIn == false) {
                    return SizedBox.shrink();
                  }
                  return Positioned(
                    top: edgePadding, // Align with other top icons
                    right: edgePadding +
                        iconSize +
                        (edgePadding / 2), // Position left of weather icon
                    child: IconButton(
                      icon: Icon(
                        Icons.feed, // Using the feed icon
                        color: Colors.green[900], // Matching other icons
                        size: iconSize, // Use responsive size
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FeedScreen(),
                          ),
                        );
                      },
                      tooltip: 'Feeds', // Add a tooltip
                    ),
                  );
                },
              ),
              // --- End Icons ---
            ],
          ),
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
