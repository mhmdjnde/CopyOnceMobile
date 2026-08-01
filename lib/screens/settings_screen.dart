import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/auth_controller.dart';
import '../controllers/clipboard_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/sync_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'security/security_screen.dart';

/// App settings. Every control here writes through to the account, so choices
/// follow the user to their other devices.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Lets the user pick how long items are kept, then applies it immediately so
  /// shortening the window takes effect now rather than on next launch.
  Future<void> _pickRetention(int current) async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Keep items for'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.l,
              0,
              AppSpacing.l,
              AppSpacing.m,
            ),
            child: Text(
              'Anything older is deleted from your account automatically. '
              'Pinned items are always kept.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          RadioGroup<int>(
            groupValue: current,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              children: [
                for (final days in SyncSettings.retentionChoices)
                  RadioListTile<int>(
                    value: days,
                    title: Text(SyncSettings.retentionLabel(days)),
                    activeColor: context.colors.accent,
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;

    final settings = context.read<SettingsController>();
    await settings.setRetentionDays(chosen);
    if (!mounted) return;

    final removed = await context.read<ClipboardController>().applyRetention(
      settings.settings ?? const SyncSettings(),
    );
    if (!mounted || removed == 0) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed $removed item${removed == 1 ? '' : 's'} past the new limit.',
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear synced history?'),
        content: const Text(
          'Deletes every item CopyOnce has stored for your account, on all '
          'devices. This cannot be undone.\n\n'
          "Your phone's own clipboard is not touched — whatever you last "
          'copied can still be pasted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (!(shouldClear ?? false) || !mounted) return;

    final clipboard = context.read<ClipboardController>();
    final cleared = await clipboard.clearHistory();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleared
              ? 'Synced history cleared.'
              : clipboard.errorMessage ?? 'Could not clear history.',
        ),
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final auth = context.read<AuthController>();
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your synced clipboard stays in your account. '
          'You will need to sign in again on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldSignOut ?? false) await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final contentWidth = MediaQuery.sizeOf(context).width > 600
        ? 560.0
        : double.infinity;
    final auth = context.watch<AuthController>();
    final user = auth.currentUser;
    final settingsController = context.watch<SettingsController>();
    final settings = settingsController.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.m),
            children: [
              // ── Account ───────────────────────────────────────────────────
              _SectionHeader(label: 'Account'),
              _SettingsCard(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: context.colors.accentSubtle,
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: context.colors.accent,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      user?.userMetadata?['display_name'] as String? ??
                          'Signed in',
                    ),
                    subtitle: Text(user?.email ?? ''),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      Icons.shield_outlined,
                      color: context.colors.textSecondary,
                      size: 20,
                    ),
                    title: const Text('Security'),
                    subtitle: const Text('Password and two-factor'),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: context.colors.textHint,
                      size: 18,
                    ),
                    onTap: () =>
                        Navigator.of(context).push(SecurityScreen.route()),
                  ),
                  const Divider(),
                  ListTile(
                    onTap: auth.isBusy ? null : _confirmSignOut,
                    title: Text(
                      'Sign out',
                      style: TextStyle(color: context.colors.error),
                    ),
                    trailing: auth.isBusy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.logout_rounded,
                            color: context.colors.error,
                            size: 18,
                          ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.l),

              // ── Sync ──────────────────────────────────────────────────────
              _SectionHeader(label: 'Sync'),
              if (settings == null)
                const _SettingsCard(
                  children: [
                    ListTile(
                      title: Text('Loading your settings…'),
                      trailing: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                )
              else ...[
                _SettingsCard(
                  children: [
                    SwitchListTile(
                      value: settings.autoSync,
                      onChanged: settingsController.setAutoSync,
                      title: const Text('Auto-sync'),
                      subtitle: const Text(
                        'Save what you copy when CopyOnce opens',
                      ),
                      activeThumbColor: context.colors.accent,
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: settings.wifiOnly,
                      onChanged: settings.autoSync
                          ? settingsController.setWifiOnly
                          : null,
                      title: const Text('Wi-Fi only'),
                      subtitle: const Text('Do not sync on mobile data'),
                      activeThumbColor: context.colors.accent,
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.l),

                // ── What to capture ─────────────────────────────────────────
                _SectionHeader(label: 'What to capture'),
                _SettingsCard(
                  children: [
                    SwitchListTile(
                      value: settings.captureText,
                      onChanged: settingsController.setCaptureText,
                      title: const Text('Text'),
                      subtitle: const Text('Plain text you copy'),
                      activeThumbColor: context.colors.accent,
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: settings.captureLinks,
                      onChanged: settingsController.setCaptureLinks,
                      title: const Text('Links'),
                      subtitle: const Text('Web addresses you copy'),
                      activeThumbColor: context.colors.accent,
                    ),
                    const Divider(),
                    ListTile(
                      title: Text(
                        'Images',
                        style: TextStyle(color: context.colors.textHint),
                      ),
                      subtitle: Text(
                        'Not synced yet — screenshots and images are ignored',
                      ),
                      trailing: Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: context.colors.textHint,
                      ),
                      enabled: false,
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.l),

                // ── Notifications ───────────────────────────────────────────
                _SectionHeader(label: 'Notifications'),
                _SettingsCard(
                  children: [
                    SwitchListTile(
                      value: settings.syncAlerts,
                      onChanged: settingsController.setSyncAlerts,
                      title: const Text('Sync alerts'),
                      subtitle: const Text(
                        'Tell me when something is saved or arrives',
                      ),
                      activeThumbColor: context.colors.accent,
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.l),

                // ── Privacy ─────────────────────────────────────────────────
                _SectionHeader(label: 'Privacy'),
                _SettingsCard(
                  children: [
                    ListTile(
                      onTap: () => _pickRetention(settings.retentionDays),
                      title: const Text('Retention period'),
                      subtitle: const Text(
                        'How long CopyOnce keeps an item before deleting it. '
                        'Shorter means less of your clipboard sitting on a '
                        'server.',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            settings.retentionSummary,
                            style: TextStyle(color: context.colors.textHint),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: context.colors.textHint,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      onTap: _confirmClearHistory,
                      title: Text(
                        'Clear synced history',
                        style: TextStyle(color: context.colors.error),
                      ),
                      subtitle: const Text(
                        "Deletes stored items only — your phone's clipboard is "
                        'left alone',
                      ),
                      trailing: Icon(
                        Icons.delete_outline_rounded,
                        color: context.colors.error,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ],

              if (settingsController.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.m),
                  child: Text(
                    settingsController.errorMessage!,
                    style: TextStyle(color: context.colors.error, fontSize: 13),
                  ),
                ),

              const SizedBox(height: AppSpacing.l),

              // ── About ─────────────────────────────────────────────────────
              _SectionHeader(label: 'About'),
              _SettingsCard(
                children: [
                  ListTile(
                    title: Text('Version'),
                    trailing: Text(
                      '1.0.0',
                      style: TextStyle(color: context.colors.textHint),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    onTap: () {},
                    title: const Text('Terms of Service'),
                    trailing: Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: context.colors.textHint,
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    onTap: () {},
                    title: const Text('Privacy Policy'),
                    trailing: Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: context.colors.textHint,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.s),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.colors.textHint,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(child: Column(children: children));
  }
}
