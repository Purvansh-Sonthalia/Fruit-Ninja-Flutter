import 'package:flutter/foundation.dart';
import 'dart:developer';
import '../models/conversation_summary_model.dart';
import '../services/conversation_service.dart';
import '../services/auth_service.dart'; // Needed to get current user ID
import '../services/database_helper.dart'; // <-- Add import

class ConversationListProvider with ChangeNotifier {
  final ConversationService _conversationService;
  final AuthService _authService; // Inject AuthService
  final DatabaseHelper _dbHelper = DatabaseHelper.instance; // <-- Add instance

  List<ConversationSummary> _summaries = [];
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isOffline = false; // Track potential offline status

  ConversationListProvider({
    required AuthService authService,
    ConversationService? conversationService, // Allow injection for testing
  })  : _authService = authService,
        _conversationService = conversationService ?? ConversationService();

  // Getters
  List<ConversationSummary> get summaries => List.unmodifiable(_summaries);
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  bool get isOffline => _isOffline;

  // Method to load/refresh summaries
  Future<void> fetchSummaries({bool forceRefresh = false}) async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      log('[ConversationListProvider] User not logged in.');
      _setErrorState('User not logged in.');
      notifyListeners();
      return;
    }

    if (_isLoading) return;

    _isLoading = true;
    if (!forceRefresh && _summaries.isNotEmpty) {
      // If not refreshing and summaries exist, show current data while loading in background
      log('[ConversationListProvider] Loading in background...');
    } else {
      // If refreshing or initial load, clear errors and indicate loading
      _hasError = false;
      _errorMessage = '';
      _isOffline = false;
      log('[ConversationListProvider] Initial load or refresh starting...');
    }
    notifyListeners(); // Notify about loading start

    try {
      final fetchedSummaries = await _conversationService
          .getSummaries(currentUserId, forceRefresh: forceRefresh);

      _summaries = fetchedSummaries;
      _hasError = false;
      _errorMessage = '';
      _isOffline = false; // Assume online on success
      log('[ConversationListProvider] Successfully fetched ${_summaries.length} summaries.');

      // --- Add Caching Step ---
      try {
        await _dbHelper.batchUpsertConversationSummaries(_summaries);
        log('[ConversationListProvider] Successfully cached ${_summaries.length} summaries.');
      } catch (cacheError) {
        log('[ConversationListProvider] Error caching summaries: $cacheError');
        // Log the error but don't necessarily fail the whole operation
        // as the summaries were fetched successfully.
      }
      // --- End Caching Step ---
    } catch (e, stacktrace) {
      log('[ConversationListProvider] Error fetching summaries: $e',
          error: e, stackTrace: stacktrace);
      _setErrorState('Failed to load conversations. $e');
      _isOffline = true; // Mark as offline on error
      // Keep existing _summaries if available (cache fallback handled by service)
    } finally {
      _isLoading = false;
      notifyListeners(); // Notify about loading end and potential data/error changes
    }
  }

  void _setErrorState(String message) {
    _hasError = true;
    _errorMessage = message;
    // Don't modify loading state here, finally block handles it
  }

  // Optional: Method to clear state on logout
  void clearState() {
    _summaries = [];
    _isLoading = false;
    _hasError = false;
    _errorMessage = '';
    _isOffline = false;
    notifyListeners();
    // Maybe call service cache clear?
    // _conversationService.clearSummaryCache();
    log('[ConversationListProvider] State cleared.');
  }
}
