import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// App settings screen (mock UI — no real settings are persisted).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoSync = true;
  bool _wifiOnly = false;
  bool _notifications = true;

  @override
  Widget build(BuildContext context) {
    final contentWidth = MediaQuery.sizeOf(context).width > 600
        ? 560.0
        : double.infinity;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.m),
            children: [
              // ── Sync ──────────────────────────────────────────────────────
              _SectionHeader(label: 'Sync'),
              _SettingsCard(
                children: [
                  SwitchListTile(
                    value: _autoSync,
                    onChanged: (v) => setState(() => _autoSync = v),
                    title: const Text('Auto-sync'),
                    subtitle: const Text('Sync clipboard automatically'),
                    activeThumbColor: AppColors.accent,
                  ),
                  const Divider(),
                  SwitchListTile(
                    value: _wifiOnly,
                    onChanged: (v) => setState(() => _wifiOnly = v),
                    title: const Text('Wi-Fi only'),
                    subtitle: const Text('Do not sync on mobile data'),
                    activeThumbColor: AppColors.accent,
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.l),

              // ── Notifications ─────────────────────────────────────────────
              _SectionHeader(label: 'Notifications'),
              _SettingsCard(
                children: [
                  SwitchListTile(
                    value: _notifications,
                    onChanged: (v) => setState(() => _notifications = v),
                    title: const Text('Sync alerts'),
                    subtitle: const Text('Notify when clipboard is synced'),
                    activeThumbColor: AppColors.accent,
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.l),

              // ── Privacy ───────────────────────────────────────────────────
              _SectionHeader(label: 'Privacy'),
              _SettingsCard(
                children: [
                  ListTile(
                    title: const Text('Retention period'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          '7 days',
                          style: TextStyle(color: AppColors.textHint),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textHint,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    onTap: () {},
                    title: const Text(
                      'Clear clipboard history',
                      style: TextStyle(color: AppColors.error),
                    ),
                    trailing: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.error,
                      size: 18,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.l),

              // ── About ─────────────────────────────────────────────────────
              _SectionHeader(label: 'About'),
              _SettingsCard(
                children: [
                  const ListTile(
                    title: Text('Version'),
                    trailing: Text(
                      '1.0.0',
                      style: TextStyle(color: AppColors.textHint),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    onTap: () {},
                    title: const Text('Terms of Service'),
                    trailing: const Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    onTap: () {},
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: AppColors.textHint,
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
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textHint,
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
