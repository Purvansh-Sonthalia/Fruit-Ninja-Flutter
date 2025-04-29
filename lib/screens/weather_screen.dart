import 'package:flutter/material.dart';
// Remove location, http, dart:convert, flutter_dotenv imports
import 'package:provider/provider.dart'; // Add provider import
import '../services/weather_provider.dart'; // Import the provider

// Make WeatherScreen StatelessWidget
class WeatherScreen extends StatelessWidget {
  const WeatherScreen({super.key});

  // Remove state class (_WeatherScreenState)

  @override
  Widget build(BuildContext context) {
    // Use watch to listen to changes in the provider
    final weatherProvider = context.watch<WeatherProvider>();

    // Trigger fetch if needed when the screen builds
    // Use addPostFrameCallback to avoid calling setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if mounted if doing async work directly here,
      // but calling provider method is fine.
      weatherProvider.fetchWeatherIfNeeded();
    });

    // Remove const from textShadow
    final textShadow = [
      Shadow(blurRadius: 2.0, color: Colors.black26, offset: Offset(1.0, 1.0)),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Weather',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            // Call provider's refresh method on press
            onPressed: () =>
                context.read<WeatherProvider>().refreshWeatherData(),
            tooltip: 'Refresh Weather',
          ),
        ],
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
          // Use a Builder or Consumer to access provider state within the Center
          child: Center(
            child: Builder(
              builder: (context) => _buildWeatherContent(
                context,
                weatherProvider,
                textShadow,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Make _buildWeatherContent a static method
  static Widget _buildWeatherContent(
    BuildContext context,
    WeatherProvider weatherProvider,
    List<Shadow> textShadow,
  ) {
    if (weatherProvider.isLoading && !weatherProvider.hasData) {
      // Show loading only if there's no existing data
      return const CircularProgressIndicator(color: Colors.white);
    } else if (weatherProvider.errorMessage != null &&
        !weatherProvider.hasData) {
      // Show error only if there's no existing data to display
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Error: ${weatherProvider.errorMessage}', // Get error from provider
              style: TextStyle(color: Colors.white, shadows: textShadow),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              // Use provider's refresh method
              onPressed: () =>
                  context.read<WeatherProvider>().refreshWeatherData(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (weatherProvider.hasData) {
      // Data extraction now uses weatherProvider.weatherData
      final weatherData = weatherProvider.weatherData!;
      final weather = weatherData['weather'][0];
      final main = weatherData['main'];
      final wind = weatherData['wind'];

      final currentTemp = main['temp'];
      final feelsLike = main['feels_like'];
      final description = weather['description'];
      final iconCode = weather['icon'];
      final humidity = main['humidity'];
      final windSpeed = wind['speed'];
      final cityName = weatherData['name'] ?? 'Current Location';

      final capitalizedDescription = description
          .split(' ')
          .map(
            (word) =>
                word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
          )
          .join(' ');

      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // If loading in the background, show a small indicator at the top
            if (weatherProvider.isLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 10.0),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.0,
                  ),
                ),
              ),
            // Current weather display uses extracted data
            Text(
              cityName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: textShadow,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Image.network(
              'https://openweathermap.org/img/wn/$iconCode@4x.png',
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 50,
              ),
              height: 100,
              width: 100,
            ),
            Text(
              capitalizedDescription,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    shadows: textShadow,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              '${currentTemp.toStringAsFixed(1)}°C',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: textShadow,
                  ),
            ),
            Text(
              'Feels like ${feelsLike.toStringAsFixed(1)}°C',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white70,
                    shadows: textShadow,
                  ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Call static method _buildInfoColumn
                _buildInfoColumn('Humidity', '$humidity%', textShadow),
                _buildInfoColumn(
                  'Wind',
                  '${windSpeed.toStringAsFixed(1)} m/s',
                  textShadow,
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Fallback if no data, error, or loading state applies (should be rare)
      return const Text(
        'Initializing weather...',
        style: TextStyle(color: Colors.white),
      );
    }
  }

  // _buildInfoColumn is already static
  static Widget _buildInfoColumn(
    String title,
    String value,
    List<Shadow> textShadow,
  ) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16, // Example explicit style
            color: Colors.white70,
            shadows: textShadow,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 20, // Example explicit style
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: textShadow,
          ),
        ),
      ],
    );
  }
}
