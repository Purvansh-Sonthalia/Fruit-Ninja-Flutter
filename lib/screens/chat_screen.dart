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
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  Message? _replyingToMessage;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  Timer? _pollingTimer;
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    log('[ChatScreen] Init for chat with ${widget.otherUserName} (ID: ${widget.otherUserId})');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchInitialChatMessages();

      _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          Provider.of<MessageProvider>(context, listen: false)
              .fetchNewMessagesForChat(widget.otherUserId);
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _fetchInitialChatMessages() async {
    final provider = Provider.of<MessageProvider>(context, listen: false);
    await provider.fetchMessagesForChat(widget.otherUserId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _pollingTimer?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: 0);
    }
  }

  void _scrollToMessage(String messageId) {
    final provider = Provider.of<MessageProvider>(context, listen: false);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Original message not found in the current view.')),
        );
      }
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
  }

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
    final provider = Provider.of<MessageProvider>(context, listen: false);

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
    final messageProvider = context.watch<MessageProvider>();
    final authService = context.read<AuthService>();
    final currentUserId = authService.userId;

    final messages = messageProvider.getMessagesForChat(widget.otherUserId);
    final isLoading = messageProvider.isLoadingChat(widget.otherUserId);
    final hasError = messageProvider.chatHasError(widget.otherUserId);
    final errorMessage =
        messageProvider.getChatErrorMessage(widget.otherUserId);

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
            _buildMessageInput(),
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

  Widget _buildMessageInput() {
    final bottomSafePadding = MediaQuery.of(context).padding.bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingToMessage != null) _buildReplyPreview(),
        if (_selectedImageBytes != null) _buildImagePreview(),
        Container(
          padding: EdgeInsets.only(
              left: 8, right: 8, top: 8, bottom: 8 + bottomSafePadding),
          color: Colors.black.withOpacity(0.1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined,
                    color: Colors.white70),
                onPressed: () => _pickImage(ImageSource.gallery),
                tooltip: 'Attach Image',
                padding: const EdgeInsets.all(10),
              ),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
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

  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final bool isReplyingToSelf =
        _replyingToMessage!.fromUserId == context.read<AuthService>().userId;
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
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingToMessage!.messageText ?? '[Media]',
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
  }

  Widget _buildImagePreview() {
    if (_selectedImageBytes == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
      color: Colors.black.withOpacity(0.2),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.memory(
              _selectedImageBytes!,
              width: 160,
              height: 160,
              fit: BoxFit.cover,
            ),
          ),
          const Spacer(),
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
                    Provider.of<MessageProvider>(context, listen: false);
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
    final provider = context.read<MessageProvider>();
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
