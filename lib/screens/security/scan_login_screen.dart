import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// Where the sign-in endpoints live.
///
/// Overridable so a debug build can point at a local server:
/// `--dart-define=COPYONCE_WEB_ORIGIN=http://10.0.2.2:3000`
const String _webOrigin = String.fromEnvironment(
  'COPYONCE_WEB_ORIGIN',
  defaultValue: 'https://copyonce.vercel.app',
);

/// Scans a sign-in code shown on another device, and approves it.
///
/// The phone never hands over its own session. It proves who it is with its
/// access token, and the server mints a separate session for the browser — so
/// approving here does not give the other device this device's credentials.
///
/// Approval is deliberately a second, explicit step. A code scanned by accident,
/// or one a stranger asks you to point your camera at, must not sign anybody in
/// on its own — that is the whole attack this flow has to survive.
class ScanLoginScreen extends StatefulWidget {
  const ScanLoginScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ScanLoginScreen()));
  }

  @override
  State<ScanLoginScreen> createState() => _ScanLoginScreenState();
}

enum _Stage { scanning, confirming, sending, done, failed }

class _ScanLoginScreenState extends State<ScanLoginScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  _Stage _stage = _Stage.scanning;
  String? _token;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Pulls the token out of a scanned value.
  ///
  /// The QR carries `https://<origin>/link#<token>` so a plain camera app does
  /// something sensible with it too. Only codes from the expected origin are
  /// accepted — anything else is somebody else's QR.
  String? _tokenFrom(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;

    final expected = Uri.parse(_webOrigin);
    if (uri.host != expected.host) return null;
    if (uri.path != '/link') return null;

    final token = uri.fragment;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(token) ? token : null;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_stage != _Stage.scanning) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;

      final token = _tokenFrom(value);
      if (token == null) continue;

      _controller.stop();
      setState(() {
        _token = token;
        _stage = _Stage.confirming;
      });
      return;
    }
  }

  Future<void> _approve() async {
    final token = _token;
    if (token == null) return;

    setState(() => _stage = _Stage.sending);

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() {
        _stage = _Stage.failed;
        _message = 'Sign in on this device first.';
      });
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_webOrigin/api/qr/approve'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() => _stage = _Stage.done);
        return;
      }

      setState(() {
        _stage = _Stage.failed;
        _message = switch (response.statusCode) {
          410 => 'That code has expired. Ask the other device for a new one.',
          401 => 'Sign in on this device first.',
          503 => 'Sign-in by code is not set up on the server yet.',
          _ => 'That did not work. Try scanning again.',
        };
      });
    } on Object {
      // Deliberately drops the raw error: it can echo the request, and the
      // request carries an access token.
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _message = 'Could not reach CopyOnce. Check your connection.';
      });
    }
  }

  void _rescan() {
    setState(() {
      _stage = _Stage.scanning;
      _token = null;
      _message = null;
    });
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan to sign in')),
      body: switch (_stage) {
        _Stage.scanning => _ScannerView(
          controller: _controller,
          onDetect: _onDetect,
        ),
        _Stage.confirming => _Confirm(onApprove: _approve, onCancel: _rescan),
        _Stage.sending => const Center(child: CircularProgressIndicator()),
        _Stage.done => _Result(
          icon: Icons.check_circle_outline_rounded,
          tone: context.colors.success,
          title: 'Signed in',
          body: 'The other device is signing in now. You can close this.',
          actionLabel: 'Done',
          onAction: () => Navigator.of(context).pop(),
        ),
        _Stage.failed => _Result(
          icon: Icons.error_outline_rounded,
          tone: context.colors.error,
          title: 'Not approved',
          body: _message ?? 'That did not work.',
          actionLabel: 'Scan again',
          onAction: _rescan,
        ),
      },
    );
  }
}

class _ScannerView extends StatelessWidget {
  const _ScannerView({required this.controller, required this.onDetect});

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: controller,
          onDetect: onDetect,
          errorBuilder: (context, error) => _Result(
            icon: Icons.no_photography_outlined,
            tone: context.colors.error,
            title: 'No camera',
            body:
                'CopyOnce needs camera access to scan a sign-in code. You can '
                'allow it in your device settings.',
            actionLabel: 'Go back',
            onAction: () => Navigator.of(context).pop(),
          ),
        ),
        // A window over the preview, so it is obvious where to aim.
        IgnorePointer(
          child: Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.white, width: 3),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.l),
            color: AppColors.black.withValues(alpha: 0.55),
            child: SafeArea(
              top: false,
              child: Text(
                'Open CopyOnce on the other device and choose "Sign in with '
                'your phone", then point the camera at the code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The moment that makes this safe.
///
/// Scanning is passive — a camera can be pointed at a code by accident, or by
/// someone else's suggestion. Signing in only happens when the owner reads this
/// and says yes.
class _Confirm extends StatelessWidget {
  const _Confirm({required this.onApprove, required this.onCancel});

  final VoidCallback onApprove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.laptop_rounded, size: 48, color: context.colors.accent),
          const SizedBox(height: AppSpacing.l),
          Text(
            'Sign in on that device?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'It will get access to your whole clipboard. Only approve this if '
            'the code is on a screen you are looking at right now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onApprove,
              child: const Text('Yes, sign in'),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: tone),
          const SizedBox(height: AppSpacing.l),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
