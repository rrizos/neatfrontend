import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

const String _kServerUrl = String.fromEnvironment(
  'NEAT_API_BASE_URL',
  defaultValue: 'https://63.181.201.175',
);

// On web the app runs on Netlify (HTTPS). Using empty base means all paths
// are relative and get handled by Netlify's proxy rules, avoiding mixed-content
// errors. On mobile the full server URL is used directly.
final String apiBaseUrl = kIsWeb ? '' : _kServerUrl;

const String webBaseUrl = String.fromEnvironment(
  'NEAT_WEB_BASE_URL',
  defaultValue: 'https://neatapp.gr',
);

Uri postDetailEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/');

Uri postsEndpoint({bool fresh = false, String? city}) {
  final uri = Uri.parse('$apiBaseUrl/api/posts/');
  final params = <String, String>{};
  if (city != null && city.isNotEmpty) params['city'] = city;
  if (fresh) {
    params['_'] = DateTime.now().millisecondsSinceEpoch.toString();
  }
  if (params.isEmpty) return uri;
  return uri.replace(queryParameters: params);
}

Uri viralPostsEndpoint({required String city, required String period}) {
  final uri = Uri.parse('$apiBaseUrl/api/posts/viral/');
  // light=1 opts into the compact charts payload (comment counts instead of
  // full comment threads); the comment sheet lazy-loads threads on open.
  final params = <String, String>{'period': period, 'light': '1'};
  if (city.isNotEmpty) params['city'] = city;
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
Uri searchUsersEndpoint([String query = '']) {
  final uri = Uri.parse('$apiBaseUrl/api/auth/search/');
  final q = query.trim();
  if (q.isEmpty) return uri;
  return uri.replace(queryParameters: {'q': q});
}
Uri get notificationsEndpoint =>
    Uri.parse('$apiBaseUrl/api/auth/notifications/');
Uri get registerDeviceEndpoint =>
    Uri.parse('$apiBaseUrl/api/push/devices/register/');
Uri get unregisterDeviceEndpoint =>
    Uri.parse('$apiBaseUrl/api/push/devices/unregister/');
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
Uri messageConversationEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/messages/$id/');
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

const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Accept': 'application/json',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
};

Map<String, String> authJsonHeaders(String token) => {
  ...jsonHeaders,
  'Authorization': 'Token $token',
};

Map<String, String> authGetHeaders(String token) => {
  'Accept': 'application/json',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
  'Authorization': 'Token $token',
};

const _kNoConnection =
    'No internet connection. Please check your connection and try again.';

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
  if (apiBaseUrl.isNotEmpty) out = out.replaceAll(apiBaseUrl, 'the server');
  out = out.replaceAll(RegExp(r',?\s*uri=\S+'), '');
  out = out.replaceAll(RegExp(r'https?://\S+'), 'the server');
  // Bare IPv4, with or without a port.
  out = out.replaceAll(RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?\b'), 'the server');
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
    return 'The connection timed out. Please try again.';
  }
  final message = _scrubEndpoints(raw.replaceFirst('Exception: ', ''));
  if (message.isEmpty) return 'Something went wrong. Please try again.';
  return message;
}

String friendlyHttpError(http.Response response) {
  final body = response.body.trim();
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded['error']?.toString() ?? 'Request failed';
    }
  } catch (_) {}
  return 'Request failed (${response.statusCode})';
}
