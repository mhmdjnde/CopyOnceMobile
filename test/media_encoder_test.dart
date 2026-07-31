import 'dart:typed_data';

import 'package:copy_once/services/media_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A solid-colour test image at the requested dimensions.
Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 160, 120));
  return img.encodePng(image);
}

void main() {
  group('sniffMimeType', () {
    test('recognises a real PNG', () {
      expect(MediaEncoder.sniffMimeType(_png(8, 8)), 'image/png');
    });

    test('recognises a real JPEG', () {
      final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
      expect(MediaEncoder.sniffMimeType(jpeg), 'image/jpeg');
    });

    test('recognises GIF and WebP containers', () {
      final gif = Uint8List.fromList([
        0x47,
        0x49,
        0x46,
        0x38,
        0x39,
        0x61,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(MediaEncoder.sniffMimeType(gif), 'image/gif');

      final webp = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      expect(MediaEncoder.sniffMimeType(webp), 'image/webp');
    });

    test('recognises HEIC by its ftyp brand', () {
      final heic = Uint8List.fromList([
        0, 0, 0, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
      ]);
      expect(MediaEncoder.sniffMimeType(heic), 'image/heic');
    });

    test('refuses an SVG, whatever the file is called', () {
      // SVG can carry script. The picker filters by extension; this is the
      // check that actually holds.
      final svg = Uint8List.fromList(
        '<svg xmlns="http://www.w3.org/2000/svg">'.codeUnits,
      );
      final sniffed = MediaEncoder.sniffMimeType(svg);

      expect(sniffed, isNot('image/svg+xml'));
      expect(allowedImageMimeTypes.contains(sniffed), isFalse);
    });

    test('returns null for arbitrary bytes and for a truncated header', () {
      expect(
        MediaEncoder.sniffMimeType(Uint8List.fromList(List.filled(64, 0x42))),
        isNull,
      );
      expect(
        MediaEncoder.sniffMimeType(Uint8List.fromList([0xFF, 0xD8])),
        isNull,
      );
    });
  });

  group('buildThumbnail', () {
    test('shrinks the long edge to the cap and keeps aspect ratio', () {
      final thumb = buildThumbnail(_png(1600, 800));
      final decoded = img.decodeImage(thumb)!;

      expect(decoded.width, thumbnailMaxEdge);
      expect(decoded.height, thumbnailMaxEdge ~/ 2);
    });

    test('caps the height when the image is portrait', () {
      final thumb = buildThumbnail(_png(600, 1800));
      final decoded = img.decodeImage(thumb)!;

      expect(decoded.height, thumbnailMaxEdge);
      expect(decoded.width, lessThan(thumbnailMaxEdge));
    });

    test('never upscales an image already smaller than the cap', () {
      final thumb = buildThumbnail(_png(80, 60));
      final decoded = img.decodeImage(thumb)!;

      expect(decoded.width, 80);
      expect(decoded.height, 60);
    });

    test('emits JPEG, not lossless WebP', () {
      // The image package only encodes WebP losslessly, which for a photograph
      // is larger than the original. If this ever flips to WebP, thumbnails
      // stop being small — which is the entire reason they exist.
      final thumb = buildThumbnail(_png(1000, 1000));
      expect(MediaEncoder.sniffMimeType(thumb), 'image/jpeg');
    });

    test('a thumbnail is much smaller than the image it came from', () {
      final original = _png(2400, 1600);
      final thumb = buildThumbnail(original);
      expect(thumb.length, lessThan(original.length));
    });

    test('rejects bytes that are not an image', () {
      expect(
        () => buildThumbnail(Uint8List.fromList(List.filled(128, 7))),
        throwsA(isA<MediaEncodeException>()),
      );
    });
  });

  group('extensionFor', () {
    test('maps each allowed type to a sensible extension', () {
      expect(MediaEncoder.extensionFor('image/png'), 'png');
      expect(MediaEncoder.extensionFor('image/gif'), 'gif');
      expect(MediaEncoder.extensionFor('image/webp'), 'webp');
      expect(MediaEncoder.extensionFor('image/heic'), 'heic');
      expect(MediaEncoder.extensionFor('image/jpeg'), 'jpg');
    });
  });
}
