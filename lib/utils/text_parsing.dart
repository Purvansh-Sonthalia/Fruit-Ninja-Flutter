import 'package:flutter/material.dart';
import 'dart:developer';

/// Parses text and returns a list of TextSpans with @mentions styled differently.
///
/// Args:
///   text: The input text string.
///   defaultStyle: The default text style.
///   mentionStyle: The style to apply to detected @mentions.
///
/// Returns:
///   A list of TextSpan objects ready for use with RichText.
List<TextSpan> buildTextSpansWithMentions(
    String text, TextStyle defaultStyle, TextStyle mentionStyle) {
  final List<TextSpan> spans = [];

  // Regex to find @ followed by one or more word characters (alphanumeric + underscore)
  // or hyphens. This is a common pattern for usernames.
  final RegExp mentionRegex = RegExp(r'(@[\w\-]+)'); // Simpler, corrected regex

  int currentPosition = 0;

  for (final Match match in mentionRegex.allMatches(text)) {
    // Add text before the mention
    if (match.start > currentPosition) {
      spans.add(TextSpan(
        text: text.substring(currentPosition, match.start),
        style: defaultStyle,
      ));
    }

    // Add the mention with its style
    final String mention = match.group(0)!;
    // Basic check: Ensure it starts with @ and doesn't contain spaces after the @
    // (This helps filter out emails somewhat crudely)
    if (mention.startsWith('@') &&
        !mention.substring(1).contains(RegExp(r'\s'))) {
      spans.add(TextSpan(text: mention, style: mentionStyle));
      log('Styled mention: $mention');
    } else {
      // If it doesn't look like a mention we want to style, use default style
      spans.add(TextSpan(text: mention, style: defaultStyle));
      log('Did not style potential mention: $mention');
    }

    // Update current position
    currentPosition = match.end;
  }

  // Add any remaining text after the last mention
  if (currentPosition < text.length) {
    spans.add(TextSpan(
      text: text.substring(currentPosition),
      style: defaultStyle,
    ));
  }

  // Handle case where text has no mentions at all
  if (spans.isEmpty && text.isNotEmpty) {
    spans.add(TextSpan(text: text, style: defaultStyle));
  }

  return spans;
}
