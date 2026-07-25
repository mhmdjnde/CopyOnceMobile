import 'package:copy_once/controllers/clipboard_controller.dart';
import 'package:copy_once/controllers/settings_controller.dart';
import 'package:copy_once/models/clipboard_item.dart';
import 'package:copy_once/models/sync_settings.dart';
import 'package:copy_once/repositories/clipboard_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_clipboard_repository.dart';
import 'fakes/fake_connectivity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeClipboardRepository repository;
  late FakeSettingsRepository settingsRepository;
  late SettingsController settings;
  late ClipboardController controller;

  /// Contents the platform clipboard will report.
  String? deviceClipboard;

  setUp(() async {
    deviceClipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return deviceClipboard == null ? null : {'text': deviceClipboard};
          }
          if (call.method == 'Clipboard.setData') {
            deviceClipboard = (call.arguments as Map)['text'] as String?;
            return null;
          }
          return null;
        });

    repository = FakeClipboardRepository();
    settingsRepository = FakeSettingsRepository();
    settings = SettingsController(
      settingsRepository,
      connectivity: FakeConnectivity(onWifi: true),
    );
    await settings.load();

    controller = ClipboardController(
      repository,
      settings,
      identity: FakeDeviceIdentity(),
    );
  });

  tearDown(() {
    controller.dispose();
    settings.dispose();
    repository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('start', () {
    test('prunes, loads, and registers the device', () async {
      await controller.start();

      expect(controller.status, ClipboardListStatus.ready);
      expect(
        repository.calls,
        containsAllInOrder(['pruneExpired', 'fetchItems', 'registerDevice']),
      );
    });

    test('surfaces a failure as an error state', () async {
      repository.failure = const ClipboardFailure('Cannot reach CopyOnce.');

      await controller.start();

      expect(controller.status, ClipboardListStatus.error);
      expect(controller.errorMessage, 'Cannot reach CopyOnce.');
    });
  });

  group('captureFromDevice', () {
    test('saves new text from the clipboard', () async {
      deviceClipboard = 'a note worth keeping';

      final saved = await controller.captureFromDevice();

      expect(saved, isNotNull);
      expect(repository.lastSavedContent, 'a note worth keeping');
      expect(repository.lastSavedType, ClipboardItemType.text);
    });

    test('classifies a URL as a link', () async {
      deviceClipboard = 'https://example.com/page';

      await controller.captureFromDevice();

      expect(repository.lastSavedType, ClipboardItemType.link);
    });

    test('does nothing when the clipboard is empty', () async {
      final saved = await controller.captureFromDevice();

      expect(saved, isNull);
      expect(repository.calls, isEmpty);
    });

    test('does not save the same value twice in a row', () async {
      deviceClipboard = 'repeated value';
      await controller.captureFromDevice();
      repository.calls.clear();

      final second = await controller.captureFromDevice();

      expect(second, isNull);
      expect(repository.calls, isEmpty);
    });

    test('skips capture entirely when auto-sync is off', () async {
      await settings.setAutoSync(false);
      deviceClipboard = 'should not sync';

      final saved = await controller.captureFromDevice();

      expect(saved, isNull);
      expect(repository.calls, isEmpty);
    });

    test('respects the text filter', () async {
      await settings.setCaptureText(false);
      deviceClipboard = 'plain text';

      expect(await controller.captureFromDevice(), isNull);
      expect(repository.calls, isEmpty);
    });

    test('a link still syncs when only text is filtered out', () async {
      await settings.setCaptureText(false);
      deviceClipboard = 'https://example.com';

      expect(await controller.captureFromDevice(), isNotNull);
    });

    test('respects the link filter', () async {
      await settings.setCaptureLinks(false);
      deviceClipboard = 'https://example.com';

      expect(await controller.captureFromDevice(), isNull);
    });

    test('blocks capture on mobile data when Wi-Fi only is set', () async {
      final offWifi = SettingsController(
        settingsRepository,
        connectivity: FakeConnectivity(onWifi: false),
      );
      addTearDown(offWifi.dispose);
      await offWifi.load();
      await offWifi.setWifiOnly(true);

      final mobileController = ClipboardController(
        repository,
        offWifi,
        identity: FakeDeviceIdentity(),
      );
      addTearDown(mobileController.dispose);
      deviceClipboard = 'on mobile data';

      expect(await mobileController.captureFromDevice(), isNull);
      expect(repository.calls, isEmpty);
    });

    test('allows capture on Wi-Fi when Wi-Fi only is set', () async {
      await settings.setWifiOnly(true);
      deviceClipboard = 'on wifi';

      expect(await controller.captureFromDevice(), isNotNull);
    });
  });

  group('copyToDevice', () {
    test('does not re-capture what we just copied out', () async {
      final item = ClipboardItem(
        id: 'item-1',
        type: ClipboardItemType.text,
        content: 'from the list',
        deviceName: 'Other phone',
        devicePlatform: DevicePlatform.android,
        timestamp: DateTime.utc(2026),
      );

      await controller.copyToDevice(item);
      repository.calls.clear();

      // The clipboard now holds our own paste; a resume must not duplicate it.
      expect(await controller.captureFromDevice(), isNull);
      expect(repository.calls, isEmpty);
    });
  });

  group('deleteItem', () {
    test('removes the item and keeps it gone on success', () async {
      deviceClipboard = 'to delete';
      final saved = await controller.captureFromDevice();

      final deleted = await controller.deleteItem(saved!);

      expect(deleted, isTrue);
      expect(controller.items, isEmpty);
    });

    test('restores the item when the delete fails', () async {
      deviceClipboard = 'keep me';
      final saved = await controller.captureFromDevice();
      repository.failure = const ClipboardFailure('Offline.');

      final deleted = await controller.deleteItem(saved!);

      expect(deleted, isFalse);
      expect(controller.items.map((i) => i.id), contains(saved.id));
      expect(controller.errorMessage, 'Offline.');
    });
  });

  group('clearHistory', () {
    test('empties the list', () async {
      deviceClipboard = 'something';
      await controller.captureFromDevice();

      final cleared = await controller.clearHistory();

      expect(cleared, isTrue);
      expect(controller.items, isEmpty);
      expect(repository.calls, contains('clearHistory'));
    });
  });

  group('sync alerts', () {
    test('flags an item that arrived from elsewhere', () async {
      deviceClipboard = 'local item';
      await controller.captureFromDevice();
      await controller.start();

      await repository.emit([
        ClipboardItem(
          id: 'remote-1',
          type: ClipboardItemType.text,
          content: 'from the laptop',
          deviceName: 'Laptop',
          devicePlatform: DevicePlatform.linux,
          timestamp: DateTime.utc(2026, 7, 25),
        ),
        ...controller.items,
      ]);

      expect(controller.pendingAlert?.deviceName, 'Laptop');

      controller.consumeAlert();
      expect(controller.pendingAlert, isNull);
    });

    test('stays quiet when sync alerts are off', () async {
      await settings.setSyncAlerts(false);
      deviceClipboard = 'local item';
      await controller.captureFromDevice();
      await controller.start();

      await repository.emit([
        ClipboardItem(
          id: 'remote-2',
          type: ClipboardItemType.text,
          content: 'from the laptop',
          deviceName: 'Laptop',
          devicePlatform: DevicePlatform.linux,
          timestamp: DateTime.utc(2026, 7, 25),
        ),
        ...controller.items,
      ]);

      expect(controller.pendingAlert, isNull);
    });
  });

  group('retention', () {
    test('does not prune when set to keep forever', () async {
      final removed = await controller.applyRetention(
        const SyncSettings(retentionDays: 0),
      );

      expect(removed, 0);
      expect(repository.calls, isEmpty);
    });

    test('prunes and reports the count', () async {
      repository.pruneResult = 3;

      final removed = await controller.applyRetention(
        const SyncSettings(retentionDays: 7),
      );

      expect(removed, 3);
    });
  });
}
