import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/clipboard_controller.dart';
import '../models/clipboard_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The small preview of a relayed image.
///
/// Fetches only the generated thumbnail, never the original: a list of ten
/// full-resolution photos would cost megabytes to scroll past, and the
/// original is what the download button is for.
class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.item,
    this.size = 64,
    this.radius = AppRadius.m,
  });

  final ClipboardItem item;
  final double size;
  final double radius;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list rebuilds as items arrive; only refetch when this card is
    // actually showing a different image.
    if (oldWidget.item.thumbPath != widget.item.thumbPath) _load();
  }

  void _load() {
    _bytes = context.read<ClipboardController>().thumbnailFor(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FutureBuilder<Uint8List?>(
          future: _bytes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ThumbnailFrame(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            final data = snapshot.data;
            if (data == null) {
              // An image whose thumbnail has already been reaped, or a
              // connection that dropped. Neither is worth an error banner.
              return const _ThumbnailFrame(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 20,
                  color: AppColors.textHint,
                ),
              );
            }

            return Image.memory(
              data,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const _ThumbnailFrame(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: AppColors.textHint,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Neutral placeholder ground, so loading and failure states occupy exactly the
/// space the image will.
class _ThumbnailFrame extends StatelessWidget {
  const _ThumbnailFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppRadius.m),
      ),
      child: Center(child: child),
    );
  }
}

/// "Expires in 3h", or "Delivered" once the relay is done.
///
/// Not a live countdown: a ticking timer on every card in a list would rebuild
/// the whole thing every second to save the user reading a number that changes
/// slowly. It refreshes when the list does.
class MediaExpiryChip extends StatelessWidget {
  const MediaExpiryChip({super.key, required this.item});

  final ClipboardItem item;

  @override
  Widget build(BuildContext context) {
    final left = item.timeLeft;
    if (left == null) return const SizedBox.shrink();

    final (label, color) = switch (left) {
      Duration.zero => ('Delivered', AppColors.success),
      final d when d.inHours >= 1 => ('${d.inHours}h left', AppColors.textHint),
      final d when d.inMinutes >= 1 => (
        '${d.inMinutes}m left',
        AppColors.warning,
      ),
      _ => ('Expiring', AppColors.warning),
    };

    return Semantics(
      label: label == 'Delivered'
          ? 'Delivered to all devices, clearing shortly'
          : 'Image expires in $label',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.s),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              label == 'Delivered'
                  ? Icons.check_circle_outline_rounded
                  : Icons.schedule_rounded,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
