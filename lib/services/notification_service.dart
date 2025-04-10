import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import 'dart:math';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin(); // Ensure this is initialized

  // Keep track if permissions have been requested this session
  bool _permissionRequestedSession = false;

  // --- Enticing Messages (Fixing Syntax) ---
  final List<Map<String, String>> _enticingMessages = [
    {
      'title': 'Slice On! 🔪',
      'body': 'Fresh fruits are flying! Can you beat your high score? 🏆',
    },
    {
      'title': 'Fruits Await! 🍉',
      'body': 'Come back and show those fruits who\'s boss! 💪',
    }, // Escaped apostrophe
    {
      'title': 'High Score Challenge! 🔥',
      'body': 'Sharpen your blade! A new challenge awaits.',
    },
    {
      'title': 'Ninja Time! 🥷',
      'body': 'Your ninja skills are needed! Slice your way to glory!',
    },
    {
      'title': 'Juicy Targets! 🍓',
      'body': 'Don\'t let those fruits escape! Play now!',
    }, // Escaped apostrophe
    {
      'title': 'Combo Time! ✨',
      'body': 'Can you get the ultimate fruit slicing combo?',
    },
    {
      'title': 'Bomb Alert! 💣',
      'body': 'Watch out for those pesky bombs! Focus is key.',
    },
    {
      'title': 'Feeling Lucky? 🍀',
      'body': 'Maybe a lucky fruit spree is waiting for you!',
    },
    {
      'title': 'Quick Reflexes? 👀',
      'body': 'Test your speed and accuracy. The fruits won\'t wait!',
    }, // Escaped apostrophe
    {
      'title': 'Break Time Fun! 🎉',
      'body': 'Take a quick break and slice some stress away!',
    },
    {
      'title': 'Daily Dose of Fun! 😄',
      'body': 'Get your daily fruit slicing fix in now!',
    },
    {
      'title': 'Watermelon Wednesday! 🍉',
      'body': 'Okay, maybe it\'s not Wednesday, but slice \'em anyway!',
    }, // Escaped apostrophes
    {
      'title': 'Banana Bonanza! 🍌',
      'body': 'Go bananas and slice everything in sight!',
    },
    {
      'title': 'Orange You Glad? 🍊',
      'body': 'Orange you glad you can play Fruit Ninja? Slice time!',
    },
    {
      'title': 'Peach Perfect! 🍑',
      'body': 'Aim for that perfect slice! Come play!',
    },
    {
      'title': 'Apple Annihilation! 🍎',
      'body': 'Annihilate those apples! Show no mercy!',
    },
    {
      'title': 'Score Booster! 🚀',
      'body': 'Boost your score! Can you reach a new personal best?',
    },
    {
      'title': 'Arcade Action! 🕹️',
      'body': 'Experience the classic arcade slicing action!',
    },
    {
      'title': 'Zen Mode? 🙏',
      'body': 'Need a calmer session? Try surviving without bombs!',
    },
    {
      'title': 'Unleash the Ninja! 💨',
      'body': 'Unleash your inner fruit ninja! Play a round!',
    }, // No comma after last item
  ];

  Future<void> initialize() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission:
              false, // Don't request on init, do it explicitly later
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
          macOS: initializationSettingsIOS,
        );

    await _notificationsPlugin.initialize(initializationSettings);
    print("Notification Service Initialized");
  }

  // Request permissions (Android 13+ and iOS/macOS)
  Future<bool> requestPermissions(BuildContext? context) async {
    if (_permissionRequestedSession) return true;

    bool? granted = false;

    // iOS/macOS specific permission request
    granted =
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;

    // Android 13+ specific permission request
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation != null) {
      // Check if permission is needed (Android 13+) before requesting
      // This might require checking the Android version, or just try requesting.
      // Let's just request - it should be a no-op on older versions.
      granted =
          await androidImplementation.requestNotificationsPermission() ?? false;
    }

    _permissionRequestedSession = true;
    print("Notification permission request result: $granted");
    return granted;
  }

  // Schedule a *single* notification for the next XX:00 or XX:30
  Future<void> scheduleEnticingNotification() async {
    // --- Pick Random Message ---
    final random = Random();
    final message = _enticingMessages[random.nextInt(_enticingMessages.length)];
    final title = message['title']!;
    final body = message['body']!;

    // --- Platform Specific Details ---
    // Provide required channel ID and name
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'fruit_ninja_reminders_01', // Channel ID - MUST be provided
          'Fruit Reminders', // Channel Name - MUST be provided
          channelDescription: 'Reminders to play Fruit Ninja',
          importance: Importance.defaultImportance, // Use default importance
          priority: Priority.defaultPriority, // Use default priority
        );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true, // Ensure notification shows alert
      presentBadge: true,
      presentSound: true,
    );
    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    // --- Calculate Next XX:00 or XX:30 ---
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate;

    if (now.minute < 30) {
      // Next slot is XX:30 of the current hour
      scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        now.hour,
        30,
      );
    } else {
      // Next slot is XX:00 of the next hour
      scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        now.hour + 1,
        0,
      );
    }

    // Ensure the scheduled time is definitely in the future
    // (Handles edge case if current time is exactly XX:00 or XX:30)
    if (!scheduledDate.isAfter(now)) {
      // If current minute is >= 30, schedule for next hour :00
      // If current minute is < 30, schedule for current hour :30
      if (now.minute >= 30) {
        scheduledDate = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          now.hour + 1,
          0,
        );
      } else {
        scheduledDate = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          now.hour,
          30,
        );
        // Check again if the calculated :30 is *still* not after now (e.g., if now is 10:30:01)
        if (!scheduledDate.isAfter(now)) {
          scheduledDate = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day,
            now.hour + 1,
            0,
          );
        }
      }
    }

    print(
      "Scheduling single notification for next half hour mark: $scheduledDate",
    );

    try {
      await _notificationsPlugin.cancel(0); // Cancel previous one
      await _notificationsPlugin.zonedSchedule(
        0, // Fixed ID
        title,
        body,
        scheduledDate,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      print(
        "Single notification scheduled successfully for ${scheduledDate.toIso8601String()}",
      );
    } catch (e) {
      print("Error scheduling single notification: $e");
    }
  }

  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    print("All scheduled notifications cancelled.");
  }
}
