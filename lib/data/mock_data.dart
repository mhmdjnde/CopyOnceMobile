import '../models/clipboard_item.dart';
import '../models/device_info.dart';

/// Static mock data for the CopyOnce prototype.
/// No real clipboard, network, or storage is used.
abstract class MockData {
  static final List<ClipboardItem> clipboardItems = [
    ClipboardItem(
      id: '1',
      type: ClipboardItemType.text,
      content:
          'Meeting at 3pm tomorrow with the design team. Bring the wireframes and the latest build.',
      deviceName: 'iPhone 15 Pro',
      devicePlatform: DevicePlatform.ios,
      timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      isPinned: true,
    ),
    ClipboardItem(
      id: '2',
      type: ClipboardItemType.link,
      content: 'https://www.figma.com/design/abc123/copyonce-mockup',
      deviceName: 'MacBook Pro',
      devicePlatform: DevicePlatform.macos,
      timestamp: DateTime.now().subtract(const Duration(minutes: 17)),
    ),
    ClipboardItem(
      id: '3',
      type: ClipboardItemType.image,
      content: 'Screenshot 2025-07-24 at 14.32.11.png',
      deviceName: 'iPhone 15 Pro',
      devicePlatform: DevicePlatform.ios,
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    ClipboardItem(
      id: '4',
      type: ClipboardItemType.text,
      content: 'flutter pub get && flutter run --debug',
      deviceName: 'MacBook Pro',
      devicePlatform: DevicePlatform.macos,
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    ClipboardItem(
      id: '5',
      type: ClipboardItemType.link,
      content: 'https://docs.flutter.dev/ui/adaptive-responsive',
      deviceName: 'Pixel 8',
      devicePlatform: DevicePlatform.android,
      timestamp: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    ClipboardItem(
      id: '6',
      type: ClipboardItemType.text,
      content: 'johndoe@example.com',
      deviceName: 'MacBook Pro',
      devicePlatform: DevicePlatform.macos,
      timestamp: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    ClipboardItem(
      id: '7',
      type: ClipboardItemType.image,
      content: 'profile_photo_final.jpg',
      deviceName: 'Pixel 8',
      devicePlatform: DevicePlatform.android,
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
    ),
    ClipboardItem(
      id: '8',
      type: ClipboardItemType.text,
      content: 'Track #KL-2094 — Production deploy failed on EU region.',
      deviceName: 'MacBook Pro',
      devicePlatform: DevicePlatform.macos,
      timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
    ),
  ];

  static final List<DeviceInfo> devices = [
    DeviceInfo(
      id: 'd1',
      name: 'iPhone 15 Pro',
      platform: DevicePlatform.ios,
      isCurrentDevice: true,
      lastSeen: DateTime.now(),
    ),
    DeviceInfo(
      id: 'd2',
      name: 'MacBook Pro',
      platform: DevicePlatform.macos,
      isCurrentDevice: false,
      lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    DeviceInfo(
      id: 'd3',
      name: 'Pixel 8',
      platform: DevicePlatform.android,
      isCurrentDevice: false,
      lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];

  /// Human-readable relative time label.
  static String formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}
