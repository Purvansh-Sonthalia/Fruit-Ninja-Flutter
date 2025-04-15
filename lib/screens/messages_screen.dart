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
    final messageProvider = Provider.of<MessageProvider>(context, listen: false);
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
        child: const Icon(Icons.add_comment_outlined), // Or Icons.add or Icons.edit
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
    // Show loading indicator during initial fetch
    if (isLoading && summaries.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Show error message if fetch failed
    if (hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            'Error loading conversations: $errorMessage\nPull down to retry.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    // Show message if no conversations after load
    if (summaries.isEmpty && !isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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

    // Build the list view of conversation summaries using ListTile
    return ListView.builder(
      padding: EdgeInsets.only(
        top: kToolbarHeight + MediaQuery.of(context).padding.top + 10,
        bottom: 20,
      ),
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        
        // --- Date/Time Formatting Logic ---
        final DateTime now = DateTime.now();
        final DateTime today = DateTime(now.year, now.month, now.day);
        final DateTime yesterday = today.subtract(const Duration(days: 1));
        final DateTime messageTimeLocal = summary.lastMessageTimestamp.toLocal();
        final DateTime messageDate = DateTime(messageTimeLocal.year, messageTimeLocal.month, messageTimeLocal.day);

        String formattedTime;
        if (messageDate == today) {
          formattedTime = DateFormat('HH:mm').format(messageTimeLocal);
        } else if (messageDate == yesterday) {
          formattedTime = 'Yesterday';
        } else {
          // Consider locale if needed: DateFormat.yMd(Localizations.localeOf(context).toString())
          formattedTime = DateFormat('dd/MM/yyyy').format(messageTimeLocal); 
        }
        // --- End Formatting Logic ---

        // Check if the last message was sent by the current user
        final bool lastMessageIsMine = summary.lastMessageFromUserId == currentUserId;
        final String messagePrefix = lastMessageIsMine ? 'You: ' : '';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // Add some spacing
          decoration: BoxDecoration(
             color: Colors.black.withOpacity(0.15), // Slight background for each item
             borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blueGrey[700],
              foregroundColor: Colors.white,
              // Display first letter of the name
              child: Text(summary.otherUserDisplayName.isNotEmpty ? summary.otherUserDisplayName[0].toUpperCase() : '?'),
            ),
            title: Text(
              summary.otherUserDisplayName,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            subtitle: Text(
              '$messagePrefix${summary.lastMessageText}',
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              formattedTime, // Use the dynamically formatted time/date string
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
            onTap: () {
              // Navigate to the specific chat screen
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
}
