import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';

import '../models/profile_model.dart';
import '../services/auth_service.dart';

class UserSelectionProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService;

  List<Profile> _users = [];
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  UserSelectionProvider(this._authService);

  List<Profile> get users => _users;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;

  Future<void> fetchUsers() async {
    final currentUserId = _authService.userId;
    if (currentUserId == null) {
      _setError('User not logged in.');
      return;
    }

    if (_isLoading) return;
    _setLoading(true);

    try {
      log('[UserSelectionProvider] Fetching users...');
      // Fetch all profiles except the current user's profile
      final response = await _supabase
          .from('profiles')
          .select('user_id, display_name')
          .neq('user_id', currentUserId) // Exclude self
          .order('display_name', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      _users = data.map((json) => Profile.fromJson(json as Map<String, dynamic>)).toList();
      log('[UserSelectionProvider] Fetched ${_users.length} users.');
      _setLoading(false);
    } on PostgrestException catch (e) {
      log('[UserSelectionProvider] Error fetching users: ${e.message}', error: e);
      _setError('Error fetching users: ${e.message}');
    } catch (e, stacktrace) {
      log('[UserSelectionProvider] Generic error fetching users: $e', stackTrace: stacktrace);
      _setError('An unexpected error occurred.');
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    if (loading) {
      _hasError = false;
      _errorMessage = '';
    }
    notifyListeners();
  }

  void _setError(String message) {
    _isLoading = false;
    _hasError = true;
    _errorMessage = message;
    notifyListeners();
  }
} 