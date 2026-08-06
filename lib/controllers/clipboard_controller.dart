import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/clipboard_item.dart';
import '../models/device_info.dart';
import '../models/sync_settings.dart';
import '../repositories/clipboard_repository.dart';
import '../repositories/media_repository.dart';
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
    this._settings,
    this._media, {
    DeviceIdentity? identity,
  }) : _identity = identity ?? DeviceIdentity();

  final ClipboardRepository _repository;
  final SettingsController _settings;
  final MediaRepository _media;
  final DeviceIdentity _identity;

  /// This device's row id, learned at registration.
  ///
  /// Delivery receipts are keyed on it, so image relaying only works once
  /// registration has succeeded. Null until then, which is why every receipt
  /// path tolerates its absence rather than waiting on it.
  String? _deviceRowId;

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
      await _reapExpiredMedia();
      _items = await _repository.fetchItems();
      _status = ClipboardListStatus.ready;
      notifyListeners();

      await _registerThisDevice();
      // Loaded here, not only on the Devices screen: the home header shows a
      // device count, and without this it reads "0 devices" next to items that
      // plainly came from two.
      await loadDevices();
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
      // Files before the row, the same order the reaper uses. The row is the
      // only remaining pointer to the files, so it has to outlive them.
      if (item.isImage) {
        await _media.deleteFiles(item);
      }
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

  // ── Images ─────────────────────────────────────────────────────────────────
  //
  // An image is a relay, not a stored file: it exists until every device on the
  // account has fetched the original, or 24 hours, whichever comes first.
  // "Fetched" means the full-resolution bytes were downloaded — seeing a
  // thumbnail in the list is not receipt of the image.

  bool _isUploading = false;

  /// True while an upload is in flight, so the UI can show progress and refuse
  /// a second pick.
  bool get isUploading => _isUploading;

  /// How far through a multi-image upload we are, as (done, total).
  ///
  /// Null when nothing is uploading, and null for a single image — "Sending…"
  /// says enough for one, and "1 of 1" reads like a bug.
  (int, int)? _uploadProgress;
  (int, int)? get uploadProgress => _uploadProgress;

  /// Sends several images, one after another.
  ///
  /// Serial rather than parallel: each upload puts two objects in Storage and
  /// decodes a full-resolution image for its thumbnail, and doing eight at once
  /// on a phone is how you get an out-of-memory kill. It also means a quota
  /// refusal stops the run instead of firing eight times.
  ///
  /// Returns how many were stored. [errorMessage] carries the reason when that
  /// is fewer than asked for.
  Future<int> uploadImages(
    List<({Uint8List bytes, String filename})> images,
  ) async {
    if (_isUploading || images.isEmpty) return 0;

    _isUploading = true;
    _errorMessage = null;
    _uploadProgress = images.length > 1 ? (0, images.length) : null;
    notifyListeners();

    var stored = 0;
    try {
      for (final image in images) {
        final saved = await _uploadOne(
          bytes: image.bytes,
          filename: image.filename,
        );

        // A refusal part-way through is almost always the quota, and every
        // remaining image would hit the same wall. Stop and report.
        if (saved == null) break;

        stored++;
        if (_uploadProgress != null) {
          _uploadProgress = (stored, images.length);
          notifyListeners();
        }
      }
      return stored;
    } finally {
      _isUploading = false;
      _uploadProgress = null;
      notifyListeners();
    }
  }

  /// Sends one image to the account's other devices.
  ///
  /// Returns the stored item, or null when the upload failed — in which case
  /// [errorMessage] explains why.
  Future<ClipboardItem?> uploadImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (_isUploading) return null;

    _isUploading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await _uploadOne(bytes: bytes, filename: filename);
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// The upload itself, without the in-flight bookkeeping, so a batch can call
  /// it repeatedly without fighting its own guard.
  Future<ClipboardItem?> _uploadOne({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final saved = await _media.upload(
        bytes: bytes,
        filename: filename,
        deviceId: await _identity.installId(),
        deviceName: await _identity.deviceName(),
        devicePlatform: _identity.platform,
      );

      // This device is holding the original already — it is the one that sent
      // it. Recording that now is what lets a one-device account reap straight
      // away instead of waiting out the whole backstop.
      await _recordDelivery(saved.id);

      _items = [saved, ..._items];
      return saved;
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
      return null;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Thumbnail bytes for [item], or null if it cannot be fetched.
  Future<Uint8List?> thumbnailFor(ClipboardItem item) async {
    try {
      return await _media.thumbnail(item);
    } on ClipboardFailure {
      // A card with a placeholder is a better outcome than an error banner
      // over the whole list.
      return null;
    }
  }

  /// The full-resolution original — and the moment this device counts as
  /// having received it.
  ///
  /// Recording the receipt here is what makes the relay work: once the last
  /// device has pulled the original, the image has done its job and the
  /// database collapses its expiry.
  Future<Uint8List?> openOriginal(ClipboardItem item) async {
    try {
      final bytes = await _media.original(item);
      await _recordDelivery(item.id);
      return bytes;
    } on ClipboardFailure catch (failure) {
      _errorMessage = failure.message;
      notifyListeners();
      return null;
    }
  }

  /// Fetches several originals, marking each delivered as it lands.
  ///
  /// Serial on purpose: each is a full-resolution image held in memory, and
  /// pulling eight at once on a phone is a spike for no gain. Reports progress
  /// so the screen can count them off.
  ///
  /// Each fetch counts as delivery, so a bulk save can complete the relay and
  /// clear the images, exactly as saving them one at a time would.
  Future<List<(ClipboardItem, Uint8List)>> fetchOriginals(
    List<ClipboardItem> items, {
    void Function(int done, int total)? onProgress,
  }) async {
    final fetched = <(ClipboardItem, Uint8List)>[];

    for (final item in items) {
      try {
        final bytes = await _media.original(item);
        fetched.add((item, bytes));
        onProgress?.call(fetched.length, items.length);

        final deviceRowId = _deviceRowId;
        if (deviceRowId != null) {
          try {
            await _media.markDelivered(
              itemId: item.id,
              deviceRowId: deviceRowId,
            );
          } on ClipboardFailure {
            // A lost receipt only delays deletion to the backstop.
          }
        }
      } on ClipboardFailure catch (failure) {
        _errorMessage = failure.message;
        notifyListeners();
        break;
      }
    }

    if (fetched.isNotEmpty) {
      try {
        final removed = await _media.reapExpired();
        if (removed > 0) await refresh();
      } on ClipboardFailure {
        // Best effort.
      }
    }

    return fetched;
  }

  /// Notes that this device now holds [itemId], and clears it if that was the
  /// last device owing a copy.
  ///
  /// The receipt makes the database collapse the image's expiry, but something
  /// still has to do the deleting. Waiting for the next app launch meant an
  /// image everyone already had could sit for hours; the client that recorded
  /// the final receipt is right here and knows the set is complete, so it
  /// deletes now. The 24-hour backstop is unchanged and still covers devices
  /// that never come back.
  ///
  /// Silent on failure by design: a lost receipt only means the image waits for
  /// that backstop, which is not worth putting in front of the user.
  Future<void> _recordDelivery(String itemId) async {
    final deviceRowId = _deviceRowId;
    if (deviceRowId == null) return;

    try {
      await _media.markDelivered(itemId: itemId, deviceRowId: deviceRowId);
      // Cheap when nothing is due: the reaper asks for expired rows and gets an
      // empty list back.
      final removed = await _media.reapExpired();
      if (removed > 0) await refresh();
    } on ClipboardFailure {
      // See above.
    }
  }

  /// Clears this account's finished images on launch.
  ///
  /// The scheduled reaper does this for everyone; this covers the window where
  /// a free-tier project has been paused and cron has not run.
  Future<void> _reapExpiredMedia() async {
    try {
      await _media.reapExpired();
    } on ClipboardFailure {
      // Best effort — the scheduled reaper collects whatever this misses.
    }
  }

  Future<ClipboardItem?> _save(String content, {required bool isLink}) async {
    try {
      final saved = await _repository.addItem(
        content: content,
        type: isLink ? ClipboardItemType.link : ClipboardItemType.text,
        deviceId: await _identity.installId(),
        deviceName: await _identity.deviceName(),
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
      _deviceRowId = await _repository.registerDevice(
        installId: await _identity.installId(),
        name: await _identity.deviceName(),
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
