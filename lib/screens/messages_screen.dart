import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/message_provider.dart';
import '../models/conversation_summary_model.dart';
import '../services/auth_service.dart';
import 'dart:developer';
import 'chat_screen.dart';
import 'user_selection_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch messages/summaries when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchMessages();
    });
  }

  Future<void> _fetchMessages({bool forceRefresh = false}) async {
    final messageProvider =
        Provider.of<MessageProvider>(context, listen: false);
    // This method now fetches messages and processes them into summaries
    await messageProvider.fetchMessages(forceRefresh: forceRefresh);
  }

  @override
  Widget build(BuildContext context) {
    final messageProvider = context.watch<MessageProvider>();
    // Get AuthService and current user ID
    final authService = context.read<AuthService>();
    final currentUserId = authService.userId;

    final summaries = messageProvider.conversationSummaries;
    final isLoading = messageProvider.isLoading;
    final hasError = messageProvider.hasError;
    final errorMessage = messageProvider.errorMessage;

    final appBarTextColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Conversations',
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
        child: RefreshIndicator(
          onRefresh: () => _fetchMessages(forceRefresh: true),
          child: _buildConversationList(
            isLoading,
            hasError,
            errorMessage,
            summaries,
            currentUserId,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to user selection screen
          log('[MessagesScreen] FAB pressed - Navigating to UserSelectionScreen');
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UserSelectionScreen()),
          );
        },
        backgroundColor: Colors.orangeAccent, // Match FeedScreen FAB
        foregroundColor: Colors.white,
        child: const Icon(
            Icons.add_comment_outlined), // Or Icons.add or Icons.edit
        tooltip: 'New Conversation',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildConversationList(
    bool isLoading,
    bool hasError,
    String errorMessage,
    List<ConversationSummary> summaries,
    String? currentUserId,
  ) {
    // 1. If we have summaries (cached or fresh), display them.
    if (summaries.isNotEmpty) {
      // Optionally: Show a small non-blocking error indicator if data is stale
      // For now, just show the list.
      return ListView.builder(
        padding: EdgeInsets.only(
          top: kToolbarHeight + MediaQuery.of(context).padding.top + 10,
          bottom: 80, // Add more bottom padding to avoid FAB overlap
        ),
        itemCount: summaries.length,
        itemBuilder: (context, index) {
          final summary = summaries[index];

          // --- Date/Time Formatting Logic ---
          final DateTime now = DateTime.now();
          final DateTime today = DateTime(now.year, now.month, now.day);
          final DateTime yesterday = today.subtract(const Duration(days: 1));
          final DateTime messageTimeLocal =
              summary.lastMessageTimestamp.toLocal();
          final DateTime messageDate = DateTime(messageTimeLocal.year,
              messageTimeLocal.month, messageTimeLocal.day);

          String formattedTime;
          if (messageDate == today) {
            formattedTime = DateFormat('HH:mm').format(messageTimeLocal);
          } else if (messageDate == yesterday) {
            formattedTime = 'Yesterday';
          } else {
            formattedTime = DateFormat('dd/MM/yyyy').format(messageTimeLocal);
          }
          // --- End Formatting Logic ---

          final bool lastMessageIsMine =
              summary.lastMessageFromUserId == currentUserId;
          final String messagePrefix = lastMessageIsMine ? 'You: ' : '';

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blueGrey[700],
                foregroundColor: Colors.white,
                child: Text(summary.otherUserDisplayName.isNotEmpty
                    ? summary.otherUserDisplayName[0].toUpperCase()
                    : '?'),
              ),
              title: Text(
                summary.otherUserDisplayName,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white),
              ),
              subtitle: Text(
                '$messagePrefix${summary.lastMessageText}',
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                formattedTime,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
              onTap: () {
                log('[MessagesScreen] Navigating to chat with ${summary.otherUserDisplayName} (ID: ${summary.otherUserId})');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      otherUserId: summary.otherUserId,
                      otherUserName: summary.otherUserDisplayName,
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    }

    // 2. If summaries is empty, decide what to show based on loading/error state.
    if (isLoading) {
      // Loading indicator when summaries are empty and loading is in progress
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (hasError) {
      // Error message when summaries are empty and an error occurred
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            // Use a more specific message if possible, or the generic one
            'Error: $errorMessage\nPull down to retry.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    // Fallback: No summaries, not loading, no error -> Show "No conversations"
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(), // Allow pull-to-refresh
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        const Center(
          child: Text(
            'No conversations yet.',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      ],
    );
  }
}
