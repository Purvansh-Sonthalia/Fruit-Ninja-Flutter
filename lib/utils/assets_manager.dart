import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/fruit_model.dart';

class AssetsManager {
  // Singleton pattern
  static final AssetsManager _instance = AssetsManager._internal();
  
  factory AssetsManager() {
    return _instance;
  }
  
  AssetsManager._internal();
  
  // Image caches
  final Map<FruitType, Color> _fruitColors = {
    FruitType.apple: Colors.red,
    FruitType.banana: Colors.yellow,
    FruitType.watermelon: Colors.green,
    FruitType.peach: Colors.pink,
    FruitType.orange: Colors.orange,
    FruitType.bomb: Colors.black,
  };
  
  // Get fruit color by type
  Color getFruitColor(FruitType type) {
    return _fruitColors[type] ?? Colors.white;
  }
  
  // Audio players
  final slicePlayer = AudioPlayer();
  final missPlayer = AudioPlayer();
  final bombPlayer = AudioPlayer();
  final backgroundPlayer = AudioPlayer();
  
  // Preload audio assets
  Future<void> preloadAudio() async {
    // This would be used for caching audio files
    // We'll skip actual implementation since we don't have the audio files yet
  }
  
  // Play a sound effect
  void playSound(String soundName) {
    switch (soundName) {
      case 'slice':
        slicePlayer.play(AssetSource('audio/slice.mp3'));
        break;
      case 'miss':
        missPlayer.play(AssetSource('audio/miss.mp3'));
        break;
      case 'bomb':
        bombPlayer.play(AssetSource('audio/bomb.mp3'));
        break;
    }
  }
  
  // Play background music
  void playBackgroundMusic() {
    backgroundPlayer.play(AssetSource('audio/background.mp3'));
    backgroundPlayer.setReleaseMode(ReleaseMode.loop);
  }
  
  // Stop background music
  void stopBackgroundMusic() {
    backgroundPlayer.stop();
  }
  
  // Clean up resources
  void dispose() {
    slicePlayer.dispose();
    missPlayer.dispose();
    bombPlayer.dispose();
    backgroundPlayer.dispose();
  }
  
  // Create placeholder images for readme
  static List<String> getPlaceholderImageNames() {
    return [
      'apple.png',
      'banana.png',
      'watermelon.png',
      'peach.png',
      'orange.png',
      'bomb.png',
      'background.jpg',
      'slice.mp3',
      'miss.mp3',
      'bomb.mp3',
      'background.mp3',
    ];
  }
} 