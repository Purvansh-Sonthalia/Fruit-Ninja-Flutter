import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

// Define the Fruit class
class Fruit {
  Offset position;
  Offset velocity;
  double radius;
  Color color;
  bool isSliced = false;

  Fruit({
    required this.position,
    required this.velocity,
    this.radius = 30.0,
    this.color = Colors.red, // Default to red
  });

  // Update fruit position based on velocity and gravity
  void update(double dt, Size screenSize) {
    // Apply gravity
    velocity = velocity + Offset(0, 980 * dt); // Simple gravity simulation
    // Update position
    position = position + velocity * dt;
  }
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  int score = 0;
  int lives = 3;
  List<Fruit> fruits = []; // List to hold fruit objects
  List<Offset> slicePoints = []; // List to hold points of the current slice
  Random random = Random();
  Size? screenSize; // Add state variable for screen size

  late AnimationController _controller;
  Timer? _spawnTimer;

  // Constants for game physics/timing
  static const double gravity = 980.0;
  static const double fruitInitialSpeedMin = 600.0;
  static const double fruitInitialSpeedMax = 900.0;
  static const double fruitSpawnIntervalSeconds = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // Aim for ~60 FPS
    )..addListener(_updateGame);
    _controller.repeat();

    // Spawning will start after the first build/layout
  }

  // Get screen size when dependencies change (safer than initState for MediaQuery)
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newScreenSize = MediaQuery.of(context).size;
    // Start spawning only if size is valid and different or not set yet
    if (newScreenSize.width > 0 && newScreenSize.height > 0 && screenSize != newScreenSize) {
       screenSize = newScreenSize;
       _startSpawning(); // Start/Restart spawning with correct size
    }
  }

  void _startSpawning() {
    // Ensure screenSize is available before starting timer
    if (screenSize == null || screenSize!.isEmpty) return;

    _spawnTimer?.cancel(); // Cancel any existing timer
    _spawnTimer = Timer.periodic(Duration(seconds: fruitSpawnIntervalSeconds.toInt()), (timer) {
      _spawnFruit();
    });
  }

  void _spawnFruit() {
    // Use the stored screen size
    if (!mounted || screenSize == null || screenSize!.isEmpty) return;

    double startX = random.nextDouble() * screenSize!.width;
    double startY = screenSize!.height + 50; // Start below screen

    double speed = fruitInitialSpeedMin + random.nextDouble() * (fruitInitialSpeedMax - fruitInitialSpeedMin);
    double angle = -pi / 4 - random.nextDouble() * pi / 2; // Angle upwards (-45 to -135 degrees)

    Offset initialVelocity = Offset(cos(angle) * speed, sin(angle) * speed);

    // Randomly choose a fruit color (simple example)
    Color fruitColor = [Colors.red, Colors.green, Colors.yellow, Colors.orange][random.nextInt(4)];

    setState(() {
      fruits.add(Fruit(
        position: Offset(startX, startY),
        velocity: initialVelocity,
        color: fruitColor,
      ));
    });
  }

  @override
  void dispose() {
    _spawnTimer?.cancel(); // Important to cancel timers
    _controller.removeListener(_updateGame);
    _controller.dispose();
    super.dispose();
  }

  void _updateGame() {
    // Use the stored screen size
    if (!mounted || screenSize == null || screenSize!.isEmpty) return;

    final double dt = _controller.duration!.inMilliseconds / 1000.0; // Time delta in seconds

    // Update fruits and remove off-screen ones
    List<Fruit> fruitsToRemove = [];
    for (var fruit in fruits) {
      fruit.update(dt, screenSize!); // Pass stored screenSize
      // Remove fruit if it falls below the screen (and wasn't sliced)
      if (fruit.position.dy > screenSize!.height + fruit.radius * 2 && !fruit.isSliced) {
         fruitsToRemove.add(fruit);
         if (lives > 0) {
            lives--;
         }
      }
      // Optionally remove sliced fruits after some time or animation
       else if (fruit.position.dy > screenSize!.height + fruit.radius * 2 && fruit.isSliced) {
           fruitsToRemove.add(fruit);
       }
    }

    // Remove fruits marked for removal
    fruits.removeWhere((fruit) => fruitsToRemove.contains(fruit));

    // Clear slice points if the pan ended recently (optional visual persistence)
    // Add more sophisticated clearing if needed

    // Check for game over
    if (lives <= 0) {
      _gameOver();
    }

    setState(() {}); // Trigger repaint
  }

  void _handleSlice(DragUpdateDetails details) {
    if (!mounted) return;
    final currentPoint = details.localPosition;
    setState(() {
        slicePoints.add(currentPoint);
    });

    // Check for intersection with fruits
    if (slicePoints.length < 2) return; // Need at least two points for a line segment

    final lastPoint = slicePoints[slicePoints.length - 2];
    final segment = LineSegment(lastPoint, currentPoint);

    for (var fruit in fruits) {
      if (!fruit.isSliced) {
        // Simple distance check from segment to fruit center
        // A more accurate check would involve line-circle intersection
        if (segment.distanceToPoint(fruit.position) < fruit.radius) {
            fruit.isSliced = true;
            score++;
            // TODO: Add slice effect (e.g., split fruit, sound)
        }
      }
    }
  }

  void _endSlice(DragEndDetails details) {
      if (!mounted) return;
      // Clear slice points after a short delay for visual effect, or immediately
      Future.delayed(const Duration(milliseconds: 200), () {
         if (mounted) { // Check again if mounted after delay
            setState(() {
               slicePoints.clear();
            });
         }
      });
  }

  void _gameOver() {
      _controller.stop();
      _spawnTimer?.cancel();
      // TODO: Show Game Over dialog or screen
      print("GAME OVER! Score: $score"); // Placeholder
      // Maybe show a dialog
      // showDialog(...);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fruit Ninja - Score: $score | Lives: $lives'),
      ),
      body: GestureDetector(
        onPanStart: (details) {
            if (!mounted) return;
            setState(() {
                slicePoints = [details.localPosition]; // Start new slice
            });
        },
        onPanUpdate: _handleSlice, // Use dedicated handler
        onPanEnd: _endSlice, // Use dedicated handler
        child: Container(
          color: Colors.lightBlueAccent[100],
          width: double.infinity,
          height: double.infinity,
          child: CustomPaint(
            painter: GamePainter(fruits: fruits, slicePoints: slicePoints), // Pass fruits and slice points
            child: Container(),
          ),
        ),
      ),
    );
  }
}

// Helper class for Line Segment calculations (optional, but cleaner)
class LineSegment {
    final Offset p1;
    final Offset p2;

    LineSegment(this.p1, this.p2);

    // Basic distance from point to line segment (simplified)
    double distanceToPoint(Offset point) {
        final l2 = (p1 - p2).distanceSquared;
        if (l2 == 0.0) return (point - p1).distance; // Segment is a point
        var t = ((point.dx - p1.dx) * (p2.dx - p1.dx) + (point.dy - p1.dy) * (p2.dy - p1.dy)) / l2;
        t = max(0, min(1, t)); // Clamp t to the segment
        final projection = p1 + (p2 - p1) * t;
        return (point - projection).distance;
    }
}

// Update GamePainter to draw fruits and slice
class GamePainter extends CustomPainter {
  final List<Fruit> fruits;
  final List<Offset> slicePoints;

  GamePainter({required this.fruits, required this.slicePoints});

  @override
  void paint(Canvas canvas, Size size) {
    final fruitPaint = Paint();
    final slicePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    // Draw Fruits
    for (var fruit in fruits) {
      if (!fruit.isSliced) {
        fruitPaint.color = fruit.color;
        canvas.drawCircle(fruit.position, fruit.radius, fruitPaint);
      } else {
        // TODO: Draw sliced fruit representation (e.g., two halves)
        // For now, just draw a smaller circle or change color
        fruitPaint.color = fruit.color.withOpacity(0.5);
        canvas.drawCircle(fruit.position, fruit.radius, fruitPaint);
      }
    }

    // Draw Slice Trail
    if (slicePoints.length > 1) {
      Path slicePath = Path();
      slicePath.moveTo(slicePoints[0].dx, slicePoints[0].dy);
      for (int i = 1; i < slicePoints.length; i++) {
        slicePath.lineTo(slicePoints[i].dx, slicePoints[i].dy);
      }
      canvas.drawPath(slicePath, slicePaint);
    }
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) {
    // Repaint if fruits or slice points change
    return oldDelegate.fruits != fruits || oldDelegate.slicePoints != slicePoints;
  }
} 