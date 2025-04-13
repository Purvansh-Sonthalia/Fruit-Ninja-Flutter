import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_selection_provider.dart';
import '../models/profile_model.dart';
import 'chat_screen.dart'; // To navigate to chat
import 'dart:developer';

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({super.key});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch users when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<UserSelectionProvider>(context, listen: false).fetchUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserSelectionProvider>();
    final users = provider.users;
    final isLoading = provider.isLoading;
    final hasError = provider.hasError;
    final errorMessage = provider.errorMessage;

    final appBarTextColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Select User',
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
        child: _buildUserList(isLoading, hasError, errorMessage, users),
      ),
    );
  }

  Widget _buildUserList(
      bool isLoading, bool hasError, String errorMessage, List<Profile> users) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (hasError) {
      return Center(
          child: Text('Error: $errorMessage',
              style: const TextStyle(color: Colors.white70)));
    }
    if (users.isEmpty) {
      return const Center(
          child: Text('No other users found.',
              style: TextStyle(color: Colors.white)));
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        top: kToolbarHeight + MediaQuery.of(context).padding.top + 10,
        bottom: 20,
      ),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.teal[700],
              foregroundColor: Colors.white,
              child: Text(user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase()
                  : '?'),
            ),
            title: Text(
              user.displayName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            onTap: () {
              log('[UserSelectionScreen] Selected user: ${user.displayName} (ID: ${user.userId})');
              // Navigate to ChatScreen with the selected user
              // Use pushReplacement if you don't want this screen in the back stack
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    otherUserId: user.userId,
                    otherUserName: user.displayName,
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