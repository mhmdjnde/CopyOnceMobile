import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/clipboard_item.dart';
import '../models/device_info.dart';
import '../models/sync_settings.dart';
import '../repositories/clipboard_repository.dart';
import '../services/device_identity.dart';
import 'settings_controller.dart';

/// What the clipboard list is currently doing, so the UI can show a real state
/// instead of an empty list that might mean "loading" or "nothing here".
enum ClipboardListStatus { initial, loading, ready, error }

/// Owns the synced clipboard: the list, capture, and deletion.
///
/// Capture is driven from here rather than from a widget so the rules — filters,
/// Wi-Fi only, de-duplication — live in one place and are testable without a
/// screen.
class ClipboardController extends ChangeNotifier {
  ClipboardController(
    this._repository,
    this._settings, {
    DeviceIdentity? identity,
  }) : _identity = identity ?? DeviceIdentity();

  final ClipboardRepository _repository;
  final SettingsController _settings;
  final DeviceIdentity _identity;

  StreamSubscription<List<ClipboardItem>>? _subscription;

  List<ClipboardItem> _items = const [];
  List<ClipboardItem> get items => _items;

  ClipboardListStatus _status = ClipboardListStatus.initial;
  ClipboardListStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Content of the last thing this device captured or copied out.
  ///
  /// Held in memory only, and only to avoid re-saving the same value when the
  /// app is resumed repeatedly. Never written to disk.
  String? _lastSeenContent;

  /// Set when an item arrives from another device and sync alerts are on, for
  /// the UI to announce and then clear.
  ClipboardItem? _pendingAlert;
  ClipboardItem? get pendingAlert => _pendingAlert;

  void consumeAlert() {
    if (_pendingAlert == null) return;
    _pendingAlert = null;
    notifyListeners();
  }

  /// Loads the list and starts watching for changes from other devices.
  Future<void> start() async {
    _status = ClipboardListStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // Retention first, so expired items never flash up before being removed.
      await _repository.pruneExpired();
      _items = await _repository.fetchItems();
      _status = ClipboardListStatus.ready;
      notifyListeners();

      await _registerThisDevice();
      _listenForChanges();
    } on ClipboardFailure catch (failure) {
      _status = ClipboardListStatus.error;
      _errorMessage = failure.message;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      _items = await _repository.fetchItems();
      _errorMessage = null;
      _status = ClipboardListStatus.ready;
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
      _status = ClipboardListStatus.error;
    }
    notifyListeners();
  }

  /// Reads the device clipboard and saves it if it is new and allowed.
  ///
  /// Called when the app comes to the foreground and from the manual capture
  /// button. Android only lets an app read the clipboard while it has focus,
  /// which is why this is tied to those moments rather than a background timer.
  ///
  /// Returns the saved item, or null when there was nothing new to save.
  Future<ClipboardItem?> captureFromDevice() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final content = data?.text?.trim() ?? '';
    if (content.isEmpty) return null;

    // Cheap guard before any network call: this is what we last handled.
    if (content == _lastSeenContent) return null;

    final isLink = ClipboardItem.looksLikeLink(content);
    if (!await _settings.canSync(isLink: isLink)) {
      // Remembered anyway, so a filtered value is not re-examined on every
      // resume.
      _lastSeenContent = content;
      return null;
    }

    return _save(content, isLink: isLink);
  }

  /// Saves [content] that arrived from outside the app, such as a share.
  Future<ClipboardItem?> captureShared(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return Future.value(null);
    return _save(trimmed, isLink: ClipboardItem.looksLikeLink(trimmed));
  }

  /// Copies an item back to the device clipboard.
  ///
  /// Records it as last-seen so the resume that follows does not treat our own
  /// paste as a fresh capture and duplicate the row.
  Future<void> copyToDevice(ClipboardItem item) async {
    await Clipboard.setData(ClipboardData(text: item.content));
    _lastSeenContent = item.content;
  }

  Future<bool> deleteItem(ClipboardItem item) async {
    final previous = _items;
    _items = _items.where((i) => i.id != item.id).toList();
    notifyListeners();

    try {
      await _repository.deleteItem(item.id);
      return true;
    } on ClipboardFailure catch (failure) {
      _items = previous;
      _errorMessage = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> togglePinned(ClipboardItem item) async {
    try {
      await _repository.setPinned(id: item.id, isPinned: !item.isPinned);
      await refresh();
      return true;
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
      notifyListeners();
      return false;
    }
  }

  /// Deletes every synced item for this account.
  ///
  /// Clears the stored history only — the device's own clipboard is untouched.
  Future<bool> clearHistory() async {
    try {
      await _repository.clearHistory();
      _items = const [];
      _errorMessage = null;
      notifyListeners();
      return true;
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<ClipboardItem?> _save(String content, {required bool isLink}) async {
    try {
      final saved = await _repository.addItem(
        content: content,
        type: isLink ? ClipboardItemType.link : ClipboardItemType.text,
        deviceId: await _identity.installId(),
        deviceName: _identity.deviceName,
        devicePlatform: _identity.platform,
      );

      _lastSeenContent = content;
      if (saved != null) {
        _items = [saved, ..._items];
        _errorMessage = null;
        notifyListeners();
      }
      return saved;
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
      notifyListeners();
      return null;
    }
  }

  List<DeviceInfo> _devices = const [];

  /// Devices signed in to this account, newest-seen first.
  List<DeviceInfo> get devices => _devices;

  Future<void> loadDevices() async {
    try {
      _devices = await _repository.fetchDevices(
        currentInstallId: await _identity.installId(),
      );
      notifyListeners();
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
      notifyListeners();
    }
  }

  /// Forgets a device. It reappears on that device's next launch — this is a
  /// tidy-up, not a way to revoke access; signing out or changing the password
  /// does that.
  Future<bool> removeDevice(DeviceInfo device) async {
    try {
      await _repository.removeDevice(device.id);
      _devices = _devices.where((d) => d.id != device.id).toList();
      notifyListeners();
      return true;
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> _registerThisDevice() async {
    try {
      await _repository.registerDevice(
        installId: await _identity.installId(),
        name: _identity.deviceName,
        platform: _identity.platform,
      );
    } on ClipboardFailure {
      // A missing device row costs a label, not the feature — do not surface it.
    }
  }

  void _listenForChanges() {
    _subscription?.cancel();
    _subscription = _repository.watchItems().listen(
      (items) {
        final arrived = _firstUnseenFromAnotherDevice(items);
        _items = items;
        _status = ClipboardListStatus.ready;

        if (arrived != null && (_settings.settings?.syncAlerts ?? false)) {
          _pendingAlert = arrived;
        }
        notifyListeners();
      },
      onError: (Object _) {
        // Realtime dropping out is not fatal: the list already loaded, and pull
        // to refresh still works.
      },
    );
  }

  /// The newest item that is not already on screen and did not come from here.
  ClipboardItem? _firstUnseenFromAnotherDevice(List<ClipboardItem> incoming) {
    if (_items.isEmpty || incoming.isEmpty) return null;

    final knownIds = _items.map((i) => i.id).toSet();
    for (final item in incoming) {
      if (!knownIds.contains(item.id) && item.content != _lastSeenContent) {
        return item;
      }
    }
    return null;
  }

  /// Applies the retention period now, for when it has just been changed.
  Future<int> applyRetention(SyncSettings settings) async {
    if (settings.retentionDays == 0) return 0;
    try {
      final removed = await _repository.pruneExpired();
      if (removed > 0) await refresh();
      return removed;
    } on ClipboardFailure {
      return 0;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
