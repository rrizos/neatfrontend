import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// The backend (63.181.201.175) has no domain name, so it can't get a
// certificate from a public CA — Let's Encrypt and friends only issue for
// domain names, not bare IPs. Its nginx serves a self-signed cert instead;
// normal TLS chain validation will always fail for that (untrusted root), so
// instead of disabling certificate checks (which would accept ANY cert from
// ANY host — a real MITM hole), we pin this one specific certificate's
// SHA-256 fingerprint and only accept it for this one specific host. Every
// other HTTPS call the app makes (Nominatim, Firebase, Netlify, MapKit's CDN)
// goes through normal system CA validation, untouched.
const String _kPinnedHost = '63.181.201.175';
const String _kPinnedCertSha256Fingerprint =
    'DCC14E2B8F8500AE850CC6A8EB259DD603E900B74A9071DEF2BE966622FE5FB8';

void setupPinnedHttpOverrides() {
  if (kIsWeb) return; // browsers manage their own TLS trust; nothing to hook
  HttpOverrides.global = _PinnedHttpOverrides();
}

class _PinnedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (host != _kPinnedHost) return false;
      final fingerprint = sha256.convert(cert.der).toString().toUpperCase();
      return fingerprint == _kPinnedCertSha256Fingerprint;
    };
    return client;
  }
}
