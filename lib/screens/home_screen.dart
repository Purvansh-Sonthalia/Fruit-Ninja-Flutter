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
import '../main.dart'; // Import routeObserver
import 'leaderboards_screen.dart'; // Corrected import path
import 'messages_screen.dart'; // Corrected import for MessagesScreen


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// Add RouteAware mixin
class _HomeScreenState extends State<HomeScreen> with RouteAware {
  // Preference Keys
  static const String _notificationsKey = 'settings_notifications_enabled';
  static const String _displayNameKey = 'user_display_name'; // Key for local storage

  @override
  void initState() {
    super.initState();
    // Ensure build is complete before accessing providers or doing heavy work
    WidgetsBinding.instance.addPostFrameCallback((_) async { // Make callback async
      // Early exit if not mounted
      if (!mounted) return;

      // Get services (use read inside callbacks)
      final authService = context.read<AuthService>();
      final weatherProvider = context.read<WeatherProvider>();
      final assetsManager = context.read<AssetsManager>();

      // Check and sync FCM token 
      _checkAndSyncFcmToken(); 
      // Fetch weather and play music
      weatherProvider.fetchWeatherIfNeeded();
      assetsManager.playBackgroundMusic();

      // --- New Logic: Check and Prompt for Display Name --- 
      // Moved the check logic to _checkAndPromptForDisplayName
      _checkAndPromptForDisplayName();
      // --- End New Logic ---
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to RouteObserver
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    // Unsubscribe from RouteObserver
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Called when the top route has been popped off, and this route is now visible.
  @override
  void didPopNext() {
    print("HomeScreen: didPopNext called - Re-checking display name.");
    // Re-check display name when returning to this screen
    _checkAndPromptForDisplayName();
    // Optionally, restart music if needed
    if (mounted) {
      context.read<AssetsManager>().playBackgroundMusic(); 
    }
  }

  // Extracted check logic into a separate method
  Future<void> _checkAndPromptForDisplayName() async {
    // Early exit if not mounted
    if (!mounted) return;

    final authService = context.read<AuthService>();

    if (authService.isLoggedIn) {
      final prefs = await SharedPreferences.getInstance();
      final localName = prefs.getString(_displayNameKey)?.trim() ?? '';
      String? remoteName;

      // Only check Supabase if local name is empty to save a network call
      if (localName.isEmpty) {
        remoteName = await authService.getCurrentDisplayName();
        remoteName = remoteName?.trim() ?? ''; // Ensure trimmed and non-null
        // Optional: If remote name exists but local doesn't, save it locally
        if (remoteName.isNotEmpty) {
          await prefs.setString(_displayNameKey, remoteName); 
        }
      }

      // Prompt if BOTH local and remote names are effectively empty
      if (localName.isEmpty && (remoteName == null || remoteName.isEmpty)) {
        print("User logged in but display name not set. Prompting...");
        // Ensure dialog isn't shown if context is no longer valid
        if (mounted) { 
          // Use a short delay to avoid potential build conflicts when called from didPopNext
          Future.delayed(Duration.zero, () { 
              if(mounted) _showDisplayNameDialog(context, authService);
          });
        }
      }
    }
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

                    // Set Display Name Button (Replaces How to Play)
                    Consumer<AuthService>(
                      builder: (ctx, authService, _) {
                        if (!authService.isLoggedIn) {
                          return const SizedBox.shrink(); // Hide if not logged in
                        }
                        return _buildMenuButton(
                          context,
                          'SET DISPLAY NAME',
                          Colors.orange, // Changed color
                          () => _showDisplayNameDialog(context, authService),
                        );
                      },
                    ),
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
                        edgePadding, // Increased gap (was edgePadding / 2)
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
               // Leaderboard Icon Button (Moved to top-right)
              Consumer<AuthService>(
                builder: (context, authService, _) {
                  if (authService.isLoggedIn == false) {
                    return const SizedBox.shrink(); // Hide if not logged in
                  }
                  return Positioned(
                    top: edgePadding,    // Align with other top icons
                    right: edgePadding + (iconSize + edgePadding) * 2, // Adjusted position with increased gap
                    child: IconButton(
                      icon: Icon(
                        Icons.leaderboard, // Use the leaderboard icon
                        color: Colors.yellowAccent, // Choose a suitable color
                        size: iconSize, // Use responsive size
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LeaderboardsScreen(), // Navigate to LeaderboardScreen
                          ),
                        );
                      },
                      tooltip: 'Leaderboard', // Add a tooltip
                    ),
                  );
                },
              ),
               // Message Icon Button (New, next to Leaderboard)
              Consumer<AuthService>(
                builder: (context, authService, _) {
                  if (authService.isLoggedIn == false) {
                    return const SizedBox.shrink(); // Hide if not logged in
                  }
                  return Positioned(
                    top: edgePadding,    // Align with other top icons
                    right: edgePadding + (iconSize + edgePadding) * 3, // Position left of Leaderboard icon
                    child: IconButton(
                      icon: Icon(
                        Icons.message, // Use the message icon
                        color: Colors.blue[800], // Choose a suitable dark blue color
                        size: iconSize, // Use responsive size
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MessagesScreen(), // Navigate to MessagesScreen
                          ),
                        );
                      },
                      tooltip: 'Messages', // Add a tooltip
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

  // New Dialog for Setting Display Name
  Future<void> _showDisplayNameDialog(BuildContext context, AuthService authService) async {
    final prefs = await SharedPreferences.getInstance();
    final currentName = prefs.getString(_displayNameKey) ?? ''; // Load from local storage
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false; // To prevent multiple saves

    if (!mounted) return; // Check if widget is still mounted

    showDialog(
      context: context,
      barrierDismissible: !isSaving, // Prevent dismissal while saving
      builder: (context) => StatefulBuilder( // Use StatefulBuilder for loading indicator
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Set Display Name'),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Enter your display name',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Display name cannot be empty.';
                  }
                  if (value.length > 20) { // Example length limit
                      return 'Name cannot exceed 20 characters.';
                  }
                  // Add more validation if needed (e.g., allowed characters)
                  return null;
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setDialogState(() => isSaving = true);
                          final newName = controller.text.trim();
                          String? errorMessage;
                          bool success = false;

                          try {
                            success = await authService.updateDisplayName(newName);
                            if (!success) {
                              // Check if it failed because the name was taken
                              // AuthService.updateDisplayName returns false if taken
                              errorMessage = 'Display name \'$newName\' is already taken.';
                            } else {
                              // Save to local storage on success
                              await prefs.setString(_displayNameKey, newName);
                            }
                          } catch (e) {
                            print("Caught error in dialog: $e");
                            errorMessage = 'An error occurred. Please try again.';
                          } finally {
                            setDialogState(() => isSaving = false);
                          }

                          if (!mounted) return; // Check again after async operation

                          if (success) {
                            Navigator.pop(context); // Close dialog on success
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Display name saved as \'$newName\'!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else if (errorMessage != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Colors.red,
                              ),
                            );
                            // Keep dialog open on failure
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) 
                    : const Text('Save'),
              ),
            ],
          );
        },
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
