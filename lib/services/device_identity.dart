import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/clipboard_item.dart';

/// Identifies this installation so synced items can say where they came from.
///
/// The id is random and generated on first launch, held in platform-secure
/// storage. Deliberately *not* a hardware identifier: a device id that survived
/// reinstalls would let two accounts on the same handset be correlated, which is
/// exactly the kind of linkage a clipboard app should not enable.
class DeviceIdentity {
  DeviceIdentity({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _installIdKey = 'copyonce_install_id';

  /// Host side lives in MainActivity.kt.
  static const _channel = MethodChannel('copyonce/device');

  final FlutterSecureStorage _storage;

  String? _cachedInstallId;
  String? _cachedDeviceName;

  /// Stable id for this install, created on first use.
  Future<String> installId() async {
    final cached = _cachedInstallId;
    if (cached != null) return cached;

    final existing = await _storage.read(key: _installIdKey);
    if (existing != null && existing.length >= 8) {
      _cachedInstallId = existing;
      return existing;
    }

    final generated = _randomId();
    await _storage.write(key: _installIdKey, value: generated);
    _cachedInstallId = generated;
    return generated;
  }

  /// Name shown next to synced items — the one the owner recognises.
  ///
  /// Android needs the platform channel: `Platform.localHostname` returns
  /// "localhost" there, which is why every device used to be labelled
  /// "Android device". Desktops report a real hostname, so they use that.
  Future<String> deviceName() async {
    final cached = _cachedDeviceName;
    if (cached != null) return cached;

    final resolved = await _resolveDeviceName();
    _cachedDeviceName = resolved;
    return resolved;
  }

  Future<String> _resolveDeviceName() async {
    if (kIsWeb) return 'Web browser';

    if (platform == DevicePlatform.android) {
      try {
        final name = await _channel.invokeMethod<String>('getDeviceName');
        if (name != null && name.trim().isNotEmpty) return name.trim();
      } on PlatformException {
        // Fall through to the generic label rather than failing a sync.
      } on MissingPluginException {
        // Older build of the host app without the channel.
      }
    }

    try {
      final host = Platform.localHostname;
      if (host.isNotEmpty && host != 'localhost') return host;
    } on Object {
      // Some platforms deny hostname lookups; the fallback below is fine.
    }

    return switch (platform) {
      DevicePlatform.android => 'Android device',
      DevicePlatform.ios => 'iPhone',
      DevicePlatform.macos => 'Mac',
      DevicePlatform.windows => 'Windows PC',
      DevicePlatform.linux => 'Linux PC',
    };
  }

  DevicePlatform get platform {
    if (kIsWeb) return DevicePlatform.linux;
    if (Platform.isAndroid) return DevicePlatform.android;
    if (Platform.isIOS) return DevicePlatform.ios;
    if (Platform.isMacOS) return DevicePlatform.macos;
    if (Platform.isWindows) return DevicePlatform.windows;
    return DevicePlatform.linux;
  }

  static String _randomId() {
    // Random.secure so the id cannot be guessed from the launch time.
    final random = Random.secure();
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      24,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}
