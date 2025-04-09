import 'package:flutter/material.dart';
import '../models/fruit_model.dart';
import '../utils/game_manager.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';
import 'dart:math';

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

  @override
  void initState() {
    super.initState();
    _initGameManager();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60 FPS
    )..addListener(_updateGame);
    _controller.repeat();
  }

  Future<void> _initGameManager() async {
    setState(() {
      _isLoading = true;
    });
    
    await _gameManager.init();
    
    setState(() {
      _isLoading = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    if (size.width > 0 && size.height > 0) {
      _gameManager.screenSize = size;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _gameManager.dispose();
    super.dispose();
  }

  void _updateGame() {
    if (!mounted) return;
    
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
    if (fillAmount <= 0) {
      return const Icon(
        Icons.favorite_border,
        color: Colors.red,
        size: 24,
      );
    } else if (fillAmount >= 1) {
      return const Icon(
        Icons.favorite,
        color: Colors.red,
        size: 24,
      );
    } else {
      // Partial heart (using stack with a clip)
      return Stack(
        children: [
          const Icon(
            Icons.favorite_border,
            color: Colors.red,
            size: 24,
          ),
          ClipRect(
            clipper: _HeartClipper(fillAmount: fillAmount),
            child: const Icon(
              Icons.favorite,
              color: Colors.red,
              size: 24,
            ),
          ),
        ],
      );
    }
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
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
          // Pause button
          IconButton(
            icon: ValueListenableBuilder<GameState>(
              valueListenable: _gameManager.stateNotifier,
              builder: (context, state, child) {
                return Icon(
                  state == GameState.paused ? Icons.play_arrow : Icons.pause,
                  color: Colors.white,
                );
              },
            ),
            onPressed: () {
              _gameManager.togglePause();
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
  
  GamePainter({required this.fruits, required this.slicePoints});
  
  @override
  void paint(Canvas canvas, Size size) {
    // Draw fruits
    for (var fruit in fruits) {
      if (!fruit.isSliced) {
        // Draw whole fruit
        final paint = Paint()..color = fruit.color;
        
        // Save canvas state before rotation
        canvas.save();
        
        // Translate to fruit position, rotate, and draw
        canvas.translate(fruit.position.dx, fruit.position.dy);
        canvas.rotate(fruit.rotation);
        
        // Draw the fruit (circle for now, could be replaced with image)
        canvas.drawCircle(Offset.zero, fruit.radius, paint);
        
        // Add a little highlight
        final highlightPaint = Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(Offset(-fruit.radius * 0.3, -fruit.radius * 0.3), 
                         fruit.radius * 0.6, highlightPaint);
        
        // Restore canvas state
        canvas.restore();
      } else {
        // Draw sliced halves
        for (var half in fruit.slicedHalves) {
          final paint = Paint()..color = FruitModel.fruitColors[half.type] ?? Colors.white;
          
          canvas.save();
          canvas.translate(half.position.dx, half.position.dy);
          canvas.rotate(half.rotation);
          
          // For sliced halves, draw half-circles
          final rect = Rect.fromCircle(center: Offset.zero, radius: fruit.radius);
          
          if (half.isLeftHalf) {
            // Left half
            canvas.drawPath(
              Path()
                ..addArc(rect, -pi/2, pi),
              paint,
            );
          } else {
            // Right half
            canvas.drawPath(
              Path()
                ..addArc(rect, pi/2, pi),
              paint,
            );
          }
          
          canvas.restore();
        }
      }
    }
    
    // Draw slice trail
    if (slicePoints.length > 1) {
      final slicePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      
      // Create a path from slice points
      final path = Path();
      path.moveTo(slicePoints[0].dx, slicePoints[0].dy);
      
      for (int i = 1; i < slicePoints.length; i++) {
        path.lineTo(slicePoints[i].dx, slicePoints[i].dy);
      }
      
      // Draw the slice path
      canvas.drawPath(path, slicePaint);
      
      // Add a glow effect
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
           oldDelegate.slicePoints != slicePoints;
  }
}

// Custom clipper to show partial hearts
class _HeartClipper extends CustomClipper<Rect> {
  final double fillAmount;

  _HeartClipper({required this.fillAmount});

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      0,
      0,
      size.width * fillAmount,
      size.height,
    );
  }

  @override
  bool shouldReclip(_HeartClipper oldClipper) {
    return fillAmount != oldClipper.fillAmount;
  }
} 