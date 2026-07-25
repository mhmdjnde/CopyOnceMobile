/// Per-account sync preferences, mirroring `public.user_settings`.
///
/// Stored server-side rather than on the device so the same choices apply
/// everywhere the account is signed in.
class SyncSettings {
  const SyncSettings({
    this.autoSync = true,
    this.wifiOnly = false,
    this.syncAlerts = true,
    this.retentionDays = 7,
    this.captureText = true,
    this.captureLinks = true,
  });

  factory SyncSettings.fromRow(Map<String, dynamic> row) {
    return SyncSettings(
      autoSync: row['auto_sync'] as bool? ?? true,
      wifiOnly: row['wifi_only'] as bool? ?? false,
      syncAlerts: row['sync_alerts'] as bool? ?? true,
      retentionDays: row['retention_days'] as int? ?? 7,
      captureText: row['capture_text'] as bool? ?? true,
      captureLinks: row['capture_links'] as bool? ?? true,
    );
  }

  /// Retention choices the picker offers. Must match the database's
  /// `retention_days` check constraint; 0 means keep until deleted by hand.
  static const List<int> retentionChoices = [1, 7, 30, 90, 365, 0];

  final bool autoSync;
  final bool wifiOnly;
  final bool syncAlerts;
  final int retentionDays;
  final bool captureText;
  final bool captureLinks;

  /// Human label for a retention value, used by the picker and the summary row.
  static String retentionLabel(int days) => switch (days) {
    0 => 'Keep forever',
    1 => '1 day',
    7 => '7 days',
    30 => '30 days',
    90 => '90 days',
    365 => '1 year',
    _ => '$days days',
  };

  String get retentionSummary => retentionLabel(retentionDays);

  Map<String, dynamic> toRow() => {
    'auto_sync': autoSync,
    'wifi_only': wifiOnly,
    'sync_alerts': syncAlerts,
    'retention_days': retentionDays,
    'capture_text': captureText,
    'capture_links': captureLinks,
  };

  SyncSettings copyWith({
    bool? autoSync,
    bool? wifiOnly,
    bool? syncAlerts,
    int? retentionDays,
    bool? captureText,
    bool? captureLinks,
  }) {
    return SyncSettings(
      autoSync: autoSync ?? this.autoSync,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      syncAlerts: syncAlerts ?? this.syncAlerts,
      retentionDays: retentionDays ?? this.retentionDays,
      captureText: captureText ?? this.captureText,
      captureLinks: captureLinks ?? this.captureLinks,
    );
  }

  /// Whether an item of this type should be captured at all.
  bool allows(bool isLink) => isLink ? captureLinks : captureText;
}
