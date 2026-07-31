import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../models/clipboard_item.dart';
import '../screens/media_viewer_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'device_badge.dart';
import 'media_thumbnail.dart';
import 'scan_to_copy_sheet.dart';

/// Card representing a single clipboard item.
///
/// Shows type, content preview, source device, timestamp, a copy action, and a
/// QR action for handing the item to someone who has neither the app nor an
/// account.
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

  /// Tapping an image opens it; tapping anything else copies it.
  ///
  /// There is nothing useful to put on the clipboard for an image — the stored
  /// content is only its filename — so the tap does the thing the user came
  /// for instead.
  void _handleTap() {
    if (widget.item.isImage) {
      MediaViewerScreen.open(context, widget.item);
    } else {
      _handleCopy();
    }
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
        onTap: _handleTap,
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
                  if (widget.item.isImage) ...[
                    const SizedBox(width: AppSpacing.s),
                    MediaExpiryChip(item: widget.item),
                  ],
                  const Spacer(),
                  // Share by QR: lets someone with no account and no app take
                  // this item off the screen with their camera.
                  //
                  // Not offered for images — a QR carries a few hundred bytes,
                  // and the only thing that would fit is the filename.
                  if (!widget.item.isImage)
                    Semantics(
                      button: true,
                      label: 'Show QR code to share',
                      child: GestureDetector(
                        onTap: () => ScanToCopySheet.show(context, widget.item),
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: AppSpacing.s),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.s),
                          ),
                          child: const Icon(
                            Icons.qr_code_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  // Open, or copy. An image has nothing to put on the clipboard.
                  Semantics(
                    button: true,
                    label: widget.item.isImage
                        ? 'Open image full screen'
                        : (_copied ? 'Copied' : 'Copy to clipboard'),
                    child: GestureDetector(
                      onTap: _handleTap,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _copied && !widget.item.isImage
                              ? AppColors.successSubtle
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.s),
                        ),
                        child: Icon(
                          switch ((widget.item.isImage, _copied)) {
                            (true, _) => Icons.open_in_full_rounded,
                            (false, true) => Icons.check_rounded,
                            (false, false) => Icons.copy_outlined,
                          },
                          size: 16,
                          color: _copied && !widget.item.isImage
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
      ClipboardItemType.image => _ImagePreview(item: item),
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
  const _ImagePreview({required this.item});

  final ClipboardItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MediaThumbnail(item: item, size: 56),
        const SizedBox(width: AppSpacing.s + AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (item.readableSize.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '${item.readableSize} · tap to open',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
