import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/clipboard_item.dart';
import '../models/device_info.dart';

/// Raised for clipboard failures, carrying a message safe to show.
///
/// Never carries the clipboard content itself — an error string can end up in a
/// log or a crash report, and the content must not follow it there.
class ClipboardFailure implements Exception {
  const ClipboardFailure(this.message);

  final String message;

  @override
  String toString() => 'ClipboardFailure: $message';
}

/// The only place that talks to the clipboard tables.
///
/// Every query is owner-scoped by Row Level Security; the explicit `user_id`
/// filters here are for index use and clarity, not for access control.
class ClipboardRepository {
  ClipboardRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// Longest content accepted, matching the table's check constraint. Anything
  /// larger is truncated rather than rejected, so a huge copy still syncs.
  static const int maxContentLength = 100000;

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  /// The account's items, newest first, pinned items ahead of the rest.
  Future<List<ClipboardItem>> fetchItems({int limit = 200}) {
    return _guard(() async {
      final userId = _requireUser();
      final rows = await _client
          .from('clipboard_items')
          .select()
          .eq('user_id', userId)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);

      return rows.map(ClipboardItem.fromRow).toList();
    });
  }

  /// Live view of the same rows, so an item copied on another device appears
  /// here without a refresh.
  Stream<List<ClipboardItem>> watchItems({int limit = 200}) {
    final userId = _userId;
    if (userId == null) return const Stream.empty();

    return _client
        .from('clipboard_items')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at')
        .limit(limit)
        .map((rows) {
          final items = rows.map(ClipboardItem.fromRow).toList();
          // The realtime stream cannot order by two columns, so pinned-first is
          // applied here to match fetchItems.
          items.sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            return b.timestamp.compareTo(a.timestamp);
          });
          return items;
        });
  }

  /// Saves a captured value.
  ///
  /// Returns null when [content] is blank or duplicates the newest item — a
  /// re-copy of what is already at the top is not worth a new row.
  Future<ClipboardItem?> addItem({
    required String content,
    required ClipboardItemType type,
    String? deviceId,
    String? deviceName,
    DevicePlatform? devicePlatform,
  }) {
    return _guard(() async {
      final userId = _requireUser();
      final trimmed = content.trim();
      if (trimmed.isEmpty) return null;

      final capped = trimmed.length > maxContentLength
          ? trimmed.substring(0, maxContentLength)
          : trimmed;

      if (await _isNewestItem(userId, capped)) return null;

      final row = await _client
          .from('clipboard_items')
          .insert({
            'user_id': userId,
            'content': capped,
            'content_type': type.name,
            'device_id': ?deviceId,
            'device_name': ?deviceName,
            if (devicePlatform != null) 'device_platform': devicePlatform.name,
          })
          .select()
          .single();

      return ClipboardItem.fromRow(row);
    });
  }

  Future<void> deleteItem(String id) {
    return _guard(() async {
      final userId = _requireUser();
      await _client
          .from('clipboard_items')
          .delete()
          .eq('id', id)
          .eq('user_id', userId);
    });
  }

  Future<void> setPinned({required String id, required bool isPinned}) {
    return _guard(() async {
      final userId = _requireUser();
      await _client
          .from('clipboard_items')
          .update({'is_pinned': isPinned})
          .eq('id', id)
          .eq('user_id', userId);
    });
  }

  /// Clears the account's synced history.
  ///
  /// Only touches rows in the database. The clipboard on the device is left
  /// alone — the user asked to forget what CopyOnce stored, not to reach into
  /// the OS clipboard they may still be pasting from.
  Future<void> clearHistory() {
    return _guard(() async {
      final userId = _requireUser();
      await _client.from('clipboard_items').delete().eq('user_id', userId);
    });
  }

  /// Applies the account's retention period, returning how many items went.
  Future<int> pruneExpired() {
    return _guard(() async {
      final removed = await _client.rpc('prune_expired_clipboard_items');
      return (removed as int?) ?? 0;
    });
  }

  // ── Devices ────────────────────────────────────────────────────────────────

  /// Records this install and refreshes its last-seen time.
  Future<void> registerDevice({
    required String installId,
    required String name,
    required DevicePlatform platform,
  }) {
    return _guard(() async {
      final userId = _requireUser();
      await _client.from('devices').upsert({
        'user_id': userId,
        'install_id': installId,
        'name': name,
        'platform': platform.name,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,install_id');
    });
  }

  Future<List<DeviceInfo>> fetchDevices({String? currentInstallId}) {
    return _guard(() async {
      final userId = _requireUser();
      final rows = await _client
          .from('devices')
          .select()
          .eq('user_id', userId)
          .order('last_seen_at', ascending: false);

      return rows.map((row) {
        return DeviceInfo(
          id: row['id'] as String,
          name: row['name'] as String? ?? 'Unknown device',
          platform: _platformFrom(row['platform'] as String?),
          isCurrentDevice:
              currentInstallId != null && row['install_id'] == currentInstallId,
          lastSeen:
              DateTime.tryParse(
                row['last_seen_at'] as String? ?? '',
              )?.toLocal() ??
              DateTime.now(),
        );
      }).toList();
    });
  }

  Future<void> removeDevice(String id) {
    return _guard(() async {
      final userId = _requireUser();
      await _client.from('devices').delete().eq('id', id).eq('user_id', userId);
    });
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// True when the newest stored item already holds this content.
  ///
  /// Compares hashes so the check does not ship the content back and forth.
  Future<bool> _isNewestItem(String userId, String content) async {
    final rows = await _client
        .from('clipboard_items')
        .select('content_hash')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return false;
    return rows.first['content_hash'] == _md5(content);
  }

  String _requireUser() {
    final userId = _userId;
    if (userId == null) {
      throw const ClipboardFailure('Sign in to sync your clipboard.');
    }
    return userId;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ClipboardFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw ClipboardFailure(_friendlyMessage(e));
    } on Object {
      // Deliberately drops the raw error: it can echo the row being written,
      // and that row is clipboard content.
      throw const ClipboardFailure(
        'Could not reach CopyOnce. Check your connection and try again.',
      );
    }
  }

  String _friendlyMessage(PostgrestException e) {
    final code = e.code ?? '';
    // 42501 is insufficient_privilege: RLS refused the row. With the assurance
    // check in place, the usual cause is a session that has not cleared 2FA.
    if (code == '42501' || code == 'PGRST301') {
      return 'Your session needs to be verified again. Sign in once more.';
    }
    if (code == '23514') {
      return 'That item is too large to sync.';
    }
    return 'Something went wrong syncing. Please try again.';
  }

  static DevicePlatform _platformFrom(String? value) => switch (value) {
    'ios' => DevicePlatform.ios,
    'macos' => DevicePlatform.macos,
    'windows' => DevicePlatform.windows,
    'linux' => DevicePlatform.linux,
    _ => DevicePlatform.android,
  };

  /// md5 of [content], matching the database's generated `content_hash`.
  ///
  /// md5 is used because Postgres' `md5(text)` defines the stored column, not
  /// because it needs to be collision-resistant — it only answers "is this the
  /// same string I just saved?".
  static String _md5(String content) =>
      crypto.md5.convert(utf8.encode(content)).toString();
}
