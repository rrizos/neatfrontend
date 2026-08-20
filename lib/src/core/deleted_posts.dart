import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'http_client.dart' as http;

/// Which shared posts have since been deleted.
///
/// Sharing a post into a chat stores a *snapshot* of it in the message, so the
/// card goes on rendering perfectly long after the post itself is gone. Tapping
/// it was the only way to find out, and what you got was an error.
///
/// The answer is per-post and never changes back — a deleted post does not
/// return — so it is worth remembering for the session, and a thread's worth of
/// cards is answered in one request rather than one per card.
class DeletedPosts {
  const DeletedPosts._();

  static final Set<int> _deleted = {};
  static final Set<int> _known = {};

  /// Bumped when something new is learned, so open threads repaint.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool isDeleted(int postId) => _deleted.contains(postId);

  /// Looks up any of [postIds] not already known. Safe to call on every build.
  static Future<void> check({
    required String token,
    required Iterable<int> postIds,
  }) async {
    final unknown = postIds.where((id) => id > 0 && !_known.contains(id)).toSet();
    if (unknown.isEmpty) return;
    // Recorded before the request, not after: two rebuilds in the same frame
    // would otherwise each fire the same lookup.
    _known.addAll(unknown);
    try {
      final res = await http.get(
        postsExistEndpoint(unknown),
        headers: authGetHeaders(token),
      );
      if (res.statusCode != 200) {
        // Unknown again, so a network blip doesn't permanently convince us a
        // post is fine when we never actually asked.
        _known.removeAll(unknown);
        return;
      }
      final missing = (jsonDecode(res.body) as Map<String, dynamic>)['missing'];
      if (missing is! List || missing.isEmpty) return;
      _deleted.addAll(missing.map((e) => int.tryParse(e.toString()) ?? 0));
      revision.value++;
    } catch (_) {
      _known.removeAll(unknown);
    }
  }

  @visibleForTesting
  static void reset() {
    _deleted.clear();
    _known.clear();
    revision.value = 0;
  }
}
