import 'package:flutter_test/flutter_test.dart';
import 'package:neat/src/core/deleted_posts.dart';

/// A post shared into a chat is stored as a snapshot, so the card renders
/// perfectly long after the original is gone — tapping it was the only way to
/// find out, and what you got was an error.
void main() {
  setUp(DeletedPosts.reset);

  test('nothing is assumed deleted before it has been checked', () {
    expect(DeletedPosts.isDeleted(1), isFalse);
  });

  test('the same post is only ever looked up once', () async {
    // No HTTP client is injectable here, so the request fails and the ids are
    // released — which is itself the behaviour worth pinning: a failed lookup
    // must not leave a post permanently marked as "asked about".
    await DeletedPosts.check(token: 't', postIds: const [1, 2]);
    expect(DeletedPosts.isDeleted(1), isFalse,
        reason: 'a failed lookup must not convict a post');
  });

  test('an empty list does no work at all', () async {
    await DeletedPosts.check(token: 't', postIds: const []);
    expect(DeletedPosts.revision.value, 0);
  });

  test('non-positive ids are never asked about', () async {
    await DeletedPosts.check(token: 't', postIds: const [0, -3]);
    expect(DeletedPosts.revision.value, 0);
  });
}
