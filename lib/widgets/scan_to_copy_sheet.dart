import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/clipboard_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/qr_payload.dart';

/// Shows one item as a QR code for someone else to scan.
///
/// Everything is encoded in the code itself, so this works with no account, no
/// app on the other phone, and no network — nothing is uploaded anywhere.
///
/// The code hides itself after [visibleFor]: it is displaying clipboard content
/// on a screen, and a QR left up is a QR that can be photographed.
class ScanToCopySheet extends StatefulWidget {
  const ScanToCopySheet({super.key, required this.item});

  final ClipboardItem item;

  /// How long the code stays on screen before hiding.
  static const visibleFor = Duration(seconds: 30);

  /// Opens the sheet for [item].
  static Future<void> show(BuildContext context, ClipboardItem item) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.background,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => ScanToCopySheet(item: item),
    );
  }

  @override
  State<ScanToCopySheet> createState() => _ScanToCopySheetState();
}

class _ScanToCopySheetState extends State<ScanToCopySheet> {
  Timer? _hideTimer;
  int _secondsLeft = ScanToCopySheet.visibleFor.inSeconds;
  bool _isHidden = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _hideTimer?.cancel();
    setState(() {
      _isHidden = false;
      _secondsLeft = ScanToCopySheet.visibleFor.inSeconds;
    });

    _hideTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        setState(() => _isHidden = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final payload = QrPayload.forItem(widget.item);
    final isWide = MediaQuery.sizeOf(context).width > 600;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          0,
          AppSpacing.l,
          AppSpacing.l,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWide ? 420.0 : double.infinity,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                payload.action.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                payload.action.scannerPromise,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.l),

              Center(
                child: _isHidden
                    ? _HiddenPlaceholder(onShowAgain: _startCountdown)
                    : _QrPanel(data: payload.data, secondsLeft: _secondsLeft),
              ),

              if (payload.isTruncated) ...[
                const SizedBox(height: AppSpacing.m),
                _Notice(
                  icon: Icons.content_cut_rounded,
                  color: context.colors.warning,
                  message:
                      'Only the first ${QrPayload.maxLength} characters fit in '
                      'a scannable code. Send the rest another way.',
                ),
              ],

              const SizedBox(height: AppSpacing.m),
              _Notice(
                icon: Icons.visibility_outlined,
                color: context.colors.textSecondary,
                message:
                    'Anyone who can see or photograph this code gets the '
                    'content. Nothing is uploaded — it lives in the code '
                    'itself.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.data, required this.secondsLeft});

  final String data;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            // Always white behind the code: scanners need the contrast, and the
            // beige app background is not reliable enough.
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.l),
            border: Border.all(color: context.colors.divider),
          ),
          child: QrImageView(
            data: data,
            size: 240,
            backgroundColor: AppColors.white,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: context.colors.primary,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: context.colors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          'Hides in ${secondsLeft}s',
          style: TextStyle(fontSize: 12, color: context.colors.textHint),
        ),
      ],
    );
  }
}

class _HiddenPlaceholder extends StatelessWidget {
  const _HiddenPlaceholder({required this.onShowAgain});

  final VoidCallback onShowAgain;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 272,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.l),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 28,
            color: context.colors.textHint,
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            'Code hidden',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          OutlinedButton(
            onPressed: onShowAgain,
            child: const Text('Show again'),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12, color: color, height: 1.4),
          ),
        ),
      ],
    );
  }
}
