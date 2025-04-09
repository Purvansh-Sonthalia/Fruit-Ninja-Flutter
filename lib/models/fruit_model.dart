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
    // Apply gravity
    velocity = velocity + Offset(0, 980 * dt); // Simple gravity simulation
    
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
  
  // Get fruit image name
  String get imageName => fruitImages[type] ?? 'apple';
  
  // Handle slicing
  void slice(Offset sliceDirection) {
    if (isSliced) return;
    
    isSliced = true;
    
    // Create two halves with slightly different velocities based on slice direction
    final perpendicular = Offset(-sliceDirection.dy, sliceDirection.dx).normalized();
    
    // Left/top half
    slicedHalves.add(
      SlicedHalf(
        position: position,
        velocity: velocity + perpendicular * 100,
        rotation: rotation,
        rotationSpeed: rotationSpeed * 1.5,
        isLeftHalf: true,
        type: type,
      )
    );
    
    // Right/bottom half
    slicedHalves.add(
      SlicedHalf(
        position: position,
        velocity: velocity - perpendicular * 100,
        rotation: rotation,
        rotationSpeed: rotationSpeed * 1.5,
        isLeftHalf: false,
        type: type,
      )
    );
  }
  
  // Check if the fruit is off-screen
  bool isOffScreen(Size screenSize) {
    return position.dy > screenSize.height + radius * 2;
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
  bool isLeftHalf; // Whether this is the left/top half
  FruitType type;
  
  SlicedHalf({
    required this.position,
    required this.velocity,
    required this.rotation,
    required this.rotationSpeed,
    required this.isLeftHalf,
    required this.type,
  });
  
  void update(double dt) {
    // Apply gravity and update position
    velocity = velocity + Offset(0, 980 * dt);
    position = position + velocity * dt;
    
    // Update rotation
    rotation += rotationSpeed * dt;
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