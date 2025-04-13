import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/fruit_model.dart';
import '../utils/game_manager.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:async';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  final GameManager _gameManager = GameManager();
  List<Offset> slicePoints = [];
  late AnimationController _controller;
  bool _isLoading = true;
  // Cache for loaded Images (dart:ui Image)
  final Map<String, ui.Image> _imageCache = {};
  final Map<String, Size> _imageSizeCache = {}; // Store original image sizes
  bool _gameStarted = false; // Flag to ensure startGame is called only once per instance

  @override
  void initState() {
    super.initState();
    _initGameManager();
    _preloadImages(); // Start preloading Images
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_gameLoop);
    _controller.repeat();
  }

  Future<void> _initGameManager() async {
    setState(() {
      _isLoading = true;
    });
    // Reset game manager state before init (optional but good practice)
    // If GameManager is a singleton, ensure its state is clean before reuse.
    // _gameManager.reset(); // Assuming a reset method exists or add one if needed.
    await _gameManager.init(); // Loads high score etc.
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      // Try starting the game if screen size is already known and game hasn't started
      if (_gameManager.screenSize != Size.zero && !_gameStarted) {
        print("Starting game from _initGameManager"); // Debug log
        _gameManager.startGame(_gameManager.screenSize);
        _gameStarted = true;
      } else if (_gameManager.screenSize == Size.zero) {
          print("_initGameManager finished, waiting for screen size..."); // Debug log
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    if (size.width > 0 && size.height > 0) {
        // Update size if it changed or wasn't set initially
        if (_gameManager.screenSize != size) {
             print("Screen size determined/changed: $size"); // Debug log
             _gameManager.screenSize = size;
        }
      // Start the game if initialized, size is known, and not already started
      if (!_isLoading && !_gameStarted) {
        print("Starting game from didChangeDependencies"); // Debug log
        _gameManager.startGame(size);
        _gameStarted = true;
      }
    } else {
        print("didChangeDependencies called with invalid size: $size"); // Debug log
    }
  }

  @override
  void dispose() {
    print("Disposing GameScreen"); // Debug log
    _controller.dispose();
    // Consider if GameManager needs explicit reset/cleanup if it's a singleton
    // _gameManager.dispose(); // Call dispose if GameManager holds resources like timers
    super.dispose();
  }

  void _gameLoop() {
    if (!mounted || _isLoading || !_gameStarted) return; // Ensure game has started
    
    // Calculate time delta in seconds
    final dt = _controller.duration!.inMilliseconds / 1000.0;
    
    _gameManager.update(dt);
    
    setState(() {
      // Just trigger a rebuild to update the UI
    });
  }

  void _handlePanStart(DragStartDetails details) {
    if (!mounted) return;
    
    setState(() {
      slicePoints = [details.localPosition];
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!mounted) return;
    
    final currentPoint = details.localPosition;
    
    setState(() {
      slicePoints.add(currentPoint);
    });
    
    // Need at least two points to form a line segment
    if (slicePoints.length < 2) return;
    
    // Calculate slice direction
    final lastPoint = slicePoints[slicePoints.length - 2];
    final sliceDirection = currentPoint - lastPoint;
    
    // Only process if there's significant movement
    if (sliceDirection.distance > 1.0) {
      final segment = LineSegment(lastPoint, currentPoint);
      _gameManager.processSlice(segment, sliceDirection);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!mounted) return;
    
    // Clear slice points after a short delay
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          slicePoints.clear();
        });
      }
    });
  }

  // Helper method to render partial hearts
  Widget _buildHeartIcon(double fillAmount) {
    // Clamp fillAmount between 0 and 1 to ensure proper display
    double clampedFill = fillAmount.clamp(0.0, 1.0);
    // Convert to quarters for cleaner visual representation
    int quarters = (clampedFill * 4).floor();
    
    // Custom heart with partial fill based on quarters
    return SizedBox(
      width: 28,
      height: 30,
      child: CustomPaint(
        painter: HeartPainter(quarters: quarters),
      ),
    );
  }

  // Preload Images and store them in the state's cache
  Future<void> _preloadImages() async {
    print('Preloading images...');
    try {
      // Original loop only for base images:
      for (var type in FruitType.values) {
        final imagePath = _getFruitImagePath(type); // Get base image path
        if (!_imageCache.containsKey(imagePath)) {
          print('Loading $imagePath...');
          final ImageProvider imageProvider = AssetImage(imagePath);
          final ImageStream stream = imageProvider.resolve(const ImageConfiguration());
          final completer = Completer<void>();
          late ImageStreamListener listener;

          listener = ImageStreamListener(
            (ImageInfo imageInfo, bool synchronousCall) async {
              final ui.Image image = imageInfo.image;
              final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
              if (mounted) {
                setState(() {
                  _imageCache[imagePath] = image;
                  _imageSizeCache[imagePath] = imageSize;
                  print('Loaded $imagePath successfully: $imageSize');
                });
              }
              // Ensure listener is removed only once
              stream.removeListener(listener);
              completer.complete();
            },
            onError: (dynamic exception, StackTrace? stackTrace) {
              print('Error loading image $imagePath: $exception');
              stream.removeListener(listener);
              // Original simple error handling:
              if (!completer.isCompleted) completer.completeError(exception, stackTrace);
            },
          );

          stream.addListener(listener);
          await completer.future; // Wait for this image to load
        } else {
          print('$imagePath already cached.');
        }
      }
      print('Image preloading complete.');
    } catch (e, s) {
      print('Error preloading images: $e\n$s');
      // Handle error appropriately
    }
  }
  
  // Static helper for image paths (assuming PNG)
  static String _getFruitImagePath(FruitType type) {
    String filename;
    switch (type) {
      case FruitType.apple: filename = 'apple'; break;
      case FruitType.banana: filename = 'banana'; break;
      case FruitType.orange: filename = 'orange'; break;
      case FruitType.peach: filename = 'peach'; break;
      case FruitType.watermelon: filename = 'watermelon'; break;
      case FruitType.bomb: filename = 'bomb'; break;
      default: filename = 'apple'; // Fallback
    }
    return 'assets/images/$filename.png'; // Assuming PNG format
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
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
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Score display
            ValueListenableBuilder<int>(
              valueListenable: _gameManager.scoreNotifier,
              builder: (context, score, child) {
                return Text(
                  'Score: $score',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        blurRadius: 5.0,
                        color: Colors.black,
                        offset: Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                );
              },
            ),
            
            // Lives display with partial hearts
            ValueListenableBuilder<double>(
              valueListenable: _gameManager.livesNotifier,
              builder: (context, lives, child) {
                return Row(
                  children: List.generate(
                    3, // Always display 3 heart positions
                    (index) {
                      double fillAmount = lives - index; // How full this heart should be
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                        child: _buildHeartIcon(fillAmount),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<GameState>(
            valueListenable: _gameManager.stateNotifier,
            builder: (context, state, child) {
              if (state == GameState.playing) {
                // Show Pause button when playing
                return IconButton(
                  icon: const Icon(Icons.pause, color: Colors.white),
                  onPressed: () {
                    _gameManager.togglePause();
                  },
                );
              } else {
                // Show Leaderboard button when paused or game over
                return IconButton(
                  icon: const Icon(Icons.leaderboard, color: Colors.white),
                  onPressed: () {
                    // Navigate to Leaderboards screen
                    // No need to explicitly pause here as the state is already paused/gameOver
                    Navigator.pushNamed(context, '/leaderboards');
                  },
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF87CEEB), // Sky blue at top
                  Color(0xFF4682B4), // Steel blue at bottom
                ],
              ),
            ),
          ),
          
          // Game area with gesture detection
          GestureDetector(
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            child: CustomPaint(
              painter: GamePainter(
                fruits: _gameManager.fruits,
                slicePoints: slicePoints,
                imageCache: _imageCache, // Pass the image cache
                imageSizeCache: _imageSizeCache, // Pass the size cache
              ),
              size: Size.infinite,
            ),
          ),
          
          // Game state overlays
          ValueListenableBuilder<GameState>(
            valueListenable: _gameManager.stateNotifier,
            builder: (context, state, child) {
              if (state == GameState.menu) {
                return _buildMenuOverlay();
              } else if (state == GameState.paused) {
                return _buildPauseOverlay();
              } else if (state == GameState.gameOver) {
                return _buildGameOverOverlay();
              } else {
                return const SizedBox.shrink(); // No overlay during gameplay
              }
            },
          ),
          
          // Notification overlay
          ValueListenableBuilder<String?>(
            valueListenable: _gameManager.notificationNotifier,
            builder: (context, notification, _) {
              if (notification == null) {
                return const SizedBox.shrink();
              }
              
              Color bgColor = notification.contains('BOOM') 
                  ? Colors.red 
                  : notification.contains('Critical') 
                      ? Colors.orange 
                      : notification.contains('Low Health') 
                          ? Colors.amber 
                          : Colors.green;
              
              return Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                left: 0,
                right: 0,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 300),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: child,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: bgColor.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withOpacity(0.6),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        notification,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              blurRadius: 4,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildMenuOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'FRUIT NINJA',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    blurRadius: 10.0,
                    color: Colors.red,
                    offset: Offset(5.0, 5.0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            ValueListenableBuilder<int>(
              valueListenable: _gameManager.highScoreNotifier,
              builder: (context, highScore, child) {
                return Text(
                  'High Score: $highScore',
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.yellow,
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                _gameManager.startGame(MediaQuery.of(context).size);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: const Text(
                'PLAY',
                style: TextStyle(fontSize: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PAUSED',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                _gameManager.togglePause();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: const Text(
                'RESUME',
                style: TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // First go to menu in the game manager (for cleanup)
                _gameManager.goToMenu();
                // Then actually navigate back to the home screen
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: const Text(
                'QUIT',
                style: TextStyle(fontSize: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'GAME OVER',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.red,
                shadows: [
                  Shadow(
                    blurRadius: 10.0,
                    color: Colors.black,
                    offset: Offset(2.0, 2.0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Score: ${_gameManager.score}',
              style: const TextStyle(
                fontSize: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<int>(
              valueListenable: _gameManager.highScoreNotifier,
              builder: (context, highScore, child) {
                return Text(
                  'High Score: $highScore',
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.yellow,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            if (_gameManager.score >= _gameManager.highScore)
              Consumer<AuthService>(
                builder: (context, authService, _) {
                  if (!authService.isLoggedIn) {
                    return const Text(
                      'Login to save your high score',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  } else {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _gameManager.highScoreSavedNotifier,
                      builder: (context, isSaved, _) {
                        return Text(
                          isSaved 
                              ? 'High Score Saved to Cloud ✓' 
                              : 'Error saving high score, try again',
                          style: TextStyle(
                            fontSize: 16,
                            color: isSaved ? Colors.green : Colors.red,
                            fontStyle: FontStyle.normal,
                          ),
                        );
                      },
                    );
                  }
                },
              ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                _gameManager.startGame(MediaQuery.of(context).size);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: const Text(
                'PLAY AGAIN',
                style: TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // First go to menu in the game manager (for cleanup)
                _gameManager.goToMenu();
                // Then actually navigate back to the home screen
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: const Text(
                'MAIN MENU',
                style: TextStyle(fontSize: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for the game elements
class GamePainter extends CustomPainter {
  final List<FruitModel> fruits;
  final List<Offset> slicePoints;
  // Receive the caches from the state
  final Map<String, ui.Image> imageCache;
  final Map<String, Size> imageSizeCache;

  GamePainter({required this.fruits, required this.slicePoints, required this.imageCache, required this.imageSizeCache}); // Update constructor

  // Helper for image paths (can be removed if state version is used)
  String _getFruitImagePath(FruitType type) {
    String filename;
    switch (type) {
      case FruitType.apple: filename = 'apple'; break;
      case FruitType.banana: filename = 'banana'; break;
      case FruitType.orange: filename = 'orange'; break;
      case FruitType.peach: filename = 'peach'; break;
      case FruitType.watermelon: filename = 'watermelon'; break;
      case FruitType.bomb: filename = 'bomb'; break;
      default: filename = 'apple'; // Fallback
    }
    return 'assets/images/$filename.png'; // Assuming PNG format
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint(); // Reusable paint

    // --- Draw Fruits using Images ---
    for (var fruit in fruits) {
      final double diameter = fruit.radius * 2;
      final String imagePath = _getFruitImagePath(fruit.type);
      
      final ui.Image? image = imageCache[imagePath];
      final Size? imageSize = imageSizeCache[imagePath];

      if (image != null && imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
        final Rect srcRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
        final Rect dstRect = Rect.fromCenter(center: fruit.position, width: diameter, height: diameter);

        if (!fruit.isSliced) {
          canvas.save();
          canvas.translate(dstRect.center.dx, dstRect.center.dy);
          canvas.rotate(fruit.rotation);
          canvas.translate(-dstRect.center.dx, -dstRect.center.dy);
          canvas.drawImageRect(image, srcRect, dstRect, paint);
          canvas.restore();
        } else {
          // --- Draw Sliced Halves using Canvas Clipping --- //
          for (var half in fruit.slicedHalves) {
            final double currentFruitRotation = half.rotation; // Fruit's current rotation

            // Get base fruit image details
            final String imagePath = _getFruitImagePath(fruit.type);
            final ui.Image? image = imageCache[imagePath];
            final Size? imageSize = imageSizeCache[imagePath];
            
            if (image != null && imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
              final double diameter = fruit.radius * 2;

              // --- Calculate Net Angle --- 
              final double netAngle = half.cutAngle;

              // --- Determine Display Cut Angle (Radians, 0 or pi/2) --- //
              //int displayCutAngle;
              final normalizedAngle = (netAngle % (2 * pi) + 2 * pi) % (2 * pi);
              //const double piOver4 = pi / 4.0;
              //const double threePiOver4 = 3 * pi / 4.0;
              //const double fivePiOver4 = 5 * pi / 4.0;
              //const double sevenPiOver4 = 7 * pi / 4.0;

              // Check if angle is closer to horizontal axis (0 or pi radians)
              //if ((normalizedAngle > sevenPiOver4 || normalizedAngle <= piOver4) || 
              //    (normalizedAngle > threePiOver4 && normalizedAngle <= fivePiOver4)) {
              //  displayCutAngle = 1; // Horizontal cut
              //} else { 
              //  displayCutAngle = 0; // Vertical cut
              //}

              // Rects for drawing the full image
              final Rect fullSrcRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
              final Rect localDstRect = Rect.fromCenter(center: Offset.zero, width: diameter, height: diameter);

              canvas.save();
              // 1. Translate to the half's center
              canvas.translate(half.position.dx, half.position.dy);
              // 2. Rotate by the half's individual rotation (spin)
              canvas.rotate(currentFruitRotation);
              // 3. Rotate AGAIN by the display cut angle for final orientation
              //canvas.rotate(displayCutAngle);

              // --- 4. Define and Apply Clipping --- 
              // Define a path representing the SEMICIRCLE we want to show.
              final Path clipPath = Path();
              double startAngle;
              const double sweepAngle = pi; // Half circle


              startAngle = half.isPrimaryHalf ? normalizedAngle : normalizedAngle + pi;
              //if (displayCutAngle == 0) { // Horizontal cut requested (Cut runs Vertically)
              //  startAngle = half.isPrimaryHalf ? pi / 2 : -pi / 2; // Left half starts at 90deg, Right at -90deg
              //} else { // Vertical cut requested (Cut runs Horizontally, displayCutAngle == pi / 2)
              //  startAngle = half.isPrimaryHalf ? pi : 0; // Bottom half starts at 180deg, Top at 0deg
              //}
              
              // Add the arc segment to the path
              clipPath.arcTo(localDstRect, startAngle, sweepAngle, true);
              // Add the diameter line to close the D-shape
              clipPath.close();

              // Apply the clip IN THE CURRENT (rotated) coordinate system
              canvas.clipPath(clipPath); 
              // --- End Clipping --- 

              // 5. Draw the *ENTIRE* fruit image; clipping will hide the unwanted half
              canvas.drawImageRect(image, fullSrcRect, localDstRect, paint);

              canvas.restore(); // Restore translation and all rotations
            } else {
               // Draw placeholder if base image not loaded (shouldn't happen often here)
               final Paint placeholderPaint = Paint()..color = Colors.grey.withOpacity(0.7);
               canvas.drawCircle(half.position, fruit.radius, placeholderPaint);
               if (image == null) print('Warning: Base image $imagePath not found for sliced half.');
            }
          }
          // --- End Sliced Halves Drawing --- //
        }
      } else {
        // Draw placeholder if image not loaded yet (or failed)
        final Paint placeholderPaint = Paint()..color = Colors.grey;
        canvas.drawCircle(fruit.position, fruit.radius, placeholderPaint);
        print('Warning: Image $imagePath not found in cache during paint.');
      }
    }

    // Draw slice trail (existing code)
    if (slicePoints.length > 1) {
         final slicePaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        
        final path = Path();
        path.moveTo(slicePoints[0].dx, slicePoints[0].dy);
        for (int i = 1; i < slicePoints.length; i++) {
          path.lineTo(slicePoints[i].dx, slicePoints[i].dy);
        }
        canvas.drawPath(path, slicePaint);
        
        final glowPaint = Paint()
          ..color = Colors.blue.withOpacity(0.5)
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
        canvas.drawPath(path, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) {
    return oldDelegate.fruits != fruits ||
           oldDelegate.slicePoints != slicePoints ||
           !mapEquals(oldDelegate.imageCache, imageCache) || // Compare caches
           !mapEquals(oldDelegate.imageSizeCache, imageSizeCache);
  }
}

// Custom heart painter to show quarter hearts
class HeartPainter extends CustomPainter {
  final int quarters; // 0-4 quarters filled (0=empty, 4=full)
  
  HeartPainter({required this.quarters});
  
  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    
    // Heart shape path - adjusted to be wider
    final path = Path();
    path.moveTo(width * 0.5, height * 0.25);
    path.cubicTo(
      width * 0.15, height * 0.0, // Adjusted control point 1 to be wider
      width * -0.05, height * 0.35, // Adjusted control point 2 to be wider
      width * 0.5, height * 0.95, // End point
    );
    path.cubicTo(
      width * 1.05, height * 0.35, // Adjusted control point 1 to be wider
      width * 0.85, height * 0.0, // Adjusted control point 2 to be wider
      width * 0.5, height * 0.25, // End point
    );
    path.close();
    
    // Paint for outline
    final outlinePaint = Paint()
      ..color = Colors.red.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    // Draw outline
    canvas.drawPath(path, outlinePaint);
    
    // If there's some fill
    if (quarters > 0) {
      // Paint for filled part
      final fillPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      
      if (quarters == 4) {
        // Full heart
        canvas.drawPath(path, fillPaint);
      } else {
        // Partial heart based on quarters
        // Create the quarter paths
        final rect = path.getBounds();
        
        // Only draw the appropriate sections based on quarters
        // Custom depletion pattern:
        // 1. First damage: Top-right quarter disappears
        // 2. Second damage: Bottom-right quarter disappears
        // 3. Third damage: Bottom-left quarter disappears
        // 4. Fourth damage: Top-left quarter disappears (heart becomes empty)
        
        // Create composite path with only the quarters we want to keep
        Path visiblePath = Path();
        
        // Top-left quarter
        if (quarters >= 1) {
          Path topLeftQuarter = Path()
            ..moveTo(rect.left, rect.top)
            ..lineTo(rect.center.dx, rect.top)
            ..lineTo(rect.center.dx, rect.center.dy)
            ..lineTo(rect.left, rect.center.dy)
            ..close();
          visiblePath.addPath(topLeftQuarter, Offset.zero);
        }
        
        // Bottom-left quarter
        if (quarters >= 2) {
          Path bottomLeftQuarter = Path()
            ..moveTo(rect.left, rect.center.dy)
            ..lineTo(rect.center.dx, rect.center.dy)
            ..lineTo(rect.center.dx, rect.bottom)
            ..lineTo(rect.left, rect.bottom)
            ..close();
          visiblePath.addPath(bottomLeftQuarter, Offset.zero);
        }
        
        // Bottom-right quarter
        if (quarters >= 3) {
          Path bottomRightQuarter = Path()
            ..moveTo(rect.center.dx, rect.center.dy)
            ..lineTo(rect.right, rect.center.dy)
            ..lineTo(rect.right, rect.bottom)
            ..lineTo(rect.center.dx, rect.bottom)
            ..close();
          visiblePath.addPath(bottomRightQuarter, Offset.zero);
        }
        
        // Save canvas state
        canvas.save();
        
        // Apply the clip path to show only the heart shape
        canvas.clipPath(path);
        
        // Draw the visible parts
        canvas.drawPath(visiblePath, fillPaint);
        
        // Restore canvas state
        canvas.restore();
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant HeartPainter oldDelegate) {
    return quarters != oldDelegate.quarters;
  }
}

// --- Fruit Path Generation Functions --- [REMOVE ALL FUNCTIONS BELOW THIS LINE] 

// Path getPathForBanana(Size targetSize) { ... }
// Path getPathForApple(Size targetSize) { ... }
// Path getPathForPeach(Size targetSize) { ... }
// Path getPathForWatermelon(Size targetSize) { ... }
// Path getPathForOrange(Size targetSize) { ... }
// Path getPathForBomb(Size targetSize) { ... }
// Path getFruitPath(FruitType type, Size targetSize) { ... } 