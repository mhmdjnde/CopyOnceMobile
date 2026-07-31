import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/clipboard_item.dart';
import '../services/media_encoder.dart';
import 'clipboard_repository.dart';

/// The only place that talks to the image bucket.
///
/// Separate from [ClipboardRepository] because it owns a different resource:
/// clipboard rows are one thing, Storage objects with their own lifecycle and
/// their own failure modes are another. The two share [ClipboardFailure] so
/// callers handle one error type.
///
/// Every path here is owner-scoped by Storage RLS. The explicit user id in the
/// path is the *subject* of that policy, not a substitute for it.
class MediaRepository {
  MediaRepository({SupabaseClient? client, Uuid? uuid})
    : _client = client ?? Supabase.instance.client,
      _uuid = uuid ?? const Uuid();

  /// Bucket holding both the originals and their thumbnails.
  static const String bucket = 'clipboard-media';

  /// Matches the bucket's file_size_limit and the byte_size check constraint.
  /// All three have to agree or an upload fails somewhere confusing.
  static const int maxImageBytes = 10 * 1024 * 1024;

  /// How long an undelivered image survives. The database is the authority —
  /// this only sets the value written at insert.
  static const Duration relayWindow = Duration(hours: 24);

  final SupabaseClient _client;
  final Uuid _uuid;

  /// Thumbnails already fetched this session, keyed by storage path.
  ///
  /// Bounded and in-memory only: image bytes are never written to disk by
  /// CopyOnce, and a relayed image should not outlive the process that showed
  /// it.
  final Map<String, Uint8List> _thumbnailCache = {};
  static const int _maxCachedThumbnails = 40;

  String? get _userId => _client.auth.currentUser?.id;

  /// Uploads [bytes] as a new image item and returns the stored row.
  ///
  /// Order matters: files go up first, the row last. A row without its files
  /// would render as a broken card that the reaper then tries to delete objects
  /// for; files without a row are invisible but harmless, and the orphan sweep
  /// collects them.
  Future<ClipboardItem> upload({
    required Uint8List bytes,
    required String filename,
    String? deviceId,
    String? deviceName,
    DevicePlatform? devicePlatform,
  }) {
    return _guard(() async {
      final userId = _requireUser();

      if (bytes.isEmpty) {
        throw const ClipboardFailure('That image is empty.');
      }
      if (bytes.length > maxImageBytes) {
        throw const ClipboardFailure('Images have to be under 10 MB.');
      }

      // The extension is a claim; the leading bytes are evidence.
      final mimeType = MediaEncoder.sniffMimeType(bytes);
      if (mimeType == null || !allowedImageMimeTypes.contains(mimeType)) {
        throw const ClipboardFailure(
          'That file type is not supported. Try a JPEG, PNG, GIF, WebP, or '
          'HEIC image.',
        );
      }

      final thumbnail = await MediaEncoder.thumbnail(bytes);

      // Generated here rather than by the database so the storage paths can be
      // built before the row exists — the shape constraint requires an image
      // row to carry its paths from the moment it is inserted.
      final itemId = _uuid.v4();
      final extension = MediaEncoder.extensionFor(mimeType);
      final fullPath = '$userId/$itemId/full.$extension';
      final thumbPath = '$userId/$itemId/thumb.jpg';

      await _client.storage
          .from(bucket)
          .uploadBinary(
            fullPath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );

      try {
        await _client.storage
            .from(bucket)
            .uploadBinary(
              thumbPath,
              thumbnail,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );

        final row = await _client
            .from('clipboard_items')
            .insert({
              'id': itemId,
              'user_id': userId,
              'content': _safeFilename(filename),
              'content_type': ClipboardItemType.image.name,
              'storage_path': fullPath,
              'thumb_path': thumbPath,
              'byte_size': bytes.length,
              'mime_type': mimeType,
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(relayWindow)
                  .toIso8601String(),
              'device_id': ?deviceId,
              'device_name': ?deviceName,
              if (devicePlatform != null)
                'device_platform': devicePlatform.name,
            })
            .select()
            .single();

        final item = ClipboardItem.fromRow(row);
        _remember(thumbPath, thumbnail);
        return item;
      } on Object {
        // The row never landed, so nothing will ever reference these files.
        // Clean them up now rather than waiting for the orphan sweep.
        await _discard([fullPath, thumbPath]);
        rethrow;
      }
    });
  }

  /// Thumbnail bytes for [item], from the session cache when possible.
  Future<Uint8List?> thumbnail(ClipboardItem item) {
    final path = item.thumbPath;
    if (path == null) return Future.value(null);

    final cached = _thumbnailCache[path];
    if (cached != null) return Future.value(cached);

    return _guard(() async {
      final bytes = await _client.storage.from(bucket).download(path);
      _remember(path, bytes);
      return bytes;
    });
  }

  /// The untouched original, for the download button.
  ///
  /// Never cached: it is large, it is wanted once, and holding it would keep a
  /// full-resolution image in memory long after the user saved it.
  Future<Uint8List> original(ClipboardItem item) {
    return _guard(() async {
      final path = item.storagePath;
      if (path == null) {
        throw const ClipboardFailure('That item has no image attached.');
      }
      return _client.storage.from(bucket).download(path);
    });
  }

  /// Records that [deviceRowId] now holds [itemId].
  ///
  /// The database decides what that means: a trigger collapses the image's
  /// expiry once every device on the account has a receipt.
  ///
  /// Failures are swallowed by the caller, not here — a missing receipt delays
  /// a deletion until the 24-hour backstop, which is not worth an error in
  /// front of the user.
  Future<void> markDelivered({
    required String itemId,
    required String deviceRowId,
  }) {
    return _guard(() async {
      final userId = _requireUser();
      await _client
          .from('clipboard_deliveries')
          .upsert(
            {'item_id': itemId, 'device_id': deviceRowId, 'user_id': userId},
            onConflict: 'item_id,device_id',
            ignoreDuplicates: true,
          );
    });
  }

  /// Deletes this account's finished images: files first, then rows.
  ///
  /// The client-side half of the reaper. The scheduled Edge Function does the
  /// same for every account whether or not anyone opens the app; this exists
  /// because free-tier projects pause when idle, and cron does not run while
  /// paused. Whoever opens the app first clears their own backlog.
  ///
  /// Returns how many images went.
  Future<int> reapExpired() {
    return _guard(() async {
      final rows = await _client.rpc('expired_media_paths') as List<dynamic>?;
      if (rows == null || rows.isEmpty) return 0;

      final ids = <String>[];
      final paths = <String>[];

      for (final row in rows.cast<Map<String, dynamic>>()) {
        final id = row['id'] as String?;
        if (id == null) continue;
        ids.add(id);
        final full = row['storage_path'] as String?;
        final thumb = row['thumb_path'] as String?;
        if (full != null) paths.add(full);
        if (thumb != null) paths.add(thumb);
      }

      if (ids.isEmpty) return 0;

      // Files first. If this throws, the rows stay — they are the only
      // remaining pointer to the files, so losing them would strand the bytes.
      await _client.storage.from(bucket).remove(paths);
      for (final path in paths) {
        _thumbnailCache.remove(path);
      }

      final removed = await _client.rpc(
        'reap_media_rows',
        params: {'item_ids': ids},
      );
      return (removed as int?) ?? 0;
    });
  }

  /// Deletes one image's files, for when the user removes it by hand.
  ///
  /// The row is deleted by [ClipboardRepository.deleteItem] afterwards, keeping
  /// the files-then-row order that holds everywhere else.
  Future<void> deleteFiles(ClipboardItem item) {
    return _guard(() async {
      final paths = [
        if (item.storagePath != null) item.storagePath!,
        if (item.thumbPath != null) item.thumbPath!,
      ];
      if (paths.isEmpty) return;

      await _client.storage.from(bucket).remove(paths);
      for (final path in paths) {
        _thumbnailCache.remove(path);
      }
    });
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Best-effort cleanup of files whose row failed to land.
  Future<void> _discard(List<String> paths) async {
    try {
      await _client.storage.from(bucket).remove(paths);
    } on Object {
      // The orphan sweep will collect them. Surfacing this would replace the
      // real error the caller is already about to see.
    }
  }

  void _remember(String path, Uint8List bytes) {
    if (_thumbnailCache.length >= _maxCachedThumbnails) {
      _thumbnailCache.remove(_thumbnailCache.keys.first);
    }
    _thumbnailCache[path] = bytes;
  }

  /// A filename safe to store and show.
  ///
  /// The name is untrusted input that ends up in a list row, so it is stripped
  /// of path separators and control characters and capped. Never empty: the
  /// content column rejects a blank string.
  static String _safeFilename(String raw) {
    final base = raw.split(RegExp(r'[/\\]')).last;
    final cleaned = base.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (cleaned.isEmpty) return 'Image';
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  String _requireUser() {
    final userId = _userId;
    if (userId == null) {
      throw const ClipboardFailure('Sign in to share images.');
    }
    return userId;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ClipboardFailure {
      rethrow;
    } on MediaEncodeException catch (e) {
      throw ClipboardFailure(e.message);
    } on StorageException catch (e) {
      throw ClipboardFailure(_storageMessage(e));
    } on PostgrestException catch (e) {
      throw ClipboardFailure(_postgrestMessage(e));
    } on Object {
      // Deliberately drops the raw error: a storage error echoes the object
      // path, and a path identifies the account.
      throw const ClipboardFailure(
        'Could not reach CopyOnce. Check your connection and try again.',
      );
    }
  }

  static String _storageMessage(StorageException e) {
    final status = e.statusCode ?? '';
    if (status == '413') return 'That image is too large to send.';
    if (status == '403' || status == '401') {
      return 'Your session needs to be verified again. Sign in once more.';
    }
    return 'Could not transfer that image. Please try again.';
  }

  static String _postgrestMessage(PostgrestException e) {
    // 54000 is program_limit_exceeded, raised by the media quota trigger.
    if (e.code == '54000' || e.message.contains('media_quota_exceeded')) {
      return 'You can have 10 images waiting at once. They clear as your '
          'devices pick them up, or after 24 hours.';
    }
    if (e.code == '42501' || e.code == 'PGRST301') {
      return 'Your session needs to be verified again. Sign in once more.';
    }
    if (e.code == '23514') {
      return 'That image could not be accepted.';
    }
    return 'Something went wrong sending that image. Please try again.';
  }
}
