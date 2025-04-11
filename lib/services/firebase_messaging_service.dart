import 'package:firebase_messaging/firebase_messaging.dart';
// For BuildContext
import 'package:shared_preferences/shared_preferences.dart';

// --- Background Message Handler ---
// Must be a top-level function (outside a class)
@pragma('vm:entry-point') // Ensures tree-shaking doesn't remove it
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, like Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  // await Firebase.initializeApp(); // Usually not needed if initialized in main

  print("Handling a background message: ${message.messageId}");
  print('Message data: ${message.data}');
  if (message.notification != null) {
    print(
      'Message also contained a notification: ${message.notification!.title}',
    );
  }
  // Here you could potentially show a *local* notification using
  // flutter_local_notifications if the background message doesn't
  // automatically trigger a system notification (data-only messages).
}

class FirebaseMessagingService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Preference Key (match SettingsScreen)
  static const String _notificationsKey = 'settings_notifications_enabled';
  static const String _fcmTopic = 'fruit_reminders'; // Topic name

  Future<void> initialize() async {
    // Request permissions (iOS and Android 13+)
    await _requestPermissions();

    // Set up message handlers
    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print(
          'Message also contained a notification: ${message.notification!.title}',
        );
        // You might want to show a local notification here too, or update UI
        // NotificationService().showLocalNotification(
        //    message.notification!.title ?? 'Notification',
        //    message.notification!.body ?? '',
        // );
      }
    });

    // Background messages (when app is not terminated)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle notification tap when app is terminated/background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Message opened app: ${message.messageId}');
      // Handle navigation or specific actions based on message data
    });

    // Check initial message if app was terminated
    final RemoteMessage? initialMessage =
        await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      print(
        'App launched from terminated state by message: ${initialMessage.messageId}',
      );
      // Handle navigation or specific actions
    }

    // Subscribe/Unsubscribe based on saved preference
    await _syncSubscriptionPreference();

    print("Firebase Messaging Service Initialized");
  }

  Future<void> _requestPermissions() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false, // Set to true for provisional authorization on iOS
      sound: true,
    );

    print('User granted push permission: ${settings.authorizationStatus}');
  }

  Future<void> _syncSubscriptionPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool notificationsEnabled =
          prefs.getBool(_notificationsKey) ?? false; // Default OFF
      if (notificationsEnabled) {
        await subscribeToReminders();
      } else {
        await unsubscribeFromReminders();
      }
    } catch (e) {
      print("Error syncing FCM subscription preference: $e");
    }
  }

  Future<void> subscribeToReminders() async {
    print("Subscribing to FCM topic: $_fcmTopic");
    await _firebaseMessaging.subscribeToTopic(_fcmTopic);
  }

  Future<void> unsubscribeFromReminders() async {
    print("Unsubscribing from FCM topic: $_fcmTopic");
    await _firebaseMessaging.unsubscribeFromTopic(_fcmTopic);
  }

  // Optional: Get FCM Token (useful for direct targeting)
  Future<String?> getFcmToken() async {
    String? token = await _firebaseMessaging.getToken();
    print("FCM Token: $token");
    return token;
  }
}
