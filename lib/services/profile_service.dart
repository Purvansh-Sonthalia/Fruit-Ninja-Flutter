import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final SupabaseClient _supabase;
  final Map<String, String?> _displayNameCache = {};

  // Optional: Singleton pattern for easy access, or provide via Provider
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService({SupabaseClient? supabaseClient}) {
    // Allow injecting client primarily for testing
    if (supabaseClient != null) {
      return ProfileService._internal(supabaseClient: supabaseClient);
    }
    return _instance;
  }
  ProfileService._internal({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  // Fetches display name, using cache first
  Future<String?> getDisplayName(String userIdToFetch) async {
    if (_displayNameCache.containsKey(userIdToFetch)) {
      log('[ProfileService] Cache hit for $userIdToFetch: ${_displayNameCache[userIdToFetch]}');
      return _displayNameCache[userIdToFetch];
    }
    log('[ProfileService] Cache miss for $userIdToFetch, fetching from DB.');
    try {
      final response = await _supabase
          .from('profiles')
          .select('display_name')
          .eq('user_id', userIdToFetch)
          .maybeSingle(); // Use maybeSingle

      final name = response?['display_name'] as String?;
      _displayNameCache[userIdToFetch] = name; // Cache result (even if null)
      log('[ProfileService] Fetched and cached name for $userIdToFetch: $name');
      return name;
    } catch (e, stacktrace) {
      log('[ProfileService] Error fetching display name for $userIdToFetch: $e\n$stacktrace');
      _displayNameCache[userIdToFetch] = null; // Cache null on error
      return null;
    }
  }

  // Optional: Pre-fetch and cache multiple display names
  Future<void> prefetchDisplayNames(Iterable<String> userIds) async {
    final List<String> idsToFetch =
        userIds.where((id) => !_displayNameCache.containsKey(id)).toList();

    if (idsToFetch.isEmpty) {
      log('[ProfileService] Prefetch: No new IDs to fetch.');
      return;
    }

    log('[ProfileService] Prefetching ${idsToFetch.length} display names...');
    try {
      final response = await _supabase
          .from('profiles')
          .select('user_id, display_name')
          .inFilter('user_id', idsToFetch);

      final List<dynamic> profilesData = response as List<dynamic>? ?? [];
      // Update cache with fetched data
      for (var profile in profilesData) {
        final userId = profile['user_id'] as String;
        final displayName = profile['display_name'] as String?;
        _displayNameCache[userId] = displayName;
      }
      // Cache null for any IDs requested but not found in the response
      for (var userId in idsToFetch) {
        _displayNameCache.putIfAbsent(userId, () => null);
      }
      log('[ProfileService] Prefetch complete. Cache size: ${_displayNameCache.length}');
    } catch (e, stacktrace) {
      log('[ProfileService] Error during prefetch: $e\n$stacktrace');
      // Cache null for IDs we tried to fetch on error
      for (var userId in idsToFetch) {
        _displayNameCache.putIfAbsent(userId, () => null);
      }
    }
  }

  // Optional: Clear cache if needed (e.g., on logout)
  void clearCache() {
    _displayNameCache.clear();
    log('[ProfileService] Cache cleared.');
  }
}
