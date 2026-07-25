/// The platform a device is running.
enum DevicePlatform { ios, android, macos, windows, linux }

/// The content type of a clipboard item.
///
/// [image] exists in the schema but nothing captures it yet.
enum ClipboardItemType { text, link, image }

/// A single clipboard entry synced from a device.
class ClipboardItem {
  const ClipboardItem({
    required this.id,
    required this.type,
    required this.content,
    required this.deviceName,
    required this.devicePlatform,
    required this.timestamp,
    this.isPinned = false,
  });

  /// Builds an item from a `clipboard_items` row.
  ///
  /// Tolerates unknown enum values rather than throwing: a row written by a
  /// newer client must not crash an older one.
  factory ClipboardItem.fromRow(Map<String, dynamic> row) {
    return ClipboardItem(
      id: row['id'] as String,
      type: _typeFrom(row['content_type'] as String?),
      content: row['content'] as String? ?? '',
      deviceName: row['device_name'] as String? ?? 'Unknown device',
      devicePlatform: _platformFrom(row['device_platform'] as String?),
      timestamp:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      isPinned: row['is_pinned'] as bool? ?? false,
    );
  }

  final String id;
  final ClipboardItemType type;

  /// Raw clipboard content: text/URL string, or filename for images.
  final String content;

  final String deviceName;
  final DevicePlatform devicePlatform;
  final DateTime timestamp;
  final bool isPinned;

  static ClipboardItemType _typeFrom(String? value) {
    return switch (value) {
      'link' => ClipboardItemType.link,
      'image' => ClipboardItemType.image,
      _ => ClipboardItemType.text,
    };
  }

  static DevicePlatform _platformFrom(String? value) {
    return switch (value) {
      'ios' => DevicePlatform.ios,
      'macos' => DevicePlatform.macos,
      'windows' => DevicePlatform.windows,
      'linux' => DevicePlatform.linux,
      _ => DevicePlatform.android,
    };
  }

  /// Whether [content] looks like a URL, deciding how it is stored and shown.
  ///
  /// Deliberately strict: a bare word with a dot in it is not a link, and only
  /// http(s) counts so a captured `javascript:` or `file:` string is never
  /// presented as something safe to open.
  static bool looksLikeLink(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return false;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    return uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
