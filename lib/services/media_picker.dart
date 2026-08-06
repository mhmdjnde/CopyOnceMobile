import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// An image chosen by the user, held in memory.
///
/// Bytes rather than a file path: the picked file may live in a cache the OS
/// can clear at any moment, and CopyOnce never writes image data to its own
/// storage.
class PickedImage {
  const PickedImage({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// Wraps the platform image picker.
///
/// A class rather than a bare function so screens can be tested against a
/// stand-in — the real picker opens system UI that a widget test cannot
/// dismiss.
class MediaPicker {
  const MediaPicker();

  /// Opens the photo library, restricted to images, allowing several at once.
  ///
  /// [ImagePicker.pickMultiImage] shows only images, so a video or document
  /// cannot be chosen in the first place. That is the first of three gates: the
  /// picker here, the magic-byte sniff in MediaEncoder, and the bucket's
  /// allowed_mime_types. The picker is a convenience; the other two are the
  /// ones that hold.
  ///
  /// Works the same on both platforms — Android's system picker and the iOS
  /// PHPicker both support multi-select, and the plugin presents them behind
  /// this one call.
  ///
  /// Returns an empty list when the user backs out.
  Future<List<PickedImage>> pickFromGallery({int? limit}) async {
    final files = await ImagePicker().pickMultiImage(limit: limit);
    if (files.isEmpty) return const [];

    // Read sequentially rather than with Future.wait: several full-resolution
    // photos decoded at once is a memory spike on a mid-range phone, and the
    // upload that follows is serial anyway.
    final picked = <PickedImage>[];
    for (final file in files) {
      picked.add(
        PickedImage(bytes: await file.readAsBytes(), filename: file.name),
      );
    }
    return picked;
  }
}
