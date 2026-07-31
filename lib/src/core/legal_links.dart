import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import 'api.dart';

/// The Terms and the Privacy Policy live on the website, not in the bundle, so
/// the text can be revised by redeploying neatapp.gr instead of shipping a new
/// build. The source copy is in landing/legal/ — see tools/build_web.sh.
///
/// The pages are Greek by default and take ?lang=en, matching the app's own
/// language switch.
Uri _legalUri(BuildContext context, String path) {
  final english = Localizations.localeOf(context).languageCode == 'en';
  return Uri.parse('$webBaseUrl$path${english ? '?lang=en' : ''}');
}

Future<void> _open(BuildContext context, String path) async {
  final uri = _legalUri(context, path);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);

  // An in-app browser keeps the user inside Neat; on web this opens a tab.
  final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView)
      .catchError((_) => false);
  if (opened) return;

  if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  messenger?.showSnackBar(SnackBar(content: Text(l10n.couldNotOpenLink)));
}

Future<void> openTermsOfService(BuildContext context) => _open(context, '/terms');

Future<void> openPrivacyPolicy(BuildContext context) => _open(context, '/privacy');
