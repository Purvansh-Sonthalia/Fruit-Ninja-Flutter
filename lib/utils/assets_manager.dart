import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fruit_model.dart';

// Preference Keys
const String _masterVolumeKey = 'settings_master_volume';
const String _bgmVolumeKey = 'settings_bgm_volume';
const String _sfxVolumeKey = 'settings_sfx_volume';

// Make it a ChangeNotifier to potentially notify listeners if needed
class AssetsManager with ChangeNotifier {
  // Singleton pattern
  static final AssetsManager _instance = AssetsManager._internal();

  factory AssetsManager() {
    return _instance;
  }

  AssetsManager._internal() {
    _loadVolumes();
    preloadAudio();
  }

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
  final AudioPlayer slicePlayer = AudioPlayer();
  final AudioPlayer missPlayer = AudioPlayer();
  final AudioPlayer bombPlayer = AudioPlayer();
  final AudioPlayer backgroundPlayer = AudioPlayer();

  // Volume state
  double _masterVolume = 1.0;
  double _bgmVolumeSetting = 1.0;
  double _sfxVolumeSetting = 1.0;

  double get effectiveBgmVolume =>
      (_masterVolume * _bgmVolumeSetting).clamp(0.0, 1.0);
  double get effectiveSfxVolume =>
      (_masterVolume * _sfxVolumeSetting).clamp(0.0, 1.0);

  // --- Volume Loading/Saving ---
  Future<void> _loadVolumes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _masterVolume = prefs.getDouble(_masterVolumeKey) ?? 1.0;
      _bgmVolumeSetting = prefs.getDouble(_bgmVolumeKey) ?? 1.0;
      _sfxVolumeSetting = prefs.getDouble(_sfxVolumeKey) ?? 1.0;
      print(
        "Volumes loaded: Master=$_masterVolume, BGM=$_bgmVolumeSetting, SFX=$_sfxVolumeSetting",
      );
      await backgroundPlayer.setVolume(effectiveBgmVolume);
    } catch (e) {
      print("Error loading volumes: $e");
    }
  }

  Future<void> _saveVolume(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (e) {
      print("Error saving volume for key '$key': $e");
    }
  }

  // --- Methods for SettingsScreen ---
  Future<void> updateMasterVolume(double volume) async {
    _masterVolume = volume.clamp(0.0, 1.0);
    await _saveVolume(_masterVolumeKey, _masterVolume);
    await backgroundPlayer.setVolume(effectiveBgmVolume);
    print("Master volume updated: $_masterVolume");
    notifyListeners();
  }

  Future<void> updateBgmVolume(double volume) async {
    _bgmVolumeSetting = volume.clamp(0.0, 1.0);
    await _saveVolume(_bgmVolumeKey, _bgmVolumeSetting);
    await backgroundPlayer.setVolume(effectiveBgmVolume);
    print(
      "BGM volume updated: $_bgmVolumeSetting (Effective: $effectiveBgmVolume)",
    );
    notifyListeners();
  }

  Future<void> updateSfxVolume(double volume) async {
    _sfxVolumeSetting = volume.clamp(0.0, 1.0);
    await _saveVolume(_sfxVolumeKey, _sfxVolumeSetting);
    print(
      "SFX volume updated: $_sfxVolumeSetting (Effective: $effectiveSfxVolume)",
    );
    notifyListeners();
  }

  // Preload audio assets (can call setSource anytime)
  Future<void> preloadAudio() async {
    slicePlayer.setReleaseMode(ReleaseMode.stop);
    missPlayer.setReleaseMode(ReleaseMode.stop);
    bombPlayer.setReleaseMode(ReleaseMode.stop);
    backgroundPlayer.setReleaseMode(ReleaseMode.loop);

    await slicePlayer.setSource(AssetSource('audio/slice.mp3'));
    await missPlayer.setSource(AssetSource('audio/miss.mp3'));
    await bombPlayer.setSource(AssetSource('audio/bomb.mp3'));
    await backgroundPlayer.setSource(AssetSource('audio/background.mp3'));
    print("Audio preloaded.");
  }

  // Play a sound effect using the correct volume
  void playSound(String soundName) {
    final vol = effectiveSfxVolume;
    print("Playing '$soundName' with volume $vol");
    switch (soundName) {
      case 'slice':
        slicePlayer.play(AssetSource('audio/slice.mp3'), volume: vol);
        break;
      case 'miss':
        missPlayer.play(AssetSource('audio/miss.mp3'), volume: vol);
        break;
      case 'bomb':
        bombPlayer.play(AssetSource('audio/bomb.mp3'), volume: vol);
        break;
    }
  }

  // Play background music using the correct volume
  void playBackgroundMusic() {
    final vol = effectiveBgmVolume;
    print("Playing BGM with volume $vol");
    backgroundPlayer.play(AssetSource('audio/background.mp3'), volume: vol);
  }

  // Stop background music
  void stopBackgroundMusic() {
    print("Stopping BGM");
    backgroundPlayer.stop();
  }

  // Clean up resources
  void dispose() {
    slicePlayer.dispose();
    missPlayer.dispose();
    bombPlayer.dispose();
    backgroundPlayer.dispose();
    super.dispose();
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
