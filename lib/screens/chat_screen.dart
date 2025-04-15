import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:developer';
import 'package:intl/intl.dart'; // For date formatting
import 'dart:io'; // For File
import 'dart:typed_data'; // For Uint8List
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'dart:convert'; // Import dart:convert for base64Encode
import 'dart:async'; // Import for Timer

import '../providers/message_provider.dart';
import '../services/auth_service.dart';
import '../models/message_model.dart';

class ChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Message? _replyingToMessage;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  Timer? _pollingTimer; // Add timer instance variable

  @override
  void initState() {
    super.initState();
    // Fetch initial messages for this specific chat
    log('[ChatScreen] Init for chat with ${widget.otherUserName} (ID: ${widget.otherUserId})');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchInitialChatMessages(); // Call the renamed initial fetch method

      // Start polling for new messages every second
      _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        // Check if the widget is still mounted before fetching
        if (mounted) {
          // Call the new incremental fetch method
          // log('[ChatScreen] Polling for new messages...'); // Less verbose logging now
           Provider.of<MessageProvider>(context, listen: false)
                .fetchNewMessagesForChat(widget.otherUserId);
        } else {
          timer.cancel(); // Cancel timer if widget is disposed mid-interval
        }
      });
    });

    // Optional: Scroll to bottom when keyboard appears/disappears
    // Consider using flutter_keyboard_visibility package for more robust handling
  }

  // Renamed for clarity: Fetches the initial full list
  Future<void> _fetchInitialChatMessages() async {
    final provider = Provider.of<MessageProvider>(context, listen: false);
    await provider.fetchMessagesForChat(widget.otherUserId);
    // Optional: Scroll to bottom after fetching
    // WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _pollingTimer?.cancel(); // Cancel the timer when the widget is disposed
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent, // Because list is reversed
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Method to set the message being replied to
  void _setReplyTo(Message message) {
    setState(() {
      _replyingToMessage = message;
    });
    // Optional: Focus the text field
    // FocusScope.of(context).requestFocus(_textFieldFocusNode); // Need to add a FocusNode
  }

  // Method to clear reply state
  void _clearReplyState() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  // Image Picker Logic
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source, imageQuality: 70); // Adjust quality as needed

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = pickedFile.name;
        });
        log('[ChatScreen] Image selected: ${pickedFile.name}');
      } else {
        log('[ChatScreen] Image picking cancelled.');
      }
    } catch (e) {
      log('[ChatScreen] Error picking image: $e');
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error picking image.'), backgroundColor: Colors.red),
          );
      }
    }
  }

  void _clearSelectedImage() {
      setState(() {
          _selectedImageBytes = null;
          _selectedImageName = null;
      });
  }

  // Implement message sending logic
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    // Allow sending only image or only text or both
    if (text.isEmpty && _selectedImageBytes == null && _replyingToMessage == null) return;

    log('[ChatScreen] Sending message: "$text" ${ _replyingToMessage != null ? "(Reply)" : ""} ${ _selectedImageBytes != null ? "(Image Attached)" : ""}');
    final provider = Provider.of<MessageProvider>(context, listen: false);

    // Prepare media payload if image is selected
    Map<String, dynamic>? mediaPayload;
    if (_selectedImageBytes != null) {
      try {
        String base64Image = base64Encode(_selectedImageBytes!); // Encode here
        mediaPayload = {
            'type': 'image',
            'name': _selectedImageName ?? 'image.jpg',
            'base64': base64Image,
        };
      } catch (e) {
          log('[ChatScreen] Error encoding image for sending: $e');
           if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Error preparing image for sending.'), backgroundColor: Colors.red),
              );
           }
           return; // Don't proceed if encoding failed
      }
    }

    final success = await provider.sendMessage(
      toUserId: widget.otherUserId,
      text: text,
      parentMessageId: _replyingToMessage?.messageId,
      media: mediaPayload, // Pass the media payload
    );

    if (success && mounted) {
      _messageController.clear();
      _clearReplyState();
      _clearSelectedImage(); // Clear selected image after sending
      _scrollToBottom();
    } else if (!success && mounted) {
      // Show error SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.getChatErrorMessage(widget.otherUserId).isNotEmpty
              ? provider.getChatErrorMessage(widget.otherUserId)
              : 'Failed to send message.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use provider to get chat-specific state
    final messageProvider = context.watch<MessageProvider>();
    final authService = context.read<AuthService>(); // Read is sufficient
    final currentUserId = authService.userId;

    // Get data for THIS chat
    final messages = messageProvider.getMessagesForChat(widget.otherUserId);
    final isLoading = messageProvider.isLoadingChat(widget.otherUserId);
    final hasError = messageProvider.chatHasError(widget.otherUserId);
    final errorMessage = messageProvider.getChatErrorMessage(widget.otherUserId);

    final appBarTextColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.otherUserName,
          style: TextStyle(color: appBarTextColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: appBarTextColor),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFF4682B4)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(), // Dismiss keyboard on tap
                child: _buildMessagesList(isLoading, hasError, errorMessage, messages, currentUserId),
              ),
            ),
            // TODO: Add Reply Preview Area
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  // Build the list of messages
  Widget _buildMessagesList(
      bool isLoading,
      bool hasError,
      String errorMessage,
      List<Message> messages,
      String? currentUserId) {
    if (isLoading && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (hasError && messages.isEmpty) { // Show error only if list is empty, otherwise show list + error?
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            'Error: $errorMessage\nCould not load messages.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }
    if (messages.isEmpty && !isLoading) {
      return const Center(
          child: Text('No messages yet. Start the conversation!', style: TextStyle(color: Colors.white)));
    }

    // Use ListView.separated for better spacing control if needed
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: EdgeInsets.only(
        top: kToolbarHeight + MediaQuery.of(context).padding.top + 10,
        bottom: 10,
        left: 10,
        right: 10,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isSentByMe = message.fromUserId == currentUserId;

        // Unique key for Dismissible
        final dismissKey = ValueKey('dismiss_${message.messageId}');
        // Unique key for GestureDetector (if needed, though not strictly necessary here)
        // final gestureKey = ValueKey('gesture_${message.messageId}');

        Widget messageItem = _buildMessageItem(message, isSentByMe);

        // Wrap with GestureDetector for long-press delete (only if sent by me)
        if (isSentByMe) {
          messageItem = GestureDetector(
            // key: gestureKey,
            onLongPress: () {
              _showDeleteConfirmation(context, message);
            },
            child: messageItem,
          );
        }

        // Wrap with Dismissible for swipe-to-reply (conditionally defined earlier)
        // ... (Conditional direction/background logic from previous step) ...
        DismissDirection direction;
        Widget? background;
        Widget? secondaryBackground;

        if (isSentByMe) {
          direction = DismissDirection.endToStart;
          background = Container(color: Colors.transparent);
          secondaryBackground = Container(
            color: Colors.blue.withOpacity(0.6),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerRight,
            child: const Icon(Icons.reply, color: Colors.white),
          );
        } else {
          direction = DismissDirection.startToEnd;
          background = Container(
            color: Colors.blue.withOpacity(0.6),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: const Icon(Icons.reply, color: Colors.white),
          );
          secondaryBackground = Container(color: Colors.transparent);
        }

        return Dismissible(
          key: dismissKey,
          direction: direction,
          confirmDismiss: (dir) async {
            _setReplyTo(message);
            return false;
          },
          background: background,
          secondaryBackground: secondaryBackground,
          child: messageItem, // Pass the potentially wrapped message item
        );
      },
    );
  }

  // Actual message bubble widget
  Widget _buildMessageItem(Message message, bool isSentByMe) {
    final alignment = isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleAlignment = isSentByMe ? Alignment.centerRight : Alignment.centerLeft;
    final color = isSentByMe ? Colors.blue[800]?.withOpacity(0.8) : Colors.green[900]?.withOpacity(0.8);
    final textColor = Colors.white;
    final timeColor = Colors.white.withOpacity(0.7);
    final DateFormat dateFormat = DateFormat('HH:mm');

    // Extract media info if present
    final bool hasImage = message.messageMedia?['type'] == 'image' && message.messageMedia?['base64'] != null;
    Uint8List? imageBytes;
    if (hasImage) {
      try {
        imageBytes = base64Decode(message.messageMedia!['base64']);
      } catch (e) {
        log('[ChatScreen] Error decoding image base64 for message ${message.messageId}', error: e);
        // Optionally display an error placeholder for this specific image
      }
    }

    Widget messageContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Display reply snippet
        if (message.parentMessageId != null)
          _buildReplyContent(message.parentMessageId!, isSentByMe),

        // Display Image if available
        if (hasImage && imageBytes != null)
          Padding(
            padding: EdgeInsets.only(
              top: message.parentMessageId != null ? 4.0 : 0.0,
              bottom: (message.messageText != null && message.messageText!.isNotEmpty) ? 6.0 : 0.0, // Add bottom padding if text follows
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: Image.memory(
                imageBytes,
                // Optional: Add width constraints or loading builders
                fit: BoxFit.contain, // Adjust fit as needed
                 errorBuilder: (context, error, stackTrace) => 
                   const Icon(Icons.broken_image, color: Colors.white60, size: 50),
              ),
            ),
          ),
          
        // Display Text if available
        if (message.messageText != null && message.messageText!.isNotEmpty)
          Padding(
            // Adjust top padding based on whether reply or image precedes it
            padding: EdgeInsets.only(top: (message.parentMessageId != null || hasImage) ? 4.0 : 0.0),
            child: Text(
              message.messageText!,
              style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
            ),
          ),

        // Timestamp
        const SizedBox(height: 5),
        Align(
           alignment: Alignment.centerRight,
           child: Text(
            dateFormat.format(message.createdAt.toLocal()),
            style: TextStyle(color: timeColor, fontSize: 11),
          ),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Align(
            alignment: bubbleAlignment,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isSentByMe ? 16 : 4),
                  bottomRight: Radius.circular(isSentByMe ? 4 : 16),
                ),
              ),
              child: messageContent,
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build the reply content using FutureBuilder
  Widget _buildReplyContent(String parentMessageId, bool isMyMessageBubble) {
    final provider = Provider.of<MessageProvider>(context, listen: false);
    final currentUserId = context.read<AuthService>().userId;

    return FutureBuilder<Message?>(
      future: provider.fetchSingleMessage(parentMessageId),
      builder: (context, snapshot) {
        Widget content;
        if (snapshot.connectionState == ConnectionState.waiting) {
          content = const SizedBox(
              height: 20, width: 20,
              child: Center(child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white54))
          );
        } else if (snapshot.hasError) {
           // Keep generic error for actual fetch errors
           content = Text(
            'Error loading reply',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, fontStyle: FontStyle.italic),
          );
        } else if (!snapshot.hasData || snapshot.data == null) {
           // Specific message for deleted/not found parent message
           content = Text(
            'Deleted message', 
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, fontStyle: FontStyle.italic),
          );
        } else {
          final parentMessage = snapshot.data!;
          final bool isParentMine = parentMessage.fromUserId == currentUserId;
          final parentAuthorName = isParentMine ? 'You' : widget.otherUserName;
          
          // Check if the parent message has image media
          final bool parentHasImage = parentMessage.messageMedia?['type'] == 'image' && parentMessage.messageMedia?['base64'] != null;
          Uint8List? parentImageBytes;
          if (parentHasImage) {
            try {
              parentImageBytes = base64Decode(parentMessage.messageMedia!['base64']);
            } catch (e) {
              log('[ChatScreen] Error decoding parent image base64 for reply preview', error: e);
            }
          }

          // Build the content Column
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parentAuthorName,
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              
              // Display image indicator if parent has image
              if (parentHasImage && parentImageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1.0), // Add slight padding if text follows
                  child: Row(
                    mainAxisSize: MainAxisSize.min, // Prevent row from taking full width
                    children: [
                      Icon(Icons.image, size: 14, color: Colors.white.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Text('Image', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                    ],
                  ),
                ),
              
              // Display text if available (and adjust padding if image is also shown)
              if (parentMessage.messageText != null && parentMessage.messageText!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: parentHasImage ? 3.0 : 0.0), // Add more padding if image is above
                  child: Text(
                    parentMessage.messageText!,
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                
              // Fallback if neither text nor image is available (unlikely for valid messages)
              if (!parentHasImage && (parentMessage.messageText == null || parentMessage.messageText!.isEmpty))
                 Text(
                  '[Original message]',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          );
        }

        // Style the reply box
        return Container(
          margin: const EdgeInsets.only(bottom: 6.0),
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(isMyMessageBubble ? 0.15 : 0.25),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: isMyMessageBubble ? Colors.blueAccent : Colors.greenAccent, width: 3)),
          ),
          child: content,
        );
      },
    );
  }

  // Build the message input area - Add Reply Preview
  Widget _buildMessageInput() {
    // Calculate bottom padding separately
    final bottomSafePadding = MediaQuery.of(context).padding.bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingToMessage != null) _buildReplyPreview(),
        // Add Image Preview Area
        if (_selectedImageBytes != null)
          _buildImagePreview(),

        // Input Row
        Container(
          padding: EdgeInsets.only(
              left: 8,
              right: 8,
              top: 8,
              // Use the calculated padding
              bottom: 8 + bottomSafePadding 
          ),
          color: Colors.black.withOpacity(0.1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Image Picker Button
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white70),
                onPressed: () => _pickImage(ImageSource.gallery), // Or show options for gallery/camera
                tooltip: 'Attach Image',
                padding: const EdgeInsets.all(10),
              ),
              // Text Field
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25.0),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25.0),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  minLines: 1,
                  maxLines: 5,
                ),
              ),
              const SizedBox(width: 8),
              // Send Button
              IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Widget to show the message being replied to
  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final bool isReplyingToSelf = _replyingToMessage!.fromUserId == context.read<AuthService>().userId;
    final replyToName = isReplyingToSelf ? 'Yourself' : widget.otherUserName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black.withOpacity(0.2),
      child: Row(
        children: [
          const Icon(Icons.reply, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $replyToName',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingToMessage!.messageText ?? '[Media]',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            onPressed: _clearReplyState,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          )
        ],
      ),
    );
  }

  // Widget to show the image preview above the input
  Widget _buildImagePreview() {
     if (_selectedImageBytes == null) return const SizedBox.shrink();
     return Container(
       padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
       color: Colors.black.withOpacity(0.2),
       child: Row(
         children: [
           ClipRRect(
             borderRadius: BorderRadius.circular(8.0),
             child: Image.memory(
               _selectedImageBytes!,
               width: 50,
               height: 50,
               fit: BoxFit.cover,
             ),
           ),
           const SizedBox(width: 10),
           Expanded(
             child: Text(
               _selectedImageName ?? 'Selected Image',
               style: const TextStyle(color: Colors.white, fontSize: 13),
               overflow: TextOverflow.ellipsis,
             ),
           ),
           IconButton(
             icon: const Icon(Icons.close, color: Colors.white70, size: 20),
             onPressed: _clearSelectedImage,
             padding: EdgeInsets.zero,
             constraints: const BoxConstraints(),
           )
         ],
       ),
     );
  }

  // Add method to show delete confirmation dialog
  void _showDeleteConfirmation(BuildContext context, Message message) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 40),
          title: const Text('Delete Message', textAlign: TextAlign.center),
          content: const Text(
            'Are you sure you want to delete this message? This action cannot be undone.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async { // Make async
                Navigator.of(dialogContext).pop(); // Close dialog first
                final provider = Provider.of<MessageProvider>(context, listen: false);
                final success = await provider.deleteMessage(message.messageId, widget.otherUserId);
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(provider.getChatErrorMessage(widget.otherUserId).isNotEmpty
                          ? provider.getChatErrorMessage(widget.otherUserId)
                          : 'Failed to delete message.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                // No success message needed, list will refresh
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
} 