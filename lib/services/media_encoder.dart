import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest edge of a generated thumbnail. Enough to look sharp in the list on a
/// 3x display without paying for pixels the card cannot show.
const int thumbnailMaxEdge = 400;

/// Thumbnails are lossy JPEG, not WebP: the `image` package only encodes WebP
/// losslessly, which for a photograph comes out several times *larger* than a
/// quality-78 JPEG. Lossless would defeat the point of a thumbnail.
const int _thumbnailQuality = 78;

/// Image types the relay accepts, mirroring the bucket's allowed_mime_types and
/// the clipboard_items_mime_allowed constraint. All three lists must agree.
///
/// SVG is absent deliberately — it can carry script, and anything arriving from
/// a picker is untrusted input.
const Set<String> allowedImageMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
};

/// Raised when a picked file cannot be treated as an image.
class MediaEncodeException implements Exception {
  const MediaEncodeException(this.message);

  final String message;

  @override
  String toString() => 'MediaEncodeException: $message';
}

/// Turns picked image bytes into something the relay can carry.
///
/// Pure Dart on purpose. A native resizer would be faster, but its behaviour
/// would differ between Android and iOS, and iOS cannot currently be tested on
/// the development machine — identical code on both platforms is worth more
/// here than the milliseconds.
class MediaEncoder {
  const MediaEncoder._();

  /// Builds the list thumbnail for [original].
  ///
  /// Runs on a background isolate: decoding a 12-megapixel photo on the UI
  /// isolate drops frames for a visible moment.
  static Future<Uint8List> thumbnail(Uint8List original) {
    return compute(buildThumbnail, original);
  }

  /// The image's real type, read from its leading bytes.
  ///
  /// Never trusts the filename. A picker hands back whatever the user chose,
  /// and an extension is a claim, not evidence.
  static String? sniffMimeType(Uint8List bytes) {
    if (bytes.length < 12) return null;

    bool startsWith(List<int> magic, [int offset = 0]) {
      if (bytes.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[offset + i] != magic[i]) return false;
      }
      return true;
    }

    if (startsWith([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (startsWith([0x47, 0x49, 0x46, 0x38])) return 'image/gif';

    // RIFF....WEBP
    if (startsWith([0x52, 0x49, 0x46, 0x46]) &&
        startsWith([0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }

    // ....ftyp<brand> — the ISO base media container HEIC also uses.
    if (startsWith([0x66, 0x74, 0x79, 0x70], 4)) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (const {
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return 'image/heic';
      }
    }

    return null;
  }

  /// The file extension to store [mimeType] under.
  static String extensionFor(String mimeType) => switch (mimeType) {
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    _ => 'jpg',
  };
}

/// Decodes, uprights, downscales, and re-encodes [original] as a JPEG.
///
/// Top-level so it can cross an isolate boundary. Visible for testing, which is
/// why it is not private — the isolate hop is untestable in a unit test, the
/// resizing logic is not.
@visibleForTesting
Uint8List buildThumbnail(Uint8List original) {
  final decoded = img.decodeImage(original);
  if (decoded == null) {
    throw const MediaEncodeException(
      "That file could not be read as an image.",
    );
  }

  // Phone cameras record rotation in EXIF rather than rotating the pixels, so
  // without this a portrait photo thumbnails on its side.
  final upright = img.bakeOrientation(decoded);

  final longestEdge = upright.width > upright.height
      ? upright.width
      : upright.height;

  // Only ever shrink. Upscaling a small image would cost bytes and add nothing.
  final resized = longestEdge <= thumbnailMaxEdge
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? thumbnailMaxEdge : null,
          height: upright.height > upright.width ? thumbnailMaxEdge : null,
          interpolation: img.Interpolation.average,
        );

  return img.encodeJpg(resized, quality: _thumbnailQuality);
}
