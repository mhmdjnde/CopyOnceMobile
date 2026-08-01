import 'package:flutter/material.dart';
import '../models/clipboard_item.dart';
import '../theme/app_colors.dart';

/// Small inline badge showing a device name and its platform icon.
/// Used on clipboard cards and in the devices screen.
class DeviceBadge extends StatelessWidget {
  const DeviceBadge({
    super.key,
    required this.deviceName,
    required this.platform,
  });

  final String deviceName;
  final DevicePlatform platform;

  IconData get _icon => switch (platform) {
    DevicePlatform.ios => Icons.phone_iphone,
    DevicePlatform.android => Icons.phone_android,
    DevicePlatform.macos => Icons.laptop_mac,
    DevicePlatform.windows => Icons.desktop_windows,
    DevicePlatform.linux => Icons.computer,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_icon, size: 12, color: context.colors.textHint),
        const SizedBox(width: 3),
        Text(
          deviceName,
          style: TextStyle(
            fontSize: 11,
            color: context.colors.textHint,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
