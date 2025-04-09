import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  final SupabaseClient _supabaseClient = Supabase.instance.client;
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _supabaseClient.auth.currentUser != null;
  String? get username => _supabaseClient.auth.currentUser?.email;
  String? get userId => _supabaseClient.auth.currentUser?.id;

  // Initialize Supabase
  static Future<void> initialize(String supabaseUrl, String supabaseAnonKey) async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  // Sign in user with email and password
  Future<bool> signIn(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Sign up user with email and password
  Future<bool> signUp(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _supabaseClient.auth.signUp(
        email: email,
        password: password,
      );
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Sign out user
  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _supabaseClient.auth.signOut();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Listen to auth state changes
  void listenToAuthChanges() {
    _supabaseClient.auth.onAuthStateChange.listen((data) {
      notifyListeners();
    });
  }
} 