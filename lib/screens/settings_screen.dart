import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'package:provider/provider.dart'; // Import Provider
import '../utils/assets_manager.dart'; // Import AssetsManager

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Preference Keys
  static const String _notificationsKey = 'settings_notifications_enabled';
  static const String _masterVolumeKey = 'settings_master_volume';
  static const String _bgmVolumeKey = 'settings_bgm_volume';
  static const String _sfxVolumeKey = 'settings_sfx_volume';

  // State variables with defaults (used if loading fails or first time)
  bool _notificationsEnabled = true;
  double _bgmVolume = 1.0;
  double _sfxVolume = 1.0;
  double _masterVolume = 1.0;
  bool _isLoading = true; // Flag to prevent UI flicker during initial load

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Access AssetsManager to get initial values (optional, could rely on prefs directly)
    // final audioManager = context.read<AssetsManager>(); // Cannot use context in initState
    setState(() {
      // Load values, using current state as default if key not found
      _notificationsEnabled =
          prefs.getBool(_notificationsKey) ?? _notificationsEnabled;
      _masterVolume = prefs.getDouble(_masterVolumeKey) ?? _masterVolume;
      _bgmVolume = prefs.getDouble(_bgmVolumeKey) ?? _bgmVolume;
      _sfxVolume = prefs.getDouble(_sfxVolumeKey) ?? _sfxVolume;
      _isLoading = false; // Loading finished
    });
  }

  // Helper method to build a volume slider section
  Widget _buildVolumeSlider({
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
    required List<Shadow> textShadow,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title Volume',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              shadows: textShadow,
            ),
          ),
          Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 10, // Optional: 10 steps
            label: (value * 100).toStringAsFixed(0) + '%', // Show percentage
            activeColor: Colors.orangeAccent,
            inactiveColor: Colors.white30,
            onChanged: onChanged,
            // Optional: Apply volume change immediately or on release
            // onChangeEnd: (newValue) {
            //   // TODO: Persist value and apply definitively
            // },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Access AssetsManager here if needed for initial values (alternative to prefs in initState)
    // final audioManager = context.watch<AssetsManager>();
    // You might sync the local state (_masterVolume etc.) with audioManager state here if desired

    const textShadow = [
      Shadow(blurRadius: 2.0, color: Colors.black26, offset: Offset(1.0, 1.0)),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
        child: SafeArea(
          child:
              _isLoading
                  ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ) // Show loading indicator
                  : ListView(
                    // Show settings once loaded
                    padding: const EdgeInsets.all(20.0),
                    children: [
                      SwitchListTile(
                        title: const Text(
                          'Enable Notifications',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            shadows: textShadow,
                          ),
                        ),
                        value: _notificationsEnabled,
                        onChanged: (bool value) {
                          setState(() {
                            _notificationsEnabled = value;
                          });
                          // Save notification setting (keep using _saveSetting or move to a dedicated SettingsProvider)
                          _saveNotificationSetting(
                            value,
                          ); // Assume separate save for non-audio
                          // TODO: Apply notification setting change
                        },
                        activeColor: Colors.orangeAccent, // Match theme accent
                        inactiveThumbColor: Colors.grey,
                        // Ensure secondary (track) color is visible
                        activeTrackColor: Colors.orangeAccent.withOpacity(0.5),
                        inactiveTrackColor: Colors.grey.withOpacity(0.5),
                        // Make switch text slightly dimmer maybe?
                        // secondary: Icon(Icons.notifications, color: Colors.white70),
                      ),

                      const Divider(
                        height: 30,
                        thickness: 1,
                        color: Colors.white30,
                      ),

                      // Volume Sliders - Use AudioManager to update
                      _buildVolumeSlider(
                        title: 'Master',
                        value: _masterVolume,
                        textShadow: textShadow,
                        onChanged: (newValue) {
                          setState(() {
                            _masterVolume = newValue;
                          });
                          // Call AudioManager update method
                          context.read<AssetsManager>().updateMasterVolume(
                            newValue,
                          );
                        },
                      ),
                      _buildVolumeSlider(
                        title: 'Background Music (BGM)',
                        value: _bgmVolume,
                        textShadow: textShadow,
                        onChanged: (newValue) {
                          setState(() {
                            _bgmVolume = newValue;
                          });
                          // Call AudioManager update method
                          context.read<AssetsManager>().updateBgmVolume(
                            newValue,
                          );
                        },
                      ),
                      _buildVolumeSlider(
                        title: 'Sound Effects (SFX)',
                        value: _sfxVolume,
                        textShadow: textShadow,
                        onChanged: (newValue) {
                          setState(() {
                            _sfxVolume = newValue;
                          });
                          // Call AudioManager update method
                          context.read<AssetsManager>().updateSfxVolume(
                            newValue,
                          );
                        },
                      ),
                    ],
                  ),
        ),
      ),
    );
  }

  // Keep separate save for notifications for now
  Future<void> _saveNotificationSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsKey, value);
  }
}
