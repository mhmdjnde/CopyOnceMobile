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
/// stand-in — a real picker opens system UI that a widget test cannot dismiss.
class MediaPicker {
  const MediaPicker();

  /// Opens the photo library, restricted to images.
  ///
  /// [ImagePicker.pickImage] shows only images, so a video or document cannot
  /// be chosen in the first place. That is the first of three gates: the picker
  /// here, the magic-byte sniff in MediaEncoder, and the bucket's
  /// allowed_mime_types. The picker is a convenience; the other two are the
  /// ones that hold.
  ///
  /// Returns null when the user backs out.
  Future<PickedImage?> pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    return PickedImage(bytes: bytes, filename: file.name);
  }
}
