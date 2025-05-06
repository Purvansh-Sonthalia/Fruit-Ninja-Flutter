import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:developer';
import 'package:intl/intl.dart'; // For date formatting
import 'dart:io'; // For File
import 'dart:typed_data'; // For Uint8List
import 'package:image_picker/image_picker.dart'; // Import image_picker
import 'dart:convert'; // Import dart:convert for base64Encode
import 'dart:async'; // Import for Timer
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart'; // Add import
import 'package:google_generative_ai/google_generative_ai.dart'; // Import Gemini SDK
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import dotenv
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // For markdown
import 'package:uuid/uuid.dart'; // Import Uuid
import 'package:path_provider/path_provider.dart';
import '../providers/chat_provider.dart'; // Import ChatProvider
import '../models/message_model.dart';
import '../services/auth_service.dart'; // Import AuthService
import 'package:voice_message_package/voice_message_package.dart'; // Import VoiceMessage

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
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  Message? _replyingToMessage;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  Timer? _highlightTimer;
  String? _highlightedMessageId;
  ChatProvider? _chatProviderInstance; // Store the provider instance

  // --- State for AI Enhancement ---
  bool _isEnhanceButtonEnabled = false;
  bool _isEnhancing = false;
  // --- End State for AI Enhancement ---

  @override
  void initState() {
    super.initState();
    log('[ChatScreen] Init for chat with ${widget.otherUserName} (ID: ${widget.otherUserId})');
    // Get the provider instance here
    _chatProviderInstance = Provider.of<ChatProvider>(context, listen: false);
    // Add listener for text field changes
    _messageController.addListener(_updateEnhanceButtonState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Activate chat using the stored instance (or directly if preferred)
      _chatProviderInstance?.activateChat(widget.otherUserId);
      // Provider.of<ChatProvider>(context, listen: false)
      //     .activateChat(widget.otherUserId);
    });
  }

  @override
  void dispose() {
    _messageController
        .removeListener(_updateEnhanceButtonState); // Remove listener
    _messageController.dispose();
    _highlightTimer?.cancel();
    // Deactivate chat listeners using the stored instance
    _chatProviderInstance?.inactivateChat();
    // Provider.of<ChatProvider>(context, listen: false).inactivateChat(); // Avoid this
    super.dispose();
  }

  // --- Update AI Button State ---
  void _updateEnhanceButtonState() {
    final bool canEnhance = _messageController.text.trim().isNotEmpty ||
        _selectedImageBytes != null;
    if (_isEnhanceButtonEnabled != canEnhance) {
      if (mounted) {
        setState(() {
          _isEnhanceButtonEnabled = canEnhance;
        });
      }
    }
  }
  // --- End Update AI Button State ---

  void _scrollToBottom() {
    if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: 0);
    }
  }

  void _scrollToMessage(String messageId) {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final messages = provider.getMessagesForChat(widget.otherUserId);
    final index = messages.indexWhere((msg) => msg.messageId == messageId);

    if (index != -1) {
      log('[ChatScreen] Scrolling to message index $index (ID: $messageId)');

      _highlightTimer?.cancel();
      setState(() {
        _highlightedMessageId = messageId;
      });
      _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });

      if (_itemScrollController.isAttached) {
        _itemScrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.3,
        );
      } else {
        log('[_ChatScreenState] Scroll controller not attached when trying to scroll.');
      }
    } else {
      log('[ChatScreen] Could not find message index for ID: $messageId');
      _highlightTimer?.cancel();
      setState(() {
        _highlightedMessageId = null;
      });
      // TODO: Re-enable if needed, causes context issues
      /*
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Original message not found in the current view.')),
        );
      }
      */
    }
  }

  void _setReplyTo(Message message) {
    setState(() {
      _replyingToMessage = message;
    });
  }

  void _clearReplyState() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile =
          await picker.pickImage(source: source, imageQuality: 70);

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = pickedFile.name;
        });
        _updateEnhanceButtonState(); // Update AI button state
        log('[ChatScreen] Image selected: ${pickedFile.name}');
      } else {
        log('[ChatScreen] Image picking cancelled.');
      }
    } catch (e) {
      log('[ChatScreen] Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error picking image.'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
    });
    _updateEnhanceButtonState(); // Update AI button state
  }

  // --- AI Enhancement Logic (for chat) ---
  Future<void> _enhanceChatMessageWithAI() async {
    if (_isEnhancing) return;

    setState(() {
      _isEnhancing = true;
    });

    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      log('[ChatScreen] Error: GEMINI_API_KEY not found.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('AI Enhancement is not configured.'),
              backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isEnhancing = false;
      });
      return;
    }

    final model =
        GenerativeModel(model: 'gemini-1.5-flash-latest', apiKey: apiKey);
    final textContent = _messageController.text.trim();
    final bool hasText = textContent.isNotEmpty;
    final bool hasImage = _selectedImageBytes != null;

    List<DataPart> imageParts = [];
    if (hasImage) {
      try {
        imageParts.add(DataPart('image/jpeg', _selectedImageBytes!));
        log('[ChatScreen] Prepared chat image for AI.');
      } catch (e) {
        log('[ChatScreen] Error preparing image data for AI: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Error processing image for AI.'),
                backgroundColor: Colors.red),
          );
        }
        setState(() {
          _isEnhancing = false;
        });
        return;
      }
    }

    String prompt;
    List<Content> content = [];

    // Tailor prompts for a chat context
    if (hasText && hasImage) {
      prompt =
          'Rewrite the following chat message, making it more clear, friendly, or concise, considering the attached image. Provide only the single, final enhanced text. Original message: "$textContent"';
      content = [
        Content.multi([TextPart(prompt), ...imageParts])
      ];
    } else if (hasText) {
      prompt =
          'Rewrite the following chat message to be more clear, friendly, concise, or professional (choose best fit). Provide only the single, final enhanced text. Original message: "$textContent"';
      content = [Content.text(prompt)];
    } else if (hasImage) {
      prompt =
          'Write *one* short, relevant message for the attached image, suitable for a direct chat response. Provide only the single message text.';
      content = [
        Content.multi([TextPart(prompt), ...imageParts])
      ];
    } else {
      log('[ChatScreen] Enhance AI called with no text or image.');
      setState(() {
        _isEnhancing = false;
      });
      return;
    }

    try {
      log('[ChatScreen] Sending chat request to Gemini...');
      final response = await model.generateContent(content);

      if (response.text != null) {
        log('[ChatScreen] Gemini response received: ${response.text}');
        setState(() {
          _messageController.text = response.text!;
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageController.text.length),
          );
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Message enhanced by AI!'),
                backgroundColor: Colors.green),
          );
        }
      } else {
        log('[ChatScreen] Gemini response was empty.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('AI enhancement failed: No response.'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      log('[ChatScreen] Error calling Gemini API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('AI enhancement failed: ${e.toString()}'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEnhancing = false;
        });
      }
    }
  }
  // --- End AI Enhancement Logic ---

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final Uint8List? imageBytes = _selectedImageBytes;
    final String? imageName = _selectedImageName;
    final Message? replyTo = _replyingToMessage;

    if (text.isEmpty && imageBytes == null && replyTo == null) return;

    setState(() {
      _messageController.clear();
      _clearSelectedImage();
      _clearReplyState();
    });

    log('[ChatScreen] Sending message: "$text" ${replyTo != null ? "(Reply)" : ""} ${imageBytes != null ? "(Image Attached)" : ""}');
    final provider = Provider.of<ChatProvider>(context, listen: false);

    Map<String, dynamic>? mediaPayload;
    if (imageBytes != null) {
      try {
        String base64Image = base64Encode(imageBytes);
        mediaPayload = {
          'type': 'image',
          'name': imageName ?? 'image.jpg',
          'base64': base64Image,
        };
      } catch (e) {
        log('[ChatScreen] Error encoding image for sending: $e');
        if (mounted) {
          setState(() {
            _messageController.text = text;
            _selectedImageBytes = imageBytes;
            _selectedImageName = imageName;
            _replyingToMessage = replyTo;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Error preparing image for sending.'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
    }

    final success = await provider.sendMessage(
      toUserId: widget.otherUserId,
      text: text,
      parentMessageId: replyTo?.messageId,
      media: mediaPayload,
    );

    if (success && mounted) {
      _scrollToBottom();
    } else if (!success && mounted) {
      setState(() {
        _messageController.text = text;
        _selectedImageBytes = imageBytes;
        _selectedImageName = imageName;
        _replyingToMessage = replyTo;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              provider.getChatErrorMessage(widget.otherUserId).isNotEmpty
                  ? provider.getChatErrorMessage(widget.otherUserId)
                  : 'Failed to send message.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final authService = context.read<AuthService>();
    final currentUserId = authService.userId;

    final messages = chatProvider.getMessagesForChat(widget.otherUserId);
    final isLoading = chatProvider.isLoadingChat(widget.otherUserId);
    final hasError = chatProvider.chatHasError(widget.otherUserId);
    final errorMessage = chatProvider.getChatErrorMessage(widget.otherUserId);
    final isOffline = chatProvider.isOffline;

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
                onTap: () => FocusScope.of(context).unfocus(),
                child: _buildMessagesList(
                    isLoading, hasError, errorMessage, messages, currentUserId),
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(bool isLoading, bool hasError, String errorMessage,
      List<Message> messages, String? currentUserId) {
    if (isLoading && messages.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (hasError && messages.isEmpty) {
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
          child: Text('No messages yet. Start the conversation!',
              style: TextStyle(color: Colors.white)));
    }

    return ScrollablePositionedList.separated(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      reverse: true,
      physics: const ClampingScrollPhysics(),
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
        final itemKey = ValueKey('msgItem_${message.messageId}');
        final isHighlighted = message.messageId == _highlightedMessageId;

        Widget messageItemWidget = _ChatMessageListItem(
          key: itemKey,
          message: message,
          isSentByMe: isSentByMe,
          isHighlighted: isHighlighted,
          otherUserName: widget.otherUserName,
          onReplySwipe: (msg) => _setReplyTo(msg),
          onDeleteLongPress: (ctx, msg) => _showDeleteConfirmation(ctx, msg),
          scrollToMessage: _scrollToMessage,
        );

        if (isSentByMe) {
          messageItemWidget = GestureDetector(
            onLongPress: () {
              _showDeleteConfirmation(context, message);
            },
            child: messageItemWidget,
          );
        }

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
          key: itemKey,
          direction: direction,
          confirmDismiss: (dir) async {
            _setReplyTo(message);
            return false;
          },
          background: background,
          secondaryBackground: secondaryBackground,
          child: messageItemWidget,
        );
      },
      separatorBuilder: (context, index) {
        if (index < messages.length - 1) {
          final currentMessage = messages[index];
          final previousMessage = messages[index + 1];
          final currentMsgDate = currentMessage.createdAt.toLocal();
          final prevMsgDate = previousMessage.createdAt.toLocal();

          final bool isNewDay = currentMsgDate.year != prevMsgDate.year ||
              currentMsgDate.month != prevMsgDate.month ||
              currentMsgDate.day != prevMsgDate.day;

          if (isNewDay) {
            return _DateSeparator(date: previousMessage.createdAt);
          }

          final timeDifference =
              currentMessage.createdAt.difference(previousMessage.createdAt);
          if (timeDifference.abs() > const Duration(hours: 1)) {
            return const SizedBox(height: 30.0);
          }
        }
        return const SizedBox(height: 4.0);
      },
    );
  }

  // --- Helper to build the input area ---
  Widget _buildInputArea() {
    final bool canSend = _messageController.text.trim().isNotEmpty ||
        _selectedImageBytes != null;

    return Container(
      padding: EdgeInsets.only(
        left: 8.0,
        right: 8.0,
        top: 8.0,
        bottom: MediaQuery.of(context).padding.bottom + 8.0, // Safe area
      ),
      // Revert to original background color
      color: Colors.black.withOpacity(0.1),
      // Remove the BoxShadow if it wasn't there originally
      /* decoration: BoxDecoration(
        color: Theme.of(context).cardColor, // Use theme color
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.1),
          ),
        ],
      ), */
      child: Column(
        mainAxisSize: MainAxisSize.min, // Important for Column
        children: [
          // --- Replying To Banner ---
          if (_replyingToMessage != null)
            _buildReplyBanner(_replyingToMessage!),

          // --- Selected Image Preview ---
          if (_selectedImageBytes != null)
            _buildImagePreview(_selectedImageBytes!, _selectedImageName),

          // --- Text Input Row ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // --- Original Attach Button (Gallery) ---
              if (_selectedImageBytes == null) // Only show if no image selected
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined,
                      color: Colors.white70),
                  tooltip: 'Attach Image',
                  onPressed: () => _pickImage(ImageSource.gallery),
                  padding: const EdgeInsets.all(10), // Restore padding
                ),

              // --- AI Enhance Button ---
              // Show next to attach button if no image is selected
              if (_selectedImageBytes == null)
                Tooltip(
                  message: 'Enhance with AI',
                  child: IconButton(
                    icon: _isEnhancing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white70))
                        // Use white70 for consistency with original attach button
                        : Icon(Icons.auto_awesome,
                            color: _isEnhanceButtonEnabled
                                ? Colors.white70
                                : Colors.grey.withOpacity(0.5)),
                    onPressed: _isEnhancing || !_isEnhanceButtonEnabled
                        ? null
                        : _enhanceChatMessageWithAI,
                    padding: const EdgeInsets.all(10), // Add padding
                  ),
                ),

              // --- Text Field (Revert Styling) ---
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(
                      color: Colors.white), // Original text color
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                    border: InputBorder.none,
                    filled: true, // Original filled state
                    fillColor:
                        Colors.white.withOpacity(0.1), // Original fill color
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10), // Original padding
                    // Original border style
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
                  onChanged: (_) => setState(() {}),
                ),
              ),
              // --- Send Button (Revert Styling) ---
              IconButton(
                icon: const Icon(Icons.send,
                    color: Colors.white), // Original icon color
                tooltip: 'Send',
                onPressed: canSend ? _sendMessage : null,
                // Original styling
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Helper to build image preview banner ---
  Widget _buildImagePreview(Uint8List bytes, String? name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
      child: Container(
        // Wrap in container to give background
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          children: [
            ClipRRect(
              // Clip the image preview
              borderRadius: BorderRadius.circular(4.0),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 60, maxWidth: 60),
                child: Image.memory(bytes, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name ?? 'Image selected',
                // Use a slightly more prominent style for the preview name
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // --- AI Enhance Button (for image preview) ---
            Tooltip(
              message: 'Enhance with AI',
              child: IconButton(
                icon: _isEnhancing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white70))
                    : Icon(Icons.auto_awesome,
                        color: _isEnhanceButtonEnabled
                            ? Colors.white70
                            : Colors.grey.withOpacity(0.5)),
                onPressed: _isEnhancing || !_isEnhanceButtonEnabled
                    ? null
                    : _enhanceChatMessageWithAI,
                padding: EdgeInsets.zero, // Adjust padding if needed
                constraints: const BoxConstraints(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close,
                  size: 20, color: Colors.white70), // Ensure icon color
              tooltip: 'Remove Image',
              onPressed: _clearSelectedImage,
              padding: EdgeInsets.zero, // Adjust padding
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper to build the reply banner ---
  Widget _buildReplyBanner(Message message) {
    final bool isReplyingToSelf =
        message.fromUserId == context.read<AuthService>().userId;
    final replyToName = isReplyingToSelf ? 'Yourself' : widget.otherUserName;

    // TODO: Implement or replace missing widget ReplyPreviewWidget
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
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  message.messageText ?? '[Media]',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 12),
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
    // return ReplyPreviewWidget(
    //    message: message,
    //    replyToName: replyToName,
    //    onCancelReply: _clearReplyState,
    // );
  }

  void _showDeleteConfirmation(BuildContext context, Message message) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          icon: const Icon(Icons.warning_amber_rounded,
              color: Colors.red, size: 40),
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
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final provider =
                    Provider.of<ChatProvider>(context, listen: false);
                final success = await provider.deleteMessage(
                    message.messageId, widget.otherUserId);
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(provider
                              .getChatErrorMessage(widget.otherUserId)
                              .isNotEmpty
                          ? provider.getChatErrorMessage(widget.otherUserId)
                          : 'Failed to delete message.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

class _ChatMessageListItem extends StatefulWidget {
  final Message message;
  final bool isSentByMe;
  final bool isHighlighted;
  final String otherUserName;
  final Function(Message) onReplySwipe;
  final Function(BuildContext, Message) onDeleteLongPress;
  final void Function(String messageId) scrollToMessage;

  const _ChatMessageListItem({
    required Key key,
    required this.message,
    required this.isSentByMe,
    required this.isHighlighted,
    required this.otherUserName,
    required this.onReplySwipe,
    required this.onDeleteLongPress,
    required this.scrollToMessage,
  }) : super(key: key);

  @override
  State<_ChatMessageListItem> createState() => _ChatMessageListItemState();
}

class _ChatMessageListItemState extends State<_ChatMessageListItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Widget _buildReplyContent(String parentMessageId, bool isMyMessageBubble) {
    final provider = context.read<ChatProvider>();
    final currentUserId = context.read<AuthService>().userId;

    return FutureBuilder<Message?>(
      future: provider.fetchSingleMessage(parentMessageId),
      builder: (context, snapshot) {
        Widget content;
        if (snapshot.connectionState == ConnectionState.waiting) {
          content = const SizedBox(
              height: 20,
              width: 20,
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 1, color: Colors.white54)));
        } else if (snapshot.hasError) {
          content = Text(
            'Error loading reply',
            style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
                fontStyle: FontStyle.italic),
          );
        } else if (!snapshot.hasData || snapshot.data == null) {
          content = Text(
            'Deleted message',
            style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
                fontStyle: FontStyle.italic),
          );
        } else {
          final parentMessage = snapshot.data!;
          final bool isParentMine = parentMessage.fromUserId == currentUserId;
          final parentAuthorName = isParentMine ? 'You' : widget.otherUserName;

          final bool parentHasImage =
              parentMessage.messageMedia?['type'] == 'image' &&
                  parentMessage.messageMedia?['base64'] != null;
          Uint8List? parentImageBytes;
          if (parentHasImage) {
            try {
              parentImageBytes =
                  base64Decode(parentMessage.messageMedia!['base64']);
            } catch (e) {
              log('[ChatScreen] Error decoding parent image base64 for reply preview',
                  error: e);
            }
          }

          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                parentAuthorName,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              if (parentHasImage && parentImageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image,
                          size: 14, color: Colors.white.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Text('Image',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12)),
                    ],
                  ),
                ),
              if (parentMessage.messageText != null &&
                  parentMessage.messageText!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: parentHasImage ? 3.0 : 0.0),
                  child: Text(
                    parentMessage.messageText!,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (!parentHasImage &&
                  (parentMessage.messageText == null ||
                      parentMessage.messageText!.isEmpty))
                Text(
                  '[Original message]',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          );
        }

        return GestureDetector(
          onTap: () {
            widget.scrollToMessage(parentMessageId);
            log('[_ChatMessageListItem] Tapped reply preview for parent ID: $parentMessageId');
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6.0),
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(isMyMessageBubble ? 0.15 : 0.25),
              borderRadius: BorderRadius.circular(6),
              border: Border(
                  left: BorderSide(
                      color: isMyMessageBubble
                          ? Colors.blueAccent
                          : Colors.greenAccent,
                      width: 3)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 35.0),
              child: content,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final message = widget.message;
    final isSentByMe = widget.isSentByMe;
    final isHighlighted = widget.isHighlighted;

    final alignment =
        isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleAlignment =
        isSentByMe ? Alignment.centerRight : Alignment.centerLeft;

    Color baseColor = isSentByMe
        ? Colors.blue[800]!.withOpacity(0.8)
        : Colors.green[900]!.withOpacity(0.8);

    Color highlightColor = isSentByMe
        ? Colors.lightBlue[600]!.withOpacity(0.9)
        : Colors.lightGreen[700]!.withOpacity(0.9);

    final bubbleColor = isHighlighted ? highlightColor : baseColor;

    final textColor = Colors.white;
    final timeColor = Colors.white.withOpacity(0.7);
    final DateFormat dateFormat = DateFormat('HH:mm');

    final bool hasImage = message.messageMedia?['type'] == 'image' &&
        message.messageMedia?['base64'] != null;
    Uint8List? imageBytes;
    if (hasImage) {
      try {
        imageBytes = base64Decode(message.messageMedia!['base64']);
      } catch (e) {
        log('[_ChatMessageListItemState] Error decoding image base64 for message ${message.messageId}',
            error: e);
      }
    }

    Widget messageContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.parentMessageId != null)
          _buildReplyContent(message.parentMessageId!, isSentByMe),
        if (hasImage && imageBytes != null)
          Padding(
            padding: EdgeInsets.only(
              top: message.parentMessageId != null ? 4.0 : 0.0,
              bottom: (message.messageText != null &&
                      message.messageText!.isNotEmpty)
                  ? 6.0
                  : 0.0,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: Image.memory(
                imageBytes,
                key: ValueKey('${message.messageId}_image'),
                gaplessPlayback: true,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image,
                    color: Colors.white60,
                    size: 50),
              ),
            ),
          ),
        if (message.messageText != null && message.messageText!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
                top: (message.parentMessageId != null || hasImage) ? 4.0 : 0.0),
            child: Text(
              message.messageText!,
              style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
            ),
          ),
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isSentByMe ? 16 : 4),
                  bottomRight: Radius.circular(isSentByMe ? 4 : 16),
                ),
                border: isHighlighted
                    ? Border.all(
                        color: Colors.yellowAccent.withOpacity(0.7), width: 2)
                    : null,
              ),
              child: messageContent,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final DateTime date;

  const _DateSeparator({required this.date});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCompare = DateTime(date.year, date.month, date.day);

    if (dateToCompare == today) {
      return 'Today';
    } else if (dateToCompare == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMMM d, yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Text(
          _formatDate(date.toLocal()),
          style: const TextStyle(
              color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
