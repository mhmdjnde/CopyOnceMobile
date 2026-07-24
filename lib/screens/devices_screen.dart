import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../models/clipboard_item.dart';
import '../models/device_info.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Shows connected devices and their sync status.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final devices = MockData.devices;
    final contentWidth = MediaQuery.sizeOf(context).width > 600
        ? 560.0
        : double.infinity;

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.m),
            children: [
              // Section header
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.s,
                ),
                child: Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint,
                    letterSpacing: 0.8,
                  ),
                ),
              ),

              // Device cards
              ...devices.map(
                (device) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: _DeviceCard(device: device),
                ),
              ),

              const SizedBox(height: AppSpacing.l),

              // Add device button
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add a Device'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.l),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final DeviceInfo device;

  IconData get _platformIcon => switch (device.platform) {
    DevicePlatform.ios => Icons.phone_iphone,
    DevicePlatform.android => Icons.phone_android,
    DevicePlatform.macos => Icons.laptop_mac,
    DevicePlatform.windows => Icons.desktop_windows,
    DevicePlatform.linux => Icons.computer,
  };

  String get _lastSeenLabel {
    if (device.isCurrentDevice) return 'This device';
    return 'Last seen ${MockData.formatTimestamp(device.lastSeen)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Row(
          children: [
            // Platform icon in colored circle
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: device.isCurrentDevice
                    ? AppColors.accentSubtle
                    : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _platformIcon,
                size: 22,
                color: device.isCurrentDevice
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
            ),

            const SizedBox(width: AppSpacing.m),

            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lastSeenLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),

            // Online indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: device.isCurrentDevice
                    ? AppColors.success
                    : AppColors.divider,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
