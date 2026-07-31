import 'dart:typed_data';

import 'package:copy_once/models/clipboard_item.dart';
import 'package:copy_once/repositories/clipboard_repository.dart';
import 'package:copy_once/repositories/media_repository.dart';

/// In-memory [MediaRepository] stand-in.
///
/// Models the relay's two moving parts — which devices hold which image, and
/// what the reaper would remove — without a bucket behind it.
class FakeMediaRepository implements MediaRepository {
  final List<String> calls = [];

  /// When set, the next call throws this instead of succeeding.
  ClipboardFailure? failure;

  /// Fails only [markDelivered], so a lost receipt can be tested apart from a
  /// failed download.
  ClipboardFailure? deliveryFailure;

  /// Rows this fake has "stored", newest first.
  final List<ClipboardItem> uploaded = [];

  /// Storage paths deleted, in the order they went.
  final List<String> deletedPaths = [];

  /// Delivery receipts recorded, as `itemId:deviceRowId`.
  final List<String> deliveries = [];

  /// Item ids returned by the next [reapExpired].
  List<String> reapable = [];

  Uint8List thumbnailBytes = Uint8List.fromList([1, 2, 3]);
  Uint8List originalBytes = Uint8List.fromList([4, 5, 6, 7]);

  /// The last filename passed to [upload], after the repository sanitised it.
  String? lastFilename;

  @override
  Future<ClipboardItem> upload({
    required Uint8List bytes,
    required String filename,
    String? deviceId,
    String? deviceName,
    DevicePlatform? devicePlatform,
  }) async {
    calls.add('upload');
    if (failure != null) throw failure!;

    lastFilename = filename;
    final id = 'image-${uploaded.length + 1}';
    final item = ClipboardItem(
      id: id,
      type: ClipboardItemType.image,
      content: filename,
      deviceName: deviceName ?? 'This device',
      devicePlatform: devicePlatform ?? DevicePlatform.android,
      timestamp: DateTime.now(),
      storagePath: 'user/$id/full.jpg',
      thumbPath: 'user/$id/thumb.jpg',
      byteSize: bytes.length,
      mimeType: 'image/jpeg',
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );

    uploaded.insert(0, item);
    return item;
  }

  @override
  Future<Uint8List?> thumbnail(ClipboardItem item) async {
    calls.add('thumbnail');
    if (failure != null) throw failure!;
    return thumbnailBytes;
  }

  @override
  Future<Uint8List> original(ClipboardItem item) async {
    calls.add('original');
    if (failure != null) throw failure!;
    return originalBytes;
  }

  @override
  Future<void> markDelivered({
    required String itemId,
    required String deviceRowId,
  }) async {
    calls.add('markDelivered');
    if (deliveryFailure != null) throw deliveryFailure!;
    if (failure != null) throw failure!;
    deliveries.add('$itemId:$deviceRowId');
  }

  @override
  Future<int> reapExpired() async {
    calls.add('reapExpired');
    if (failure != null) throw failure!;
    final count = reapable.length;
    reapable = [];
    return count;
  }

  @override
  Future<void> deleteFiles(ClipboardItem item) async {
    calls.add('deleteFiles');
    if (failure != null) throw failure!;
    if (item.storagePath != null) deletedPaths.add(item.storagePath!);
    if (item.thumbPath != null) deletedPaths.add(item.thumbPath!);
  }
}
