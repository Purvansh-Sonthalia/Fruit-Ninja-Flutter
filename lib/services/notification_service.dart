import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import 'dart:math';

class NotificationService {
  // ... (singleton, plugin instance, permission flag) ...

  // --- Enticing Messages (Fix missing commas - Take 2) --- 
  final List<Map<String, String>> _enticingMessages = [
    {'title': 'Slice On! 🔪', 'body': 'Fresh fruits are flying! Can you beat your high score? 🏆'},
    {'title': 'Fruits Await! 🍉', 'body': 'Come back and show those fruits who's boss! 💪'},
    {'title': 'High Score Challenge! 🔥', 'body': 'Sharpen your blade! A new challenge awaits.'},
    {'title': 'Ninja Time! 🥷', 'body': 'Your ninja skills are needed! Slice your way to glory!'},
    {'title': 'Juicy Targets! 🍓', 'body': 'Don't let those fruits escape! Play now!'},
    {'title': 'Combo Time! ✨', 'body': 'Can you get the ultimate fruit slicing combo?'},
    {'title': 'Bomb Alert! 💣', 'body': 'Watch out for those pesky bombs! Focus is key.'},
    {'title': 'Feeling Lucky? 🍀', 'body': 'Maybe a lucky fruit spree is waiting for you!'},
    {'title': 'Quick Reflexes? 👀', 'body': 'Test your speed and accuracy. The fruits won't wait!'},
    {'title': 'Break Time Fun! 🎉', 'body': 'Take a quick break and slice some stress away!'},
    {'title': 'Daily Dose of Fun! 😄', 'body': 'Get your daily fruit slicing fix in now!'},
    {'title': 'Watermelon Wednesday! 🍉', 'body': 'Okay, maybe it's not Wednesday, but slice 'em anyway!'},
    {'title': 'Banana Bonanza! 🍌', 'body': 'Go bananas and slice everything in sight!'},
    {'title': 'Orange You Glad? 🍊', 'body': 'Orange you glad you can play Fruit Ninja? Slice time!'},
    {'title': 'Peach Perfect! 🍑', 'body': 'Aim for that perfect slice! Come play!'},
    {'title': 'Apple Annihilation! 🍎', 'body': 'Annihilate those apples! Show no mercy!'},
    {'title': 'Score Booster! 🚀', 'body': 'Boost your score! Can you reach a new personal best?'},
    {'title': 'Arcade Action! 🕹️', 'body': 'Experience the classic arcade slicing action!'},
    {'title': 'Zen Mode? 🙏', 'body': 'Need a calmer session? Try surviving without bombs!'},
    {'title': 'Unleash the Ninja! 💨', 'body': 'Unleash your inner fruit ninja! Play a round!'}
  ];

  // ... initialize method remains the same ...
  // ... requestPermissions method remains the same ...

  // Schedule a *single* notification for the next XX:30
  Future<void> scheduleEnticingNotification() async {
    // --- Pick Random Message ---
    final random = Random();
    final message = _enticingMessages[random.nextInt(_enticingMessages.length)];
    final title = message['title']!;
    final body = message['body']!;

    // --- Platform Specific Details (remain the same) ---
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(/*...*/);
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(/*...*/);
    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    // --- Calculate Next XX:30 --- 
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate;

    if (now.minute < 30) {
      // Schedule for XX:30 of the current hour
      scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, now.hour, 30);
    } else {
      // Schedule for XX:30 of the next hour
      scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, now.hour + 1, 30);
    }

    // Ensure the scheduled time is in the future (handles edge case around XX:30 itself)
    if (scheduledDate.isBefore(now)) {
       scheduledDate = scheduledDate.add(const Duration(hours: 1)); 
    }

    print("Scheduling single notification for: $scheduledDate");

    try {
      // Cancel any previous notification with the same ID before scheduling a new one
      await _notificationsPlugin.cancel(0); 
      
      await _notificationsPlugin.zonedSchedule(
        0, // Use a fixed ID (0) to ensure only one reminder is scheduled at a time
        title,
        body,
        scheduledDate,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // Remove matchDateTimeComponents as we are not repeating daily based on time
        // matchDateTimeComponents: DateTimeComponents.time, 
      );
      print("Single notification scheduled successfully for ${scheduledDate.toIso8601String()}");
    } catch (e) {
       print("Error scheduling single notification: $e");
    }
  }

   // ... cancelAllNotifications method remains the same ...
} 