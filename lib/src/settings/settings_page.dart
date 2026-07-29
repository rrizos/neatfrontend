import 'package:flutter/material.dart';
import '../core/http_client.dart' as http;

import '../../l10n/app_localizations.dart';
import '../app.dart';
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
    final l10n = AppLocalizations.of(context);
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
        title: Text(l10n.settings),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            _SectionHeader(label: l10n.appearance, color: sectionColor),
            SwitchListTile(
              value: isLight,
              onChanged: (value) =>
                  onThemeModeChanged(value ? ThemeMode.light : ThemeMode.dark),
              secondary: Icon(
                isLight ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: isLight ? Colors.black : Colors.white,
              ),
              title: Text(
                l10n.lightMode,
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _SectionHeader(label: l10n.language, color: sectionColor),
            _LanguageRow(
              label: 'Ελληνικά',
              selected: Localizations.localeOf(context).languageCode == 'el',
              isLight: isLight,
              onTap: () => NeatApp.setLocale(const Locale('el')),
            ),
            Divider(height: 1, color: divider),
            _LanguageRow(
              label: 'English',
              selected: Localizations.localeOf(context).languageCode == 'en',
              isLight: isLight,
              onTap: () => NeatApp.setLocale(const Locale('en')),
            ),
            const SizedBox(height: 28),
            _SectionHeader(label: l10n.legal, color: sectionColor),
            _SettingsRow(
              icon: Icons.description_outlined,
              label: l10n.termsOfService,
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
              label: l10n.privacyPolicy,
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
            _SectionHeader(label: l10n.account, color: sectionColor),
            _SettingsRow(
              icon: Icons.block,
              label: l10n.blockedAccounts,
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
              label: l10n.logOut,
              isLight: isLight,
              showChevron: false,
              onTap: () => _confirmLogout(context),
            ),
            Divider(height: 1, color: divider),
            _SettingsRow(
              icon: Icons.delete_outline,
              label: l10n.deleteAccount,
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logOut),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.logOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await onLogout();
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Deleting is irreversible and the row sits one tap away in a list people
    // scroll through, so the confirmation asks for a typed word rather than a
    // second button — a mis-tap can't produce it.
    final word = l10n.deleteAccountTypeWord;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final matches = controller.text.trim().toUpperCase() == word.toUpperCase();
          return AlertDialog(
            title: Text(l10n.deleteAccount),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.deleteAccountConfirm),
                const SizedBox(height: 18),
                Text(
                  l10n.deleteAccountTypePrompt(word),
                  style: TextStyle(
                    color: isLight ? const Color(0xff6b7280) : const Color(0xffb7b7b7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: word,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: matches
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Text(
                  l10n.delete,
                  style: TextStyle(
                    color: matches
                        ? const Color(0xfff66c6c)
                        : (isLight
                            ? const Color(0xffb0b4bb)
                            : const Color(0xff5c5c5c)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (confirmed != true || !context.mounted) return;

    try {
      final res = await http.delete(
        deleteAccountEndpoint,
        headers: authGetHeaders(token),
      );
      if (!context.mounted) return;
      if (res.statusCode != 200 && res.statusCode != 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.actionFailedStatus(res.statusCode, res.body))),
        );
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.genericErrorMessage('$e'))),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await onLogout();
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.selected,
    required this.isLight,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isLight ? Colors.black : Colors.white;
    return ListTile(
      onTap: selected ? null : onTap,
      leading: Icon(Icons.language, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: Color(0xff1479ff))
          : null,
    );
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
