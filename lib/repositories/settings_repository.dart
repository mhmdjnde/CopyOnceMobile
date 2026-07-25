import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sync_settings.dart';
import 'clipboard_repository.dart';

/// Reads and writes the account's sync preferences.
///
/// Settings live server-side so they follow the account between devices.
class SettingsRepository {
  SettingsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  /// Loads the account's settings, creating the row if it is missing.
  ///
  /// New accounts get a row from a trigger, but accounts that existed before
  /// this table did will not have one — so the row is created on demand rather
  /// than assuming the trigger ran.
  Future<SyncSettings> load() {
    return _guard(() async {
      final userId = _requireUser();
      final row = await _client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row != null) return SyncSettings.fromRow(row);

      const defaults = SyncSettings();
      await _client.from('user_settings').insert({
        'user_id': userId,
        ...defaults.toRow(),
      });
      return defaults;
    });
  }

  Future<void> save(SyncSettings settings) {
    return _guard(() async {
      final userId = _requireUser();
      await _client.from('user_settings').upsert({
        'user_id': userId,
        ...settings.toRow(),
      }, onConflict: 'user_id');
    });
  }

  String _requireUser() {
    final userId = _userId;
    if (userId == null) {
      throw const ClipboardFailure('Sign in to change your settings.');
    }
    return userId;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ClipboardFailure {
      rethrow;
    } on Object {
      throw const ClipboardFailure(
        'Could not save your settings. Check your connection and try again.',
      );
    }
  }
}
