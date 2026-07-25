import 'dart:async';

import 'package:copy_once/models/clipboard_item.dart';
import 'package:copy_once/models/device_info.dart';
import 'package:copy_once/models/sync_settings.dart';
import 'package:copy_once/repositories/clipboard_repository.dart';
import 'package:copy_once/repositories/settings_repository.dart';

/// In-memory [ClipboardRepository] stand-in.
class FakeClipboardRepository implements ClipboardRepository {
  final List<String> calls = [];

  List<ClipboardItem> items = [];
  List<DeviceInfo> devices = [];

  /// When set, the next call throws this instead of succeeding.
  ClipboardFailure? failure;

  int pruneResult = 0;
  String? lastSavedContent;
  ClipboardItemType? lastSavedType;

  /// Makes [addItem] behave as if the value were already the newest item.
  bool treatNextAsDuplicate = false;

  final _stream = StreamController<List<ClipboardItem>>.broadcast();

  @override
  Future<List<ClipboardItem>> fetchItems({int limit = 200}) async {
    calls.add('fetchItems');
    if (failure != null) throw failure!;
    return items;
  }

  @override
  Stream<List<ClipboardItem>> watchItems({int limit = 200}) => _stream.stream;

  /// Pushes a realtime update, as if another device had synced.
  Future<void> emit(List<ClipboardItem> incoming) async {
    _stream.add(incoming);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<ClipboardItem?> addItem({
    required String content,
    required ClipboardItemType type,
    String? deviceId,
    String? deviceName,
    DevicePlatform? devicePlatform,
  }) async {
    calls.add('addItem');
    if (failure != null) throw failure!;
    lastSavedContent = content;
    lastSavedType = type;
    if (treatNextAsDuplicate) return null;

    final item = ClipboardItem(
      id: 'item-${items.length + 1}',
      type: type,
      content: content,
      deviceName: deviceName ?? 'Test device',
      devicePlatform: devicePlatform ?? DevicePlatform.android,
      timestamp: DateTime.utc(2026, 7, 25),
    );
    items = [item, ...items];
    return item;
  }

  @override
  Future<void> deleteItem(String id) async {
    calls.add('deleteItem');
    if (failure != null) throw failure!;
    items = items.where((i) => i.id != id).toList();
  }

  @override
  Future<void> setPinned({required String id, required bool isPinned}) async {
    calls.add('setPinned');
    if (failure != null) throw failure!;
  }

  @override
  Future<void> clearHistory() async {
    calls.add('clearHistory');
    if (failure != null) throw failure!;
    items = [];
  }

  @override
  Future<int> pruneExpired() async {
    calls.add('pruneExpired');
    if (failure != null) throw failure!;
    return pruneResult;
  }

  @override
  Future<void> registerDevice({
    required String installId,
    required String name,
    required DevicePlatform platform,
  }) async {
    calls.add('registerDevice');
    if (failure != null) throw failure!;
  }

  @override
  Future<List<DeviceInfo>> fetchDevices({String? currentInstallId}) async {
    calls.add('fetchDevices');
    if (failure != null) throw failure!;
    return devices;
  }

  @override
  Future<void> removeDevice(String id) async {
    calls.add('removeDevice');
    if (failure != null) throw failure!;
    devices = devices.where((d) => d.id != id).toList();
  }

  void dispose() => _stream.close();
}

/// In-memory [SettingsRepository] stand-in.
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({this.stored = const SyncSettings()});

  SyncSettings stored;
  ClipboardFailure? failure;
  final List<String> calls = [];

  @override
  Future<SyncSettings> load() async {
    calls.add('load');
    if (failure != null) throw failure!;
    return stored;
  }

  @override
  Future<void> save(SyncSettings settings) async {
    calls.add('save');
    if (failure != null) throw failure!;
    stored = settings;
  }
}
