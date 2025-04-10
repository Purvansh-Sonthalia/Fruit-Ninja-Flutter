import 'dart:math';
import 'package:flutter/material.dart';

enum FruitType {
  apple,
  orange,
  watermelon,
  banana,
  peach,
  bomb // Not a fruit, but we'll use it for special gameplay
}

class FruitModel {
  Offset position;
  Offset velocity;
  double radius;
  FruitType type;
  bool isSliced = false;
  double rotation = 0.0;
  double rotationSpeed;
  List<SlicedHalf> slicedHalves = [];
  
  // Images will be loaded from assets
  static const Map<FruitType, String> fruitImages = {
    FruitType.apple: 'apple',
    FruitType.orange: 'orange',
    FruitType.watermelon: 'watermelon',
    FruitType.banana: 'banana',
    FruitType.peach: 'peach',
    FruitType.bomb: 'bomb',
  };
  
  static const Map<FruitType, Color> fruitColors = {
    FruitType.apple: Colors.red,
    FruitType.orange: Colors.orange,
    FruitType.watermelon: Colors.green,
    FruitType.banana: Colors.yellow,
    FruitType.peach: Colors.pink,
    FruitType.bomb: Colors.black,
  };
  
  // Highlight colors for gradients/shading
  static const Map<FruitType, Color> fruitHighlightColors = {
    FruitType.apple: Color(0xFFFFCDD2), // Lighter red/pink
    FruitType.orange: Color(0xFFFFE0B2), // Lighter orange
    FruitType.watermelon: Color(0xFFC8E6C9), // Lighter green
    FruitType.banana: Color(0xFFFFF9C4), // Lighter yellow
    FruitType.peach: Color(0xFFF8BBD0), // Lighter pink
    FruitType.bomb: Colors.grey, // Grey highlight for bomb
  };

  // Default score values
  static const Map<FruitType, int> fruitScores = {
    FruitType.apple: 1,
    FruitType.orange: 1,
    FruitType.watermelon: 3,
    FruitType.banana: 2,
    FruitType.peach: 2,
    FruitType.bomb: -10, // Negative score for bomb
  };

  FruitModel({
    required this.position,
    required this.velocity,
    required this.type,
    this.radius = 30.0,
    this.rotationSpeed = 2.0,
  });

  // Update fruit position based on velocity and gravity
  void update(double dt, Size screenSize) {
    // Apply gravity - reduced from 980 to 800 for longer air time
    velocity = velocity + Offset(0, 800 * dt); // Reduced gravity for longer hang time
    
    // Update position
    position = position + velocity * dt;
    
    // Update rotation
    rotation += rotationSpeed * dt;
    
    // If sliced, update the sliced halves too
    if (isSliced) {
      for (var half in slicedHalves) {
        half.update(dt);
      }
    }
  }
  
  // Get fruit score
  int get score => fruitScores[type] ?? 0;
  
  // Get fruit color
  Color get color => fruitColors[type] ?? Colors.white;
  
  // Get fruit highlight color
  Color get highlightColor => fruitHighlightColors[type] ?? Colors.grey[300]!;
  
  // Get fruit image name
  String get imageName => fruitImages[type] ?? 'apple';
  
  // Handle slicing
  void slice(Offset sliceDirection) {
    if (isSliced) return;
    
    isSliced = true;
    
    // Calculate the angle of the slice for determining half orientation
    final double cutAngle = sliceDirection.direction;
    // Calculate a vector perpendicular to the slice for separation
    final perpendicular = Offset(-sliceDirection.dy, sliceDirection.dx).normalized();
    const double separationForce = 150.0; // Speed at which halves separate

    // Create two halves 
    slicedHalves.add(
      SlicedHalf(
        position: position,
        velocity: perpendicular * separationForce, // Velocity is ONLY separation
        initialRotation: rotation, 
        rotationSpeed: rotationSpeed, // Use original fruit rotation speed
        type: type,
        cutAngle: cutAngle, 
        isPrimaryHalf: true, 
      )
    );
    
    slicedHalves.add(
      SlicedHalf(
        position: position, 
        velocity: -perpendicular * separationForce, // Velocity is ONLY separation (opposite dir)
        initialRotation: rotation, 
        rotationSpeed: rotationSpeed, // Use original fruit rotation speed
        type: type,
        cutAngle: cutAngle,
        isPrimaryHalf: false,
      )
    );
  }
  
  // Check if the fruit is off-screen
  bool isOffScreen(Size screenSize) {
    // Only consider fruits off-screen if they fall below the bottom edge
    // with an additional buffer to ensure they're completely off-screen
    return position.dy > screenSize.height + radius * 3;
  }
  
  // Check if the fruit was sliced by the given line segment
  bool isSlicedByLine(LineSegment segment) {
    if (isSliced) return false; // Already sliced
    
    // Simple distance check from segment to fruit center
    return segment.distanceToPoint(position) < radius;
  }
}

// Class for half fruits after slicing
class SlicedHalf {
  Offset position;
  Offset velocity;
  double rotation;
  double rotationSpeed;
  FruitType type;
  double cutAngle; // Angle of the original cut (for drawing)
  bool isPrimaryHalf; // To distinguish which half for drawing
  double timeAlive = 0.0; // Track how long the half has existed

  SlicedHalf({
    required this.position,
    required this.velocity,
    required double initialRotation,
    required this.rotationSpeed,
    required this.type,
    required this.cutAngle,
    required this.isPrimaryHalf,
  }) : rotation = initialRotation; // Initialize rotation
  
  void update(double dt) {
    // Apply gravity and update position
    velocity = velocity + Offset(0, 800 * dt); // Use consistent gravity
    position = position + velocity * dt;
    
    // Update rotation
    rotation += rotationSpeed * dt;
    timeAlive += dt;
  }
  
  // Check if the half is off-screen or has lived too long
  bool isOffScreen(Size screenSize) {
      // Remove if below screen OR after 3 seconds to prevent lingering pieces
      return position.dy > screenSize.height + 50 || timeAlive > 3.0;
  }
}

// Helper class for Line Segment calculations
class LineSegment {
  final Offset p1;
  final Offset p2;

  LineSegment(this.p1, this.p2);

  // Basic distance from point to line segment
  double distanceToPoint(Offset point) {
    final l2 = (p1 - p2).distanceSquared;
    if (l2 == 0.0) return (point - p1).distance; // Segment is a point
    var t = ((point.dx - p1.dx) * (p2.dx - p1.dx) + (point.dy - p1.dy) * (p2.dy - p1.dy)) / l2;
    t = max(0, min(1, t)); // Clamp t to the segment
    final projection = p1 + (p2 - p1) * t;
    return (point - projection).distance;
  }
}

// Extension for normalizing vectors
extension OffsetExtension on Offset {
  Offset normalized() {
    final magnitude = distance;
    if (magnitude == 0) return Offset.zero;
    return this / magnitude;
  }
} 