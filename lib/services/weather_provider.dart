import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WeatherProvider with ChangeNotifier {
  final Location _location = Location();
  final String _apiKey = dotenv.env['OPENWEATHERMAP_API_KEY'] ?? '';

  Map<String, dynamic>? _weatherData;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastFetchTime;

  // Keys for shared preferences
  static const String _weatherDataKey = 'weather_data';
  static const String _lastFetchTimeKey = 'weather_last_fetch_time';

  WeatherProvider() {
    _loadWeatherData(); // Load data when provider is created
  }

  Map<String, dynamic>? get weatherData => _weatherData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastFetchTime => _lastFetchTime;

  bool get hasData => _weatherData != null;
  bool get isDataStale =>
      _lastFetchTime == null ||
      DateTime.now().difference(_lastFetchTime!) > const Duration(hours: 1);

  // --- Load data from SharedPreferences ---
  Future<void> _loadWeatherData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final weatherDataString = prefs.getString(_weatherDataKey);
      final lastFetchMillis = prefs.getInt(_lastFetchTimeKey);

      if (weatherDataString != null) {
        _weatherData = json.decode(weatherDataString);
      }
      if (lastFetchMillis != null) {
        _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(lastFetchMillis);
      }
      // Notify listeners after loading potentially cached data
      notifyListeners();
    } catch (e) {
      print("Error loading weather data from cache: $e");
      // Optionally clear potentially corrupted cache
      // await _clearCache();
    }
  }

  // --- Save data to SharedPreferences ---
  Future<void> _saveWeatherData() async {
    if (_weatherData == null || _lastFetchTime == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final weatherDataString = json.encode(_weatherData);
      await prefs.setString(_weatherDataKey, weatherDataString);
      await prefs.setInt(
        _lastFetchTimeKey,
        _lastFetchTime!.millisecondsSinceEpoch,
      );
    } catch (e) {
      print("Error saving weather data to cache: $e");
    }
  }

  // --- Optional: Clear Cache ---
  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_weatherDataKey);
      await prefs.remove(_lastFetchTimeKey);
      _weatherData = null;
      _lastFetchTime = null;
      notifyListeners();
    } catch (e) {
      print("Error clearing weather cache: $e");
    }
  }

  // Fetches data only if missing or older than 1 hour (checks loaded data)
  Future<void> fetchWeatherIfNeeded() async {
    // Ensure loaded data is checked before fetching
    if (!hasData || isDataStale) {
      if (_isLoading) return;
      await _fetchWeatherDataInternal();
    } else if (!_isLoading) {
      // If data is fresh and not loading, ensure UI has latest loaded state
      // This might be redundant if _loadWeatherData already notified
      // notifyListeners();
    }
  }

  // Forces a refresh regardless of timestamp
  Future<void> refreshWeatherData() async {
    if (_isLoading) return;
    await _fetchWeatherDataInternal();
  }

  Future<void> _fetchWeatherDataInternal() async {
    if (_apiKey.isEmpty) {
      _errorMessage = "Weather API key is missing. Please check configuration.";
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    // Notify immediately that loading has started
    notifyListeners();

    try {
      // 1. Check and request location service/permission
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          throw Exception('Location services are disabled.');
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          throw Exception('Location permissions are denied.');
        }
      }

      // 2. Get current location
      LocationData locationData = await _location.getLocation();
      final lat = locationData.latitude;
      final lon = locationData.longitude;

      if (lat == null || lon == null) {
        throw Exception('Could not get location coordinates.');
      }

      // 3. Fetch weather data
      final apiUrl =
          'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$_apiKey&units=metric';
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        _weatherData = json.decode(response.body);
        _lastFetchTime = DateTime.now();
        _errorMessage = null;
        await _saveWeatherData(); // Save successful fetch to cache
      } else {
        // Keep existing data on error? Or clear?
        // For now, keep existing data and show error message
        _errorMessage =
            'Failed to load weather data: ${response.reasonPhrase} (Status code: ${response.statusCode})';
        // throw Exception(...); // Maybe don't throw, just set error message
      }
    } catch (e) {
      _errorMessage = e.toString();
      // Optionally clear cache on error?
      // await _clearCache();
    } finally {
      _isLoading = false;
      notifyListeners(); // Notify completion (success or error)
    }
  }
}
