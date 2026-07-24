/// The platform a device is running.
enum DevicePlatform { ios, android, macos, windows, linux }

/// The content type of a clipboard item.
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

  final String id;
  final ClipboardItemType type;

  /// Raw clipboard content: text/URL string, or filename for images.
  final String content;

  final String deviceName;
  final DevicePlatform devicePlatform;
  final DateTime timestamp;
  final bool isPinned;
}
