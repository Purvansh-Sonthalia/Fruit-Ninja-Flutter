import 'dart:convert'; // For jsonDecode, base64Decode
import 'dart:developer'; // For log
import 'dart:typed_data'; // For Uint8List

// Define a model for the Post data for better type safety
class Post {
  final String id;
  final String userId;
  final String textContent;
  final DateTime createdAt;
  // Store the list of image data maps
  final List<Map<String, dynamic>>? imageList;
  final bool reported;

  Post({
    required this.id,
    required this.userId,
    required this.textContent,
    required this.createdAt,
    this.imageList,
    required this.reported,
  });

 factory Post.fromJson(Map<String, dynamic> json) {
    // Ensure required fields are present and have correct types
    if (json['post_id'] == null ||
        json['user_id'] == null ||
        json['created_at'] == null ||
        json['reported'] == null) { // Check for reported
      log('Error: Missing required field in post JSON: $json');
      throw FormatException('Invalid post data received: $json');
    }

    List<Map<String, dynamic>>? parsedImageList;
    final dynamic mediaContent =
        json['media_content']; // Use dynamic type for check

    if (mediaContent != null) {
      if (mediaContent is String && mediaContent.isNotEmpty) {
        // New format: JSON string representing a list
        try {
          final decodedList = jsonDecode(mediaContent) as List<dynamic>;
          parsedImageList =
              decodedList.map((item) {
                if (item is Map<String, dynamic>) {
                  return item;
                } else {
                  log(
                    'Warning: Invalid item type in media_content list for post ${json['post_id']}: $item',
                  );
                  return <String, dynamic>{}; // Handle error: empty map
                }
              }).toList();
        } catch (e) {
          log(
            'Error decoding media_content JSON string for post ${json['post_id']}: $e',
          );
          parsedImageList = null; // Handle JSON decoding error
        }
      } else if (mediaContent is Map<String, dynamic>) {
        // Old format: Single JSON object
        // Check if the map is not empty and contains expected keys (optional but good practice)
        if (mediaContent.containsKey('image_base64') ||
            mediaContent.containsKey('image_mime_type')) {
          parsedImageList = [mediaContent]; // Wrap the single map in a list
        } else {
          log(
            'Warning: media_content map is empty or missing expected keys for post ${json['post_id']}',
          );
          parsedImageList = null;
        }
      } else {
        // Unexpected type for media_content
        log(
          'Warning: Unexpected type for media_content for post ${json['post_id']}: ${mediaContent.runtimeType}',
        );
        parsedImageList = null;
      }
    }

    return Post(
      id: json['post_id'] as String,
      userId: json['user_id'] as String,
      textContent:
          json['text_content'] as String? ?? '', // Handle null text better
      createdAt: DateTime.parse(json['created_at'] as String),
      imageList: parsedImageList, // Assign the parsed list
      reported: json['reported'] as bool, // Parse reported field
    );
  }

   Uint8List? getDecodedImageBytes(int index) {
    if (imageList != null && index >= 0 && index < imageList!.length) {
      final imageData = imageList![index];
      final base64String = imageData['image_base64'] as String?;
      if (base64String != null && base64String.isNotEmpty) {
        try {
          // Use base64Decode from dart:convert
          return base64Decode(base64String);
        } catch (e) {
          log('Error decoding base64 image at index $index for post $id: $e');
          return null;
        }
      }
    }
    return null;
  }
}
