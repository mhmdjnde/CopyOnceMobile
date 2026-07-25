/// App-level view of two-factor authentication, so screens never handle
/// Supabase SDK types.
library;

/// A TOTP factor that has been created but not yet proven.
///
/// Holds enrollment secrets: never log this, never persist it. It is discarded
/// as soon as the user confirms a code or abandons setup.
class TotpEnrollment {
  const TotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.otpauthUri,
  });

  final String factorId;

  /// Base32 secret, shown only for manual entry when a QR cannot be scanned.
  final String secret;

  /// `otpauth://` URI the QR code encodes.
  final String otpauthUri;

  /// The secret in groups of four, which is far easier to type without slips.
  String get formattedSecret {
    final groups = <String>[];
    for (var i = 0; i < secret.length; i += 4) {
      groups.add(secret.substring(i, (i + 4).clamp(0, secret.length)));
    }
    return groups.join(' ');
  }
}

/// Whether the account currently has a verified second factor.
class TwoFactorStatus {
  const TwoFactorStatus({
    required this.isEnabled,
    this.factorId,
    this.enrolledAt,
  });

  const TwoFactorStatus.disabled()
    : isEnabled = false,
      factorId = null,
      enrolledAt = null;

  final bool isEnabled;

  /// Id of the verified factor, needed to disable it.
  final String? factorId;

  final DateTime? enrolledAt;
}
