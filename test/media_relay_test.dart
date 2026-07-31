import 'package:copy_once/controllers/clipboard_controller.dart';
import 'package:copy_once/controllers/settings_controller.dart';
import 'package:copy_once/models/clipboard_item.dart';
import 'package:copy_once/repositories/clipboard_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_clipboard_repository.dart';
import 'fakes/fake_connectivity.dart';
import 'fakes/fake_media_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeClipboardRepository repository;
  late FakeMediaRepository media;
  late FakeSettingsRepository settingsRepository;
  late SettingsController settings;
  late ClipboardController controller;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );

    repository = FakeClipboardRepository();
    media = FakeMediaRepository();
    settingsRepository = FakeSettingsRepository();
    settings = SettingsController(
      settingsRepository,
      connectivity: FakeConnectivity(onWifi: true),
    );
    await settings.load();

    controller = ClipboardController(
      repository,
      settings,
      media,
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

  final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

  group('upload', () {
    test('adds the image to the top of the list', () async {
      final saved = await controller.uploadImage(
        bytes: bytes,
        filename: 'sunset.jpg',
      );

      expect(saved, isNotNull);
      expect(saved!.isImage, isTrue);
      expect(controller.items.first.id, saved.id);
    });

    test('records this device as already holding what it just sent', () async {
      // Without this the uploading device would wait for its own copy, and a
      // one-device account would never reap before the 24-hour backstop.
      await controller.start();
      final saved = await controller.uploadImage(
        bytes: bytes,
        filename: 'note.png',
      );

      expect(
        media.deliveries,
        contains('${saved!.id}:${repository.deviceRowId}'),
      );
    });

    test('surfaces the quota message and adds nothing', () async {
      media.failure = const ClipboardFailure(
        'You can have 10 images waiting at once.',
      );

      final saved = await controller.uploadImage(
        bytes: bytes,
        filename: 'eleventh.jpg',
      );

      expect(saved, isNull);
      expect(controller.items, isEmpty);
      expect(controller.errorMessage, contains('10 images'));
    });

    test('refuses a second upload while one is in flight', () async {
      final first = controller.uploadImage(bytes: bytes, filename: 'a.jpg');
      final second = controller.uploadImage(bytes: bytes, filename: 'b.jpg');

      expect(await second, isNull, reason: 'second pick should be ignored');
      expect(await first, isNotNull);
      expect(media.calls.where((c) => c == 'upload').length, 1);
    });

    test('clears the in-flight flag even when the upload fails', () async {
      media.failure = const ClipboardFailure('nope');
      await controller.uploadImage(bytes: bytes, filename: 'x.jpg');

      expect(controller.isUploading, isFalse);
    });
  });

  group('delivery', () {
    test(
      'fetching the original marks this device as having received it',
      () async {
        await controller.start();
        final saved = await controller.uploadImage(
          bytes: bytes,
          filename: 'photo.jpg',
        );
        media.deliveries.clear();

        final original = await controller.openOriginal(saved!);

        expect(original, media.originalBytes);
        expect(media.deliveries, ['${saved.id}:${repository.deviceRowId}']);
      },
    );

    test('viewing a thumbnail does not count as delivery', () async {
      // Seeing a small preview in the list is not receipt of the image; only
      // pulling the full original is.
      await controller.start();
      final saved = await controller.uploadImage(
        bytes: bytes,
        filename: 'photo.jpg',
      );
      media.deliveries.clear();

      await controller.thumbnailFor(saved!);

      expect(media.deliveries, isEmpty);
    });

    test('a failed receipt is silent and still returns the image', () async {
      // A lost receipt only delays deletion to the 24-hour backstop, so it must
      // not put anything in front of the user.
      await controller.start();
      final saved = await controller.uploadImage(
        bytes: bytes,
        filename: 'photo.jpg',
      );
      media.deliveryFailure = const ClipboardFailure('receipt failed');

      final original = await controller.openOriginal(saved!);

      expect(original, media.originalBytes);
      expect(controller.errorMessage, isNull);
    });

    test('does nothing when the device has not registered', () async {
      // No start(), so no device row id.
      final saved = await controller.uploadImage(
        bytes: bytes,
        filename: 'photo.jpg',
      );

      expect(saved, isNotNull);
      expect(media.deliveries, isEmpty);
    });
  });

  group('reaping', () {
    test('clears finished images on launch', () async {
      media.reapable = ['a', 'b'];
      await controller.start();

      expect(media.calls, contains('reapExpired'));
    });

    test('a reap failure does not stop the list from loading', () async {
      // The scheduled reaper covers whatever this misses; a stale image is a
      // far better outcome than a screen that will not load.
      media.failure = const ClipboardFailure('reap failed');
      await controller.start();

      expect(controller.status, ClipboardListStatus.ready);
    });
  });

  group('deletion', () {
    test('removes both the original and the thumbnail, then the row', () async {
      final saved = await controller.uploadImage(
        bytes: bytes,
        filename: 'gone.jpg',
      );

      final deleted = await controller.deleteItem(saved!);

      expect(deleted, isTrue);
      expect(media.deletedPaths, [saved.storagePath, saved.thumbPath]);
      expect(repository.calls, contains('deleteItem'));
      expect(controller.items, isEmpty);
    });

    test('does not touch storage for a text item', () async {
      final text = ClipboardItem(
        id: 't1',
        type: ClipboardItemType.text,
        content: 'hello',
        deviceName: 'Phone',
        devicePlatform: DevicePlatform.android,
        timestamp: DateTime.now(),
      );

      await controller.deleteItem(text);

      expect(media.calls, isNot(contains('deleteFiles')));
    });

    test('keeps the item when file deletion fails', () async {
      final saved = await controller.uploadImage(
        bytes: bytes,
        filename: 'stuck.jpg',
      );
      media.failure = const ClipboardFailure('storage down');

      final deleted = await controller.deleteItem(saved!);

      expect(deleted, isFalse);
      expect(controller.items.map((i) => i.id), contains(saved.id));
      expect(repository.calls, isNot(contains('deleteItem')));
    });
  });

  group('ClipboardItem image helpers', () {
    ClipboardItem imageWith({DateTime? expiresAt, int? byteSize}) {
      return ClipboardItem(
        id: 'i1',
        type: ClipboardItemType.image,
        content: 'x.jpg',
        deviceName: 'Phone',
        devicePlatform: DevicePlatform.android,
        timestamp: DateTime.now(),
        expiresAt: expiresAt,
        byteSize: byteSize,
      );
    }

    test(
      'timeLeft clamps a passed expiry to zero rather than going negative',
      () {
        final item = imageWith(
          expiresAt: DateTime.now().subtract(const Duration(hours: 2)),
        );
        expect(item.timeLeft, Duration.zero);
      },
    );

    test('timeLeft counts down from a future expiry', () {
      final item = imageWith(
        expiresAt: DateTime.now().add(const Duration(hours: 5)),
      );
      expect(item.timeLeft!.inHours, inInclusiveRange(4, 5));
    });

    test('timeLeft is null for a text item', () {
      final text = ClipboardItem(
        id: 't',
        type: ClipboardItemType.text,
        content: 'hi',
        deviceName: 'Phone',
        devicePlatform: DevicePlatform.android,
        timestamp: DateTime.now(),
      );
      expect(text.timeLeft, isNull);
    });

    test('readableSize scales its unit', () {
      expect(imageWith(byteSize: 512).readableSize, '512 B');
      expect(imageWith(byteSize: 2048).readableSize, '2 KB');
      expect(imageWith(byteSize: 3 * 1024 * 1024).readableSize, '3.0 MB');
      expect(imageWith().readableSize, '');
    });

    test('fromRow reads the image columns', () {
      final item = ClipboardItem.fromRow({
        'id': 'abc',
        'content': 'holiday.png',
        'content_type': 'image',
        'created_at': DateTime.now().toIso8601String(),
        'storage_path': 'u/abc/full.png',
        'thumb_path': 'u/abc/thumb.jpg',
        'byte_size': 4096,
        'mime_type': 'image/png',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 12))
            .toIso8601String(),
      });

      expect(item.isImage, isTrue);
      expect(item.storagePath, 'u/abc/full.png');
      expect(item.thumbPath, 'u/abc/thumb.jpg');
      expect(item.byteSize, 4096);
      expect(item.mimeType, 'image/png');
      expect(item.timeLeft!.inHours, inInclusiveRange(11, 12));
    });

    test('fromRow leaves image fields null for a text row', () {
      final item = ClipboardItem.fromRow({
        'id': 'abc',
        'content': 'hello',
        'content_type': 'text',
        'created_at': DateTime.now().toIso8601String(),
      });

      expect(item.isImage, isFalse);
      expect(item.storagePath, isNull);
      expect(item.expiresAt, isNull);
      expect(item.timeLeft, isNull);
    });
  });
}
