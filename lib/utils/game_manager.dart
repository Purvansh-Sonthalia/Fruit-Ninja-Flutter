import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fruit_model.dart';
import '../services/scores_service.dart';

enum GameState {
  menu,
  playing,
  paused,
  gameOver,
}

class GameManager {
  // Game state
  GameState _state = GameState.menu;
  int score = 0;
  double lives = 3.0; // Changed to double to support partial heart reduction
  int highScore = 0;
  double _difficultyMultiplier = 1.0;
  Timer? _spawnTimer;
  final List<FruitModel> fruits = [];
  final Random random = Random();
  bool isHighScoreSaved = false;
  
  // Value notifiers
  final ValueNotifier<int> scoreNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> livesNotifier = ValueNotifier<double>(3.0); // Changed to double
  final ValueNotifier<int> highScoreNotifier = ValueNotifier<int>(0);
  final ValueNotifier<GameState> stateNotifier = ValueNotifier<GameState>(GameState.menu);
  final ValueNotifier<String?> notificationNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<bool> highScoreSavedNotifier = ValueNotifier<bool>(false);
  Size screenSize = Size.zero;
  
  // Scores service
  final ScoresService _scoresService = ScoresService();
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  
  // Sound effects
  final AudioPlayer _slicePlayer = AudioPlayer();
  final AudioPlayer _bombPlayer = AudioPlayer();
  final AudioPlayer _missPlayer = AudioPlayer();
  
  // Singleton pattern
  static final GameManager _instance = GameManager._internal();
  
  factory GameManager() {
    return _instance;
  }
  
  GameManager._internal();
  
  // Check if user is logged in
  bool get isLoggedIn => _supabaseClient.auth.currentUser != null;
  
  // Initialize and load high score
  Future<void> init() async {
    // Fetch user's high score from Supabase
    highScore = await _scoresService.getUserHighScore();
    highScoreNotifier.value = highScore;
  }
  
  // Start a new game
  void startGame(Size size) {
    screenSize = size;
    score = 0;
    lives = 3.0; // Reset to full health
    _difficultyMultiplier = 1.0;
    fruits.clear();
    isHighScoreSaved = false;
    highScoreSavedNotifier.value = false;
    
    scoreNotifier.value = score;
    livesNotifier.value = lives;
    _state = GameState.playing;
    stateNotifier.value = _state;
    
    _startSpawnTimer();
  }
  
  // Pause/resume game
  void togglePause() {
    if (_state == GameState.playing) {
      _state = GameState.paused;
      _spawnTimer?.cancel();
    } else if (_state == GameState.paused) {
      _state = GameState.playing;
      _startSpawnTimer();
    }
    stateNotifier.value = _state;
  }
  
  // End the game
  Future<void> gameOver() async {
    _state = GameState.gameOver;
    stateNotifier.value = _state;
    _spawnTimer?.cancel();
    
    // Update high score if necessary
    if (score > highScore) {
      highScore = score;
      highScoreNotifier.value = highScore;
      
      // Only try to update high score if user is logged in
      if (isLoggedIn) {
        // Update high score in Supabase
        bool success = await _scoresService.updateUserHighScore(score);
        isHighScoreSaved = success;
        highScoreSavedNotifier.value = success;
        
        if (success) {
          // Show notification that high score was saved
          showNotification('New High Score Saved!');
        } else {
          // Show error notification
          showNotification('Error saving high score');
        }
      } else {
        // Reset saved state if not logged in
        isHighScoreSaved = false;
        highScoreSavedNotifier.value = false;
      }
    }
  }
  
  // Show a notification that will auto-dismiss after a few seconds
  void showNotification(String message) {
    notificationNotifier.value = message;
    
    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (notificationNotifier.value == message) {
        notificationNotifier.value = null;
      }
    });
  }
  
  // Go back to menu
  void goToMenu() {
    _state = GameState.menu;
    stateNotifier.value = _state;
    _spawnTimer?.cancel();
  }
  
  // Current game state
  GameState get state => _state;
  
  // Start spawning fruits
  void _startSpawnTimer() {
    _spawnTimer?.cancel();
    
    // Spawn time decreases (gets faster) as difficulty increases
    // Increased minimum time between fruit spawns (300 → 500ms)
    final spawnInterval = (1200 / _difficultyMultiplier).clamp(500, 1200).toInt();
    
    _spawnTimer = Timer.periodic(Duration(milliseconds: spawnInterval), (timer) {
      if (_state != GameState.playing) return;
      
      _spawnFruit();
      
      // Slower difficulty progression (0.01 → 0.005)
      _difficultyMultiplier += 0.005;
    });
  }
  
  // Spawn a new fruit
  void _spawnFruit() {
    if (screenSize.isEmpty) return;

    // Determine if this should be a bomb (10% chance)
    bool isBomb = random.nextDouble() < 0.1;
    
    // Select a random fruit type
    FruitType type = isBomb 
        ? FruitType.bomb 
        : FruitType.values[random.nextInt(FruitType.values.length - 1)]; // -1 to exclude bomb
    
    // Center-biased position - focuses more fruits toward the middle of the screen
    // Instead of uniform distribution, use a bell curve-like distribution
    double centerBias = (random.nextDouble() * 0.6) + 0.2; // Value between 0.2 and 0.8
    double startX = screenSize.width * centerBias; // More likely to be near center
    double startY = screenSize.height + 50; // Start below screen
    
    // Adjusted speed to balance lower gravity (800 vs 980)
    // Reduced from 1000 to 900 for the base speed
    // Reduced from 400 to 350 for the variable component
    double speed = 800 + random.nextDouble() * 350 * _difficultyMultiplier;
    
    // More vertical angle for higher jumps
    // Changed to -pi/4 to -3pi/4 for more vertical trajectory
    double angle = -pi / 4 - random.nextDouble() * pi / 2;
    
    // Calculate initial velocity components
    double vx = cos(angle) * speed;
    double vy = sin(angle) * speed;
    
    // Clamp horizontal velocity to keep fruits on screen longer
    // Limit how fast fruits can move horizontally
    double maxHorizontalSpeed = screenSize.width * 0.4; // 40% of screen width per second
    vx = vx.clamp(-maxHorizontalSpeed, maxHorizontalSpeed);
    
    Offset initialVelocity = Offset(vx, vy);
    
    fruits.add(FruitModel(
      position: Offset(startX, startY),
      velocity: initialVelocity,
      type: type,
      radius: type == FruitType.watermelon ? 40.0 : 30.0, // Watermelons are larger
      rotationSpeed: (random.nextDouble() * 4 - 2) * pi, // Random rotation
    ));
  }
  
  // Update game state
  void update(double dt) {
    if (_state != GameState.playing) return;
    
    List<FruitModel> fruitsToRemove = [];
    
    for (var fruit in fruits) {
      fruit.update(dt, screenSize);
      
      // Check if fruit has fallen off screen
      if (fruit.isOffScreen(screenSize)) {
        fruitsToRemove.add(fruit);
        
        // Deduct quarter of a life for missed fruits (only if not already sliced and not a bomb)
        if (!fruit.isSliced && fruit.type != FruitType.bomb) {
          _playSound('miss');
          
          double oldLives = lives;
          lives = max(0, lives - 0.25); // Deduct quarter of a heart
          livesNotifier.value = lives;
          
          // Show warning notifications based on health level
          if (lives <= 0.5 && oldLives > 0.5) {
            showNotification('⚠️ Critical Health! ⚠️');
          } else if (lives <= 1.0 && oldLives > 1.0) {
            showNotification('⚠️ Low Health! ⚠️');
          } else if (lives <= 2.0 && oldLives > 2.0) {
            showNotification('Careful! Missing fruits costs health!');
          }
          
          // Check for game over
          if (lives <= 0) {
            showNotification('Game Over - Too Many Missed Fruits!');
            gameOver();
          }
        }
      }
    }
    
    // Remove fruits that are no longer needed
    fruits.removeWhere((fruit) => fruitsToRemove.contains(fruit));
  }
  
  // Process a slice action
  void processSlice(LineSegment sliceSegment, Offset sliceDirection) {
    if (_state != GameState.playing) return;
    
    bool slicedAny = false;
    bool slicedBomb = false;
    
    for (var fruit in fruits) {
      if (!fruit.isSliced && fruit.isSlicedByLine(sliceSegment)) {
        // Slice the fruit
        fruit.slice(sliceDirection);
        
        if (fruit.type == FruitType.bomb) {
          slicedBomb = true;
          _playSound('bomb');
          // Slicing a bomb causes instant death
          lives = 0;
          livesNotifier.value = lives;
          
          // Show death message
          showNotification('💥 BOOM! Instant Death! 💥');
          
          // Delay the game over screen slightly for dramatic effect
          Future.delayed(const Duration(milliseconds: 800), () {
            gameOver();
          });
        } else {
          slicedAny = true;
          // Add score
          score += fruit.score;
          scoreNotifier.value = score;
        }
      }
    }
    
    // Play slice sound if at least one fruit was sliced
    if (slicedAny && !slicedBomb) {
      _playSound('slice');
    }
  }
  
  // Play a sound effect
  void _playSound(String soundName) {
    switch (soundName) {
      case 'slice':
        _slicePlayer.play(AssetSource('audio/slice.mp3'));
        break;
      case 'bomb':
        _bombPlayer.play(AssetSource('audio/bomb.mp3'));
        break;
      case 'miss':
        _missPlayer.play(AssetSource('audio/miss.mp3'));
        break;
    }
  }
  
  // Clean up resources
  void dispose() {
    _spawnTimer?.cancel();
    _slicePlayer.dispose();
    _bombPlayer.dispose();
    _missPlayer.dispose();
  }
} 