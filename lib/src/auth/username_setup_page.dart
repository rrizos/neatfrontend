import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../core/onboarding_ui.dart';

/// The step where an Apple or Google sign-up replaces the username the server
/// invented for it.
///
/// Only those accounts ever see this: an email sign-up already typed a
/// username into the form, and a returning user has had one for a long time.
/// The generated name exists purely so the account could be created at all —
/// it is nobody's idea of a name they want to be known by.
///
/// The rules mirror the server's, so a name is refused here with an
/// explanation rather than by a round trip that comes back saying only "no".
class UsernameSetupPage extends StatefulWidget {
  const UsernameSetupPage({
    super.key,
    required this.themeMode,
    required this.onChosen,
    this.busy = false,
    this.serverError,
  });

  final ThemeMode themeMode;

  /// Called with a name that has already passed the local rules.
  final ValueChanged<String> onChosen;

  /// True while the choice is being saved.
  final bool busy;

  /// Something only the server could know — that the name is taken, usually.
  final String? serverError;

  @override
  State<UsernameSetupPage> createState() => _UsernameSetupPageState();
}

class _UsernameSetupPageState extends State<UsernameSetupPage> {
  final _controller = TextEditingController();
  String? _error;

  static const _minLength = 3;
  static const _maxLength = 20;
  static final _allowed = RegExp(r'^[a-zA-Z0-9._]+$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _localError(String name, AppLocalizations l10n) {
    if (name.length < _minLength) return l10n.usernameSetupTooShort;
    if (name.length > _maxLength) return l10n.usernameSetupTooLong;
    if (!_allowed.hasMatch(name)) return l10n.usernameSetupBadChars;
    if (name.startsWith('.') || name.endsWith('.')) {
      return l10n.usernameSetupBadChars;
    }
    return null;
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final name = _controller.text.trim();
    final error = _localError(name, l10n);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);
    widget.onChosen(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = widget.themeMode == ThemeMode.light;
    final fg = onboardingFg(isLight);
    final shown = _error ?? widget.serverError;

    return PopScope(
      // The account exists but has a name it did not choose; there is nowhere
      // sensible to go back to.
      canPop: false,
      child: Scaffold(
        backgroundColor: isLight ? Colors.white : const Color(0xff000000),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: OnboardingBody(
                  children: [
                    OnboardingHeadline(
                      title: l10n.usernameSetupTitle,
                      subtitle: l10n.usernameSetupSubtitle,
                      isLight: isLight,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      enabled: !widget.busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) {
                        if (shown != null) setState(() => _error = null);
                      },
                      maxLength: _maxLength,
                      style: TextStyle(color: fg, fontSize: 17),
                      inputFormatters: [
                        // Stops the impossible characters at the keyboard
                        // rather than explaining them afterwards.
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
                      ],
                      decoration: InputDecoration(
                        prefixText: '@',
                        prefixStyle: TextStyle(
                            color: onboardingMuted(isLight), fontSize: 17),
                        hintText: l10n.usernameSetupHint,
                        hintStyle: TextStyle(color: onboardingMuted(isLight)),
                        counterText: '',
                        errorText: shown,
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: isLight
                                ? const Color(0xffd6d9de)
                                : const Color(0xff2a2a2a),
                          ),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: fg),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.usernameSetupRules,
                      style: TextStyle(
                          color: onboardingMuted(isLight), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              OnboardingFooter(
                children: [
                  // OnboardingButton takes a non-null callback, so being
                  // busy is expressed by covering it rather than by handing it
                  // a no-op that would still look pressable.
                  Opacity(
                    opacity: widget.busy ? 0.6 : 1,
                    child: AbsorbPointer(
                      absorbing: widget.busy,
                      child: OnboardingButton(
                        label: l10n.usernameSetupCta,
                        onPressed: _submit,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
