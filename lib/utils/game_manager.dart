import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/fruit_model.dart';

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
  int lives = 3;
  int highScore = 0;
  double _difficultyMultiplier = 1.0;
  Timer? _spawnTimer;
  final List<FruitModel> fruits = [];
  final Random random = Random();
  final ValueNotifier<int> scoreNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> livesNotifier = ValueNotifier<int>(3);
  final ValueNotifier<GameState> stateNotifier = ValueNotifier<GameState>(GameState.menu);
  Size screenSize = Size.zero;
  
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
  
  // Start a new game
  void startGame(Size size) {
    screenSize = size;
    score = 0;
    lives = 3;
    _difficultyMultiplier = 1.0;
    fruits.clear();
    
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
  void gameOver() {
    _state = GameState.gameOver;
    stateNotifier.value = _state;
    _spawnTimer?.cancel();
    
    // Update high score if necessary
    if (score > highScore) {
      highScore = score;
    }
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
    
    // Increased base speed for higher jumps
    double speed = 800 + random.nextDouble() * 300 * _difficultyMultiplier;
    
    // More vertical angle for higher jumps
    // Original was -pi/4 to -3pi/4 (too spread out horizontally)
    // New is -pi/3 to -2pi/3 (more vertical)
    double angle = -pi / 3 - random.nextDouble() * pi / 3;
    
    Offset initialVelocity = Offset(cos(angle) * speed, sin(angle) * speed);
    
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
        
        // Removed life deduction for missed fruits
        // Only play the miss sound for feedback, but don't deduct life
        if (!fruit.isSliced && fruit.type != FruitType.bomb) {
          _playSound('miss');
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
          // Slicing a bomb costs lives
          lives = max(0, lives - 1);
          livesNotifier.value = lives;
          
          // Check for game over
          if (lives <= 0) {
            gameOver();
          }
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