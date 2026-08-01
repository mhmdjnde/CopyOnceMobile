import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';

import '../controllers/clipboard_controller.dart';
import '../models/clipboard_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Full-resolution view of a relayed image, with a save-to-gallery action.
///
/// Opening this screen is what marks the image as received on this device: the
/// original is downloaded here, and once every device has pulled it the relay
/// releases it. That is the whole point of the feature, but it does mean the
/// image may disappear from the list shortly after you look at it — so the
/// bytes are held in this screen's state and the download button reuses them
/// rather than fetching again.
/// The viewer's ground, fixed in both themes.
///
/// An image reads truer against neutral dark, and a photo that sat on a beige
/// page in light mode and a black one at night would look like two different
/// photos. This is the one screen that does not follow the palette.
const Color _viewerBackdrop = Color(0xFF141814);

class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({super.key, required this.item});

  final ClipboardItem item;

  static Future<void> open(BuildContext context, ClipboardItem item) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaViewerScreen(item: item),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = context.read<ClipboardController>();
    final bytes = await controller.openOriginal(widget.item);
    if (!mounted) return;

    setState(() {
      _bytes = bytes;
      _error = bytes == null
          ? (controller.errorMessage ?? 'That image could not be loaded.')
          : null;
    });
  }

  /// Saves the already-downloaded bytes to the device's photo library.
  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null || _saving) return;

    setState(() => _saving = true);

    try {
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          _report('CopyOnce needs permission to save to your photos.');
          return;
        }
      }

      await Gal.putImageBytes(bytes, name: _saveName);
      _report('Saved to your photos');
    } on GalException catch (e) {
      // The plugin's own message names the failure (access, not enough space,
      // unsupported format) without echoing any image data.
      _report('Could not save: ${e.type.message}');
    } on Object {
      _report('Could not save that image.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Gallery filename: the original name without its extension, since the
  /// platform appends its own.
  String get _saveName {
    final name = widget.item.content;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return base.isEmpty ? 'CopyOnce' : base;
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.colors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.m),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      // Dark ground: an image reads truer against neutral black than against
      // the app's warm beige, and this is the one screen that is entirely image.
      backgroundColor: _viewerBackdrop,
      appBar: AppBar(
        backgroundColor: _viewerBackdrop,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: Text(
          item.content,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, color: AppColors.white),
        ),
        actions: [
          if (_bytes != null)
            Semantics(
              button: true,
              label: 'Save to photos at full resolution',
              child: IconButton(
                onPressed: _saving ? null : _save,
                tooltip: 'Save to photos',
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: _buildBody())),
          _MediaFooter(item: item, byteCount: _bytes?.length),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _ViewerError(message: _error!, onRetry: _load);
    }

    final bytes = _bytes;
    if (bytes == null) {
      return const CircularProgressIndicator(color: AppColors.white);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // On a wide window an image pinned to the full width becomes a mural.
        // Cap it so it stays a picture on a desk as well as in a hand.
        final maxWidth = constraints.maxWidth > 900
            ? 900.0
            : constraints.maxWidth;

        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _ViewerError(
                message: 'That image could not be displayed.',
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Filename, size, source device, and how long the relay will hold it.
class _MediaFooter extends StatelessWidget {
  const _MediaFooter({required this.item, this.byteCount});

  final ClipboardItem item;
  final int? byteCount;

  @override
  Widget build(BuildContext context) {
    final left = item.timeLeft;

    final note = switch (left) {
      null => null,
      Duration.zero =>
        'Every device has this image now, so CopyOnce is letting it go.',
      final d when d.inHours >= 1 =>
        'Clears in ${d.inHours}h, or as soon as your other devices have it.',
      final d =>
        'Clears in ${d.inMinutes}m, or as soon as your other devices have it.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.m),
      color: _viewerBackdrop,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.devices_rounded,
                  size: 13,
                  color: AppColors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Flexible(
                  child: Text(
                    item.deviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ),
                if (item.readableSize.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.s),
                  Text(
                    '· ${item.readableSize}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                note,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 40,
            color: AppColors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.white.withValues(alpha: 0.8),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.l),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.white,
                side: BorderSide(color: AppColors.white.withValues(alpha: 0.4)),
              ),
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
