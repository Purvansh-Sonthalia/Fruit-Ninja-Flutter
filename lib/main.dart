import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:fruit_ninja_flutter/screens/home_screen.dart';
import 'package:fruit_ninja_flutter/screens/leaderboards_screen.dart';
import 'package:fruit_ninja_flutter/services/auth_service.dart';
import 'package:fruit_ninja_flutter/services/weather_provider.dart';
import 'package:fruit_ninja_flutter/utils/assets_manager.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/firebase_messaging_service.dart';
import 'providers/feed_provider.dart';
import 'providers/comments_provider.dart';
import 'providers/user_selection_provider.dart';
import 'services/location_service.dart';
import 'providers/conversation_list_provider.dart';
import 'providers/chat_provider.dart';

// Create a RouteObserver instance
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> _initializeAppServices() async {
  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize FCM Service AFTER Firebase Core - Run in background, do not await
  FirebaseMessagingService().initialize(); // No await here

  // Load environment variables
  await dotenv.load();

  // Initialize Supabase
  await AuthService.initialize(
    dotenv.env['SUPABASE_URL']!,
    dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // --- Request Initial Location Permission using LocationService ---
  await LocationService().requestInitialLocationPermission();
  // --- End Location Permission Request ---

  // Set preferred orientations (portrait only)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Hide status bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeAppServices();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final authService = AuthService();
            authService.listenToAuthChanges();
            return authService;
          },
        ),
        ChangeNotifierProvider(create: (_) => WeatherProvider()),
        ChangeNotifierProvider.value(value: AssetsManager()),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
        ChangeNotifierProxyProvider<FeedProvider, CommentsProvider>(
          create: (context) => CommentsProvider(
            Provider.of<FeedProvider>(context, listen: false),
          ),
          update: (context, feedProvider, previousCommentsProvider) =>
              CommentsProvider(feedProvider),
        ),
        ChangeNotifierProvider(
          create: (context) => ConversationListProvider(
            authService: Provider.of<AuthService>(context, listen: false),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ChatProvider(
            authService: Provider.of<AuthService>(context, listen: false),
          ),
        ),
        ChangeNotifierProxyProvider<AuthService, UserSelectionProvider>(
          create: (context) => UserSelectionProvider(
            Provider.of<AuthService>(context, listen: false),
          ),
          update: (context, authService, previousUserSelectionProvider) =>
              UserSelectionProvider(authService),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Fruit Ninja',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        darkTheme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.dark,
        navigatorObservers: [routeObserver],
        home: const HomeScreen(),
        routes: {
          '/leaderboards': (context) => const LeaderboardsScreen(),
        },
      ),
    );
  }
}
