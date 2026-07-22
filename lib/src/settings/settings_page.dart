import 'package:flutter/material.dart';
import '../core/http_client.dart' as http;

import '../core/api.dart';
import '../legal/legal_page.dart';
import 'blocked_accounts_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
    required this.token,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;
  final String token;

  @override
  Widget build(BuildContext context) {
    final isLight = themeMode == ThemeMode.light;
    final bg = isLight ? Colors.white : const Color(0xff121212);
    final divider = isLight ? const Color(0xffd9dee6) : const Color(0xff242424);
    final sectionColor = isLight ? const Color(0xff616161) : const Color(0xffb3b3b3);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: isLight ? Colors.black : Colors.white,
        elevation: 0,
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            _SectionHeader(label: 'Appearance', color: sectionColor),
            SwitchListTile(
              value: isLight,
              onChanged: (value) =>
                  onThemeModeChanged(value ? ThemeMode.light : ThemeMode.dark),
              secondary: Icon(
                isLight ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: isLight ? Colors.black : Colors.white,
              ),
              title: Text(
                'Light mode',
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _SectionHeader(label: 'Legal', color: sectionColor),
            _SettingsRow(
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              isLight: isLight,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LegalPage(
                    title: 'Terms of Service',
                    body: termsOfServiceText,
                    titleEl: termsOfServiceTitleEl,
                    bodyEl: termsOfServiceTextEl,
                    themeMode: themeMode,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: divider),
            _SettingsRow(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              isLight: isLight,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LegalPage(
                    title: 'Privacy Policy',
                    body: privacyPolicyText,
                    titleEl: privacyPolicyTitleEl,
                    bodyEl: privacyPolicyTextEl,
                    themeMode: themeMode,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            _SectionHeader(label: 'Account', color: sectionColor),
            _SettingsRow(
              icon: Icons.block,
              label: 'Blocked Accounts',
              isLight: isLight,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BlockedAccountsPage(token: token),
                ),
              ),
            ),
            Divider(height: 1, color: divider),
            _SettingsRow(
              icon: Icons.logout,
              label: 'Log Out',
              isLight: isLight,
              showChevron: false,
              onTap: () => _confirmLogout(context),
            ),
            Divider(height: 1, color: divider),
            _SettingsRow(
              icon: Icons.delete_outline,
              label: 'Delete Account',
              isLight: isLight,
              destructive: true,
              showChevron: false,
              onTap: () => _confirmDeleteAccount(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await onLogout();
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and everything in it — '
          'your profile, posts, events, and messages. This action cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xfff66c6c)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final res = await http.delete(
        deleteAccountEndpoint,
        headers: authGetHeaders(token),
      );
      if (!context.mounted) return;
      if (res.statusCode != 200 && res.statusCode != 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed (${res.statusCode}): ${res.body}')),
        );
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await onLogout();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.isLight,
    required this.onTap,
    this.destructive = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final bool isLight;
  final VoidCallback onTap;
  final bool destructive;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xfff66c6c)
        : (isLight ? Colors.black : Colors.white);
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      trailing: showChevron
          ? Icon(
              Icons.chevron_right,
              color: isLight ? const Color(0xffb0b0b0) : const Color(0xff5a5a5a),
            )
          : null,
    );
  }
}
