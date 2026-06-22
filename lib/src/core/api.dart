import 'dart:convert';

import 'package:http/http.dart' as http;

const String apiBaseUrl = String.fromEnvironment(
  'NEAT_API_BASE_URL',
  defaultValue: 'https://neatbackendv1.onrender.com',
);

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

Uri postLikeEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/like/');
Uri postLikersEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/likers/');
Uri postSaveEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/save/');
Uri postCommentsEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/posts/$id/comments/');
Uri postDeleteEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/$id/delete/');
Uri commentLikeEndpoint(int id) => Uri.parse('$apiBaseUrl/api/posts/comments/$id/like/');
Uri get savedPostsEndpoint => Uri.parse('$apiBaseUrl/api/posts/saved/');
Uri get likedPostsEndpoint => Uri.parse('$apiBaseUrl/api/posts/liked/');
Uri get signupEndpoint => Uri.parse('$apiBaseUrl/api/auth/signup/');
Uri get loginEndpoint => Uri.parse('$apiBaseUrl/api/auth/login/');
Uri get logoutEndpoint => Uri.parse('$apiBaseUrl/api/auth/logout/');
Uri get meEndpoint => Uri.parse('$apiBaseUrl/api/auth/me/');
Uri profileEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/profiles/$username/');
Uri followEndpoint(String username) =>
    Uri.parse('$apiBaseUrl/api/auth/profiles/$username/follow/');
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
Uri get searchHistoryEndpoint =>
    Uri.parse('$apiBaseUrl/api/auth/search-history/');
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
Uri eventDeleteEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/events/$id/delete/');
Uri get inboxEndpoint => Uri.parse('$apiBaseUrl/api/messages/inbox/');
Uri get presenceEndpoint => Uri.parse('$apiBaseUrl/api/messages/presence/');
Uri get startConversationEndpoint =>
    Uri.parse('$apiBaseUrl/api/messages/start/');
Uri messageConversationEndpoint(int id) =>
    Uri.parse('$apiBaseUrl/api/messages/$id/');

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
