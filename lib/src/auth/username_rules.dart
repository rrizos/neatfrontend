import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// What a username is allowed to be, in the one place both screens read it
/// from — the sign-up form and the picker an Apple or Google account sees.
///
/// These mirror `_username_format_error` in the server's accounts/views.py.
/// The server is what actually decides; repeating the rule here is so a name
/// is refused at the keyboard, with a reason, instead of by a round trip that
/// comes back saying only "no".
///
/// The rule is narrow on purpose. A username ends up in a URL (the profile is
/// fetched as `/api/auth/profiles/<username>/`) and in @-mentions, so a name
/// holding a slash or a space produces an account whose own profile will not
/// open — which is exactly how this was found.
const usernameMinLength = 3;
const usernameMaxLength = 20;

final _allowed = RegExp(r'^[a-zA-Z0-9._]+$');

/// Stops the impossible characters at the keyboard rather than explaining
/// them afterwards.
///
/// Sign-in fields must not use this: people sign in with an email address,
/// and the accounts made before this rule existed still hold spaces and Greek
/// letters that they have to be able to type.
final usernameInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
];

/// Why [name] cannot be used, or null when it is fine.
String? usernameFormatError(String name, AppLocalizations l10n) {
  if (name.length < usernameMinLength) return l10n.usernameSetupTooShort;
  if (name.length > usernameMaxLength) return l10n.usernameSetupTooLong;
  if (!_allowed.hasMatch(name)) return l10n.usernameSetupBadChars;
  if (name.startsWith('.') || name.endsWith('.')) {
    return l10n.usernameSetupBadChars;
  }
  return null;
}
