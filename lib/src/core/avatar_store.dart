import 'package:flutter/foundation.dart';

/// The newest avatar known for a user, whatever an already-fetched payload says.
///
/// Avatars are base64 `data:` URLs carried inside every object that mentions a
/// person — each post, comment, conversation and search result has its own
/// copy. So changing your picture used to leave the old one everywhere until
/// each of those was fetched again: your own profile updated, and then your
/// posts, the feed, your comments and the chat list all still showed the photo
/// you had just replaced, which reads as the change not having worked.
///
/// This is the one place that answers "what does this person look like now".
/// Two ways in, because both cases happen:
///
///  * by username, which covers someone setting their very first picture, and
///  * by the URL being replaced, which fixes every widget still holding the
///    old `data:` URL without it needing to know whose it is — see
///    `decodeAvatarUrl`.
class AvatarStore {
  const AvatarStore._();

  /// Bumped on every change. Anything showing an avatar rebuilds off this;
  /// the app is wrapped in a listener, since a new picture can appear on any
  /// screen at once and it happens rarely enough to be worth the rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final Map<String, String> _byUser = {};
  static final Map<String, String> _replacements = {};

  static void update({
    required String username,
    required String previousUrl,
    required String url,
  }) {
    final key = username.trim().toLowerCase();
    if (key.isEmpty) return;
    if (_byUser[key] == url && (previousUrl.isEmpty || _replacements[previousUrl] == url)) {
      return; // Nothing new to say; don't rebuild the app over it.
    }
    _byUser[key] = url;
    if (previousUrl.isNotEmpty && previousUrl != url) {
      _replacements[previousUrl] = url;
      // An avatar can change twice in a session, so anything that pointed at
      // the URL we just replaced has to follow it forward.
      _replacements.updateAll((_, value) => value == previousUrl ? url : value);
    }
    revision.value++;
  }

  /// What [username]'s avatar should be right now, given the (possibly stale)
  /// [url] the caller is holding.
  static String resolve(String username, String url) {
    final override = _byUser[username.trim().toLowerCase()];
    if (override != null) return override;
    return _replacements[url] ?? url;
  }

  /// The replacement for a `data:` URL that has since changed, if any.
  static String? replacementFor(String url) => _replacements[url];

  @visibleForTesting
  static void reset() {
    _byUser.clear();
    _replacements.clear();
    revision.value = 0;
  }
}
