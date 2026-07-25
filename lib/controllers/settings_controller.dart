import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/sync_settings.dart';
import '../repositories/clipboard_repository.dart';
import '../repositories/settings_repository.dart';

/// Owns the account's sync preferences and answers whether syncing is allowed
/// right now.
///
/// Toggles apply optimistically so a switch never feels laggy, and roll back if
/// the write fails.
class SettingsController extends ChangeNotifier {
  SettingsController(this._repository, {Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final SettingsRepository _repository;
  final Connectivity _connectivity;

  SyncSettings? _settings;

  /// Null until loaded, so screens can show a loading state.
  SyncSettings? get settings => _settings;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _settings = await _repository.load();
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setAutoSync(bool value) =>
      _update((s) => s.copyWith(autoSync: value));

  Future<void> setWifiOnly(bool value) =>
      _update((s) => s.copyWith(wifiOnly: value));

  Future<void> setSyncAlerts(bool value) =>
      _update((s) => s.copyWith(syncAlerts: value));

  Future<void> setRetentionDays(int days) =>
      _update((s) => s.copyWith(retentionDays: days));

  Future<void> setCaptureText(bool value) =>
      _update((s) => s.copyWith(captureText: value));

  Future<void> setCaptureLinks(bool value) =>
      _update((s) => s.copyWith(captureLinks: value));

  /// Whether a capture may be sent right now.
  ///
  /// Answers no when auto-sync is off, when the item's type is filtered out, or
  /// when Wi-Fi only is set and the device is on mobile data.
  Future<bool> canSync({required bool isLink}) async {
    final settings = _settings;
    if (settings == null) return false;
    if (!settings.autoSync) return false;
    if (!settings.allows(isLink)) return false;
    if (!settings.wifiOnly) return true;
    return isOnWifi();
  }

  /// True when the current connection is Wi-Fi or ethernet.
  ///
  /// A VPN reports itself as its own transport, so it counts as allowed — the
  /// setting exists to protect a data allowance, and a VPN over Wi-Fi should not
  /// be treated as mobile data.
  Future<bool> isOnWifi() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any(
        (r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet ||
            r == ConnectivityResult.vpn,
      );
    } on Object {
      // If connectivity cannot be determined, do not block the user's clipboard.
      return true;
    }
  }

  /// Applies [change] immediately, then persists it — restoring the previous
  /// value if the write fails so the UI never claims a saved setting it lost.
  Future<void> _update(SyncSettings Function(SyncSettings) change) async {
    final current = _settings;
    if (current == null) return;

    final updated = change(current);
    _settings = updated;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.save(updated);
    } on ClipboardFailure catch (failure) {
      _settings = current;
      _errorMessage = failure.message;
      notifyListeners();
    }
  }
}
