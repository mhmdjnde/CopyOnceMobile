import 'clipboard_item.dart';

/// A connected device that participates in clipboard sync.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.isCurrentDevice,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final DevicePlatform platform;

  /// True when this entry represents the device the app is currently running on.
  final bool isCurrentDevice;

  final DateTime lastSeen;
}
