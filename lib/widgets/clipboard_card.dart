import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../models/clipboard_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'device_badge.dart';

/// Card representing a single clipboard item.
/// Shows type, content preview, source device, timestamp, and a copy action.
class ClipboardCard extends StatefulWidget {
  const ClipboardCard({super.key, required this.item, required this.onCopy});

  final ClipboardItem item;

  /// Called when the user taps the copy button.
  final VoidCallback onCopy;

  @override
  State<ClipboardCard> createState() => _ClipboardCardState();
}

class _ClipboardCardState extends State<ClipboardCard> {
  bool _copied = false;

  void _handleCopy() {
    if (_copied) return;
    setState(() => _copied = true);
    widget.onCopy();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  ({Color bg, Color fg, IconData icon, String label}) get _typeInfo =>
      switch (widget.item.type) {
        ClipboardItemType.text => (
          bg: AppColors.primarySubtle,
          fg: AppColors.primary,
          icon: Icons.notes_rounded,
          label: 'Text',
        ),
        ClipboardItemType.link => (
          bg: AppColors.linkSubtle,
          fg: AppColors.link,
          icon: Icons.link_rounded,
          label: 'Link',
        ),
        ClipboardItemType.image => (
          bg: AppColors.accentImageSubtle,
          fg: AppColors.accent,
          icon: Icons.image_outlined,
          label: 'Image',
        ),
      };

  @override
  Widget build(BuildContext context) {
    final info = _typeInfo;

    return Card(
      child: InkWell(
        onTap: _handleCopy,
        borderRadius: BorderRadius.circular(AppRadius.l),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(
                children: [
                  // Type badge
                  Semantics(
                    label: '${info.label} item',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: info.bg,
                        borderRadius: BorderRadius.circular(AppRadius.s),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(info.icon, size: 12, color: info.fg),
                          const SizedBox(width: 4),
                          Text(
                            info.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: info.fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.item.isPinned) ...[
                    const SizedBox(width: AppSpacing.s),
                    const Tooltip(
                      message: 'Pinned',
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Copy button
                  Semantics(
                    button: true,
                    label: _copied ? 'Copied' : 'Copy to clipboard',
                    child: GestureDetector(
                      onTap: _handleCopy,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _copied
                              ? AppColors.successSubtle
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.s),
                        ),
                        child: Icon(
                          _copied ? Icons.check_rounded : Icons.copy_outlined,
                          size: 16,
                          color: _copied
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.s + AppSpacing.xs),

              // ── Content preview ──────────────────────────────────────────
              _ContentPreview(item: widget.item),

              const SizedBox(height: AppSpacing.s + AppSpacing.xs),

              // ── Footer: device + timestamp ────────────────────────────────
              Row(
                children: [
                  DeviceBadge(
                    deviceName: widget.item.deviceName,
                    platform: widget.item.devicePlatform,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  const Text(
                    '·',
                    style: TextStyle(color: AppColors.textHint, fontSize: 11),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Text(
                    MockData.formatTimestamp(widget.item.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the appropriate content preview for a clipboard item type.
class _ContentPreview extends StatelessWidget {
  const _ContentPreview({required this.item});

  final ClipboardItem item;

  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      ClipboardItemType.text => Text(
        item.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
      ),
      ClipboardItemType.link => _LinkPreview(url: item.content),
      ClipboardItemType.image => _ImagePreview(filename: item.content),
    };
  }
}

class _LinkPreview extends StatelessWidget {
  const _LinkPreview({required this.url});

  final String url;

  String get _domain {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _domain,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.link,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textHint),
        ),
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.filename});

  final String filename;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.m),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Icon(
            Icons.image_outlined,
            color: AppColors.textHint,
            size: 24,
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            filename,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
