import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

// The domain, not the bare IP it used to be.
//
// Talking to an IP meant a self-signed certificate and a pinned fingerprint
// (see pinned_http.dart), and that pin is a lock on the infrastructure: the
// server could never be moved, put behind a load balancer, or served through a
// CDN, because every one of those changes the address or the certificate and
// every installed app would stop connecting. neatapp.gr has a real Let's
// Encrypt certificate and resolves to the same box, so this is the same server
// reached in a way that can be changed later by editing DNS.
//
// Verified equivalent before switching: every endpoint the app calls — feed,
// events, me, inbox, notifications, city-heat, link previews, badge, login,
// upload, media and the websocket — answers identically on both.
//
// Builds already in people's hands still use the IP, and that endpoint is
// deliberately left working for them.
const String _kServerUrl = String.fromEnvironment(
  'NEAT_API_BASE_URL',
  defaultValue: 'https://neatapp.gr',
);

// On web the app runs on Netlify (HTTPS). Using empty base means all paths
// are relative and get handled by Netlify's proxy rules, avoiding mixed-content
// errors. On mobile the full server URL is used directly.
final String apiBaseUrl = kIsWeb ? '' : _kServerUrl;

const String webBaseUrl = String.fromEnvironment(
  'NEAT_WEB_BASE_URL',
  defaultValue: 'https://neatapp.gr',
);

// The web app and the marketing site share one origin: `/` is the landing
// page, so the app itself is entered at `/app`. Shared post links
// (`/post/<id>`) land on the app too — see netlify.toml.
const String webAppPath = '/app';

Uri linkPreviewEndpoint(String url) =>
    Uri.parse('$apiBaseUrl/api/link-preview/').replace(queryParameters: {'url': url});

Uri postDetailEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/');

/// Uploads one file before the post that will use it exists, so composing a
/// caption and uploading happen at the same time rather than one after the
/// other. See posts/views.py stage_upload.
/// Foreground heartbeat. The server turns these into sessions, which is where
/// retention and time-in-app come from — see accounts/models.py AppSession.
Uri get sessionPingEndpoint => Uri.parse('$apiBaseUrl/api/auth/session/ping/');

Uri get stageUploadEndpoint => Uri.parse('$apiBaseUrl/api/posts/upload/');

/// Which of [ids] still exist. One request for a whole thread's shared posts.
Uri postsExistEndpoint(Iterable<int> ids) =>
    Uri.parse('$apiBaseUrl/api/posts/exist/?ids=${ids.join(',')}');

Uri postsEndpoint({bool fresh = false, String? city, int? before}) {
  final uri = Uri.parse('$apiBaseUrl/api/posts/');
  final params = <String, String>{};
  if (city != null && city.isNotEmpty) params['city'] = city;
  // The page of posts older than this one; absent means the newest page.
  if (before != null) params['before'] = '$before';
  if (fresh) {
    params['_'] = DateTime.now().millisecondsSinceEpoch.toString();
  }
  if (params.isEmpty) return uri;
  return uri.replace(queryParameters: params);
}

Uri viralPostsEndpoint({
  String city = '',
  String excludeCity = '',
  required String period,
}) {
  final uri = Uri.parse('$apiBaseUrl/api/posts/viral/');
  // light=1 opts into the compact charts payload (comment counts instead of
  // full comment threads); the comment sheet lazy-loads threads on open.
  final params = <String, String>{'period': period, 'light': '1'};
  if (city.isNotEmpty) params['city'] = city;
  // Charts for "everywhere but home": an exclusion, not an empty city filter,
  // which would fold the viewer's own city back in.
  if (excludeCity.isNotEmpty) params['exclude_city'] = excludeCity;
  return uri.replace(queryParameters: params);
}

Uri postLikeEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/like/');
Uri postShareEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/share/');
Uri postLikersEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/likers/');
Uri postSaveEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/save/');
Uri postCommentsEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/posts/$id/comments/');
Uri postDeleteEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/delete/');
Uri postReportEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/report/');
Uri postPollVoteEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/poll/vote/');

// Admin endpoints
Uri get adminAnalyticsEndpoint => Uri.parse('$apiBaseUrl/api/auth/admin/analytics/');
Uri get adminSecuritySummaryEndpoint =>
    Uri.parse('$apiBaseUrl/api/auth/admin/security/summary/');
Uri get adminSecurityActionsEndpoint =>
    Uri.parse('$apiBaseUrl/api/auth/admin/security/actions/');
Uri adminSecurityLogsEndpoint({
  String severity = 'all',
  String eventType = 'all',
  String query = '',
  int limit = 100,
}) {
  final params = <String, String>{
    'severity': severity,
    'event_type': eventType,
    'limit': '$limit',
  };
  if (query.trim().isNotEmpty) params['q'] = query.trim();
  return Uri.parse('$apiBaseUrl/api/auth/admin/security/logs/')
      .replace(queryParameters: params);
}
Uri get adminReportsEndpoint => Uri.parse('$apiBaseUrl/api/auth/admin/reports/');
Uri adminDismissReportEndpoint(int id) => Uri.parse('$apiBaseUrl/api/auth/admin/reports/$id/');
Uri adminDeletePostEndpoint(int id) => Uri.parse('$apiBaseUrl/api/auth/admin/posts/$id/');
Uri adminDeleteCommentEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/auth/admin/comments/$id/');
Uri adminDeleteMessageEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/auth/admin/messages/$id/');
Uri adminUsersEndpoint([String query = '']) {
  final uri = Uri.parse('$apiBaseUrl/api/auth/admin/users/');
  if (query.trim().isEmpty) return uri;
  return uri.replace(queryParameters: {'q': query.trim()});
}
Uri adminVerifyUserEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/admin/users/$username/verify/');
Uri adminSetOfficialEligibilityEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/admin/users/$username/official-eligibility/');
Uri adminDeleteUserEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/admin/users/$username/delete/');
Uri commentLikeEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/comments/$id/like/');
Uri commentReportEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/comments/$id/report/');
Uri commentPinEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/comments/$id/pin/');
Uri get savedPostsEndpoint => Uri.parse('$apiBaseUrl/api/posts/saved/');
Uri get likedPostsEndpoint => Uri.parse('$apiBaseUrl/api/posts/liked/');
Uri get forgotPasswordEndpoint => Uri.parse('$apiBaseUrl/api/auth/forgot-password/');
Uri get resetPasswordEndpoint => Uri.parse('$apiBaseUrl/api/auth/reset-password/');
Uri get signupEndpoint => Uri.parse('$apiBaseUrl/api/auth/signup/');
Uri get loginEndpoint => Uri.parse('$apiBaseUrl/api/auth/login/');
/// Apple and Google, for both signing up and signing back in — the app cannot
/// know which it is, so the server decides from the provider identity.
Uri get socialLoginEndpoint => Uri.parse('$apiBaseUrl/api/auth/social/');

// ── Google sign-in client ids ───────────────────────────────────────────────
//
// Both come from the Firebase console (Authentication -> Sign-in method ->
// Google). Until they are filled in, the Google button reports that sign-in is
// not configured rather than failing in a way nobody can read.
//
//  * [googleClientId] identifies this app to Google. iOS only — on Android the
//    app is identified by its signing certificate instead, so it stays null
//    there and Google looks the app up by package name + SHA-1.
//  * [googleServerClientId] is the *web* client id from the same project. It
//    is what makes Google mint an ID token addressed to our backend; without
//    it the token comes back with no audience the server will accept.
const String _googleIosClientId =
    '449378002358-i3dlqsb7rmff8jf05ag6slk7o21k8laq.apps.googleusercontent.com';
const String _googleWebClientId =
    '449378002358-430tlsk1shjrk07mv4nbcsjibtk9437a.apps.googleusercontent.com';

String? get googleClientId {
  if (kIsWeb || _googleIosClientId.isEmpty) return null;
  return Platform.isIOS ? _googleIosClientId : null;
}

String? get googleServerClientId =>
    _googleWebClientId.isEmpty ? null : _googleWebClientId;

/// Whether the Google button can do anything yet.
bool get googleSignInConfigured => _googleWebClientId.isNotEmpty;
/// Sets a first password on a provider-only account, or replaces an
/// existing one. See accounts/views.py set_password.
Uri get setPasswordEndpoint =>
    Uri.parse('$apiBaseUrl/api/auth/password/set/');
Uri get logoutEndpoint => Uri.parse('$apiBaseUrl/api/auth/logout/');
Uri get meEndpoint => Uri.parse('$apiBaseUrl/api/auth/me/');
Uri get deleteAccountEndpoint => Uri.parse('$apiBaseUrl/api/auth/me/');
Uri profileEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/profiles/$username/');
Uri followEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/profiles/$username/follow/');
Uri userBlockEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/profiles/$username/block/');
Uri get blockedUsersEndpoint => Uri.parse('$apiBaseUrl/api/auth/blocked/');
Uri followersEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/profiles/$username/followers/');
Uri followingEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/profiles/$username/following/');
Uri get suggestionsEndpoint => Uri.parse('$apiBaseUrl/api/auth/suggestions/');
Uri searchUsersEndpoint([String query = '', bool connectionsOnly = false]) {
  final uri = Uri.parse('$apiBaseUrl/api/auth/search/');
  final q = query.trim();
  final params = <String, String>{
    if (q.isNotEmpty) 'q': q,
    if (connectionsOnly) 'connections_only': '1',
  };
  return params.isEmpty ? uri : uri.replace(queryParameters: params);
}
Uri get notificationsEndpoint =>
    Uri.parse('$apiBaseUrl/api/auth/notifications/');
Uri get registerDeviceEndpoint =>
    Uri.parse('$apiBaseUrl/api/push/devices/register/');
Uri get unregisterDeviceEndpoint =>
    Uri.parse('$apiBaseUrl/api/push/devices/unregister/');
/// What the iOS home-screen icon should read: unread DMs + unread activity.
/// A push can only ever raise that number, so the app pulls this whenever the
/// counts change and stamps it on the icon itself — see push/badge.py.
Uri get pushBadgeEndpoint => Uri.parse('$apiBaseUrl/api/push/badge/');
Uri searchHistoryEndpoint({int limit = 20}) =>
    Uri.parse('$apiBaseUrl/api/auth/search-history/?limit=$limit');
Uri searchHistoryItemEndpoint(String query) =>
    Uri.parse('$apiBaseUrl/api/auth/search-history/${Uri.encodeComponent(query)}/');
Uri get citiesEndpoint => Uri.parse('$apiBaseUrl/api/posts/cities/');
Uri eventsEndpoint({String? city, String? type}) {
  final uri = Uri.parse('$apiBaseUrl/api/events/');
  final params = <String, String>{};
  if (city != null && city.isNotEmpty) params['city'] = city;
  if (type != null && type.isNotEmpty) params['type'] = type;
  if (params.isEmpty) return uri;
  return uri.replace(queryParameters: params);
}
Uri eventDetailEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/$id/');
Uri eventAttendEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/$id/attend/');
Uri eventAttendeesEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/$id/attendees/');
Uri eventUpdateEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/$id/update/');
Uri eventDeleteEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/$id/delete/');
Uri eventReportEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/$id/report/');
Uri eventCommentsEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/$id/comments/');
Uri eventCommentReportEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/comments/$id/report/');
Uri eventCommentPinEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/comments/$id/pin/');
Uri eventCommentLikeEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/comments/$id/like/');
Uri get inboxEndpoint => Uri.parse('$apiBaseUrl/api/messages/inbox/');
Uri get presenceEndpoint => Uri.parse('$apiBaseUrl/api/messages/presence/');
Uri typingEndpoint(int conversationId) =>
    Uri.parse('$apiBaseUrl/api/messages/$conversationId/typing/');
Uri get startConversationEndpoint =>
    Uri.parse('$apiBaseUrl/api/messages/start/');
/// A conversation's newest messages, or — with [before] — the page of older
/// ones ending just before that message id.
Uri messageConversationEndpoint(int id, {int? before}) {
  final uri = Uri.parse('$apiBaseUrl/api/messages/$id/');
  if (before == null) return uri;
  return uri.replace(queryParameters: {'before': '$before'});
}
/// The bytes of a photo or voice note, which threads no longer carry inline.
Uri messageMediaEndpoint(int conversationId, int messageId) =>
    Uri.parse('$apiBaseUrl/api/messages/$conversationId/messages/$messageId/media/');

/// Spends one viewing of a "view once" / "allow replay" photo and returns it.
/// The only route to those bytes — see `message_open` in the backend.
Uri messageOpenEndpoint(int conversationId, int messageId) =>
    Uri.parse('$apiBaseUrl/api/messages/$conversationId/messages/$messageId/open/');
Uri messageReactEndpoint(int conversationId, int messageId) =>
    Uri.parse('$apiBaseUrl/api/messages/$conversationId/messages/$messageId/react/');
Uri messageDeleteEndpoint(int conversationId, int messageId) =>
    Uri.parse('$apiBaseUrl/api/messages/$conversationId/messages/$messageId/delete/');
Uri messageEditEndpoint(int conversationId, int messageId) =>
    Uri.parse('$apiBaseUrl/api/messages/$conversationId/messages/$messageId/edit/');
Uri messageReportEndpoint(int conversationId, int messageId) =>
    Uri.parse('$apiBaseUrl/api/messages/$conversationId/messages/$messageId/report/');
Uri conversationDeleteEndpoint(int conversationId) =>
    Uri.parse('$apiBaseUrl/api/messages/$conversationId/delete/');
Uri get cityHeatEndpoint => Uri.parse('$apiBaseUrl/api/posts/city-heat/');
Uri get neatPassEndpoint => Uri.parse('$apiBaseUrl/api/auth/neat-pass/');

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Accept': 'application/json',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
};

/// Marks this build as one that fetches DM media on demand rather than
/// expecting it inline. The server keeps sending the old, heavy payloads to
/// anything without it — see `_wants_lean_media` in dm_messages/views.py.
// 3 tells the server this build renders avatar *URLs*, so it stops embedding
// them as base64 in every payload that names a person. Measured against the
// live server, that took notifications from 1191 KB to 19 KB and the inbox
// from 125 KB to 5 KB. Only raise this once every screen can draw a URL
// avatar — see avatarProvider in post_card.dart — because a build that still
// decodes data URLs directly would show initials for everyone.
const neatClientHeader = {'X-Neat-Client': '3'};

Map<String, String> authJsonHeaders(String token) => {
  ...jsonHeaders,
  ...neatClientHeader,
  'Authorization': 'Token $token',
};

Map<String, String> authGetHeaders(String token) => {
  ...neatClientHeader,
  'Accept': 'application/json',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
  'Authorization': 'Token $token',
};

const _kNoConnection =
    'Δεν υπάρχει σύνδεση στο διαδίκτυο. Έλεγξε τη σύνδεσή σου και δοκίμασε ξανά.';

// Transport failures, matched by text so this works on every platform (dart:io
// types aren't available on web, so we can't type-check SocketException here).
const _kNetworkMarkers = [
  'socketexception',
  'clientexception',
  'handshakeexception',
  'failed host lookup',
  'connection refused',
  'connection closed',
  'connection reset',
  'connection timed out',
  'network is unreachable',
  'no route to host',
  'software caused connection abort',
  'xmlhttprequest error', // web
  'connection attempt failed',
  'os error',
];

bool _looksLikeNetworkFailure(String text) {
  final lower = text.toLowerCase();
  return _kNetworkMarkers.any(lower.contains);
}

/// Removes anything that would expose infrastructure — the API host/IP, a
/// `uri=...` tail, or a bare address — from a message before it reaches a user.
String _scrubEndpoints(String message) {
  var out = message;
  if (apiBaseUrl.isNotEmpty) out = out.replaceAll(apiBaseUrl, 'τον διακομιστή');
  out = out.replaceAll(RegExp(r',?\s*uri=\S+'), '');
  out = out.replaceAll(RegExp(r'https?://\S+'), 'τον διακομιστή');
  // Bare IPv4, with or without a port.
  out = out.replaceAll(RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b'), 'τον διακομιστή');
  return out.trim();
}

/// Turns a caught error into something safe to show a user.
///
/// Messages we raise deliberately (e.g. `Exception(friendlyHttpError(res))`,
/// which carries the server's own wording) pass through; anything that looks
/// like a transport failure becomes a plain connection message. Raw
/// SocketException text embeds the server host/IP and the full request URL, so
/// it must never reach the screen.
String friendlyError(Object error) {
  final raw = error.toString();
  if (_looksLikeNetworkFailure(raw)) return _kNoConnection;
  if (raw.toLowerCase().contains('timeoutexception')) {
    return 'Έληξε ο χρόνος σύνδεσης. Δοκίμασε ξανά.';
  }
  final message = _scrubEndpoints(raw.replaceFirst('Exception: ', ''));
  if (message.isEmpty) return 'Κάτι πήγε στραβά. Δοκίμασε ξανά.';
  return message;
}

String friendlyHttpError(http.Response response) {
  final body = response.body.trim();
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded['error']?.toString() ?? 'Το αίτημα απέτυχε';
    }
  } catch (_) {}
  return 'Το αίτημα απέτυχε (${response.statusCode})';
}
