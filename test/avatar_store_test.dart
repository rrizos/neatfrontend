import 'package:flutter_test/flutter_test.dart';
import 'package:neat/src/core/avatar_store.dart';

/// A new profile picture has to reach screens that were built before it
/// existed. Avatars are base64 copied into every payload that mentions a
/// person — each post, comment and conversation carries its own — so without
/// this the feed kept showing the old photo until every one of them was
/// refetched, which reads as the change not having worked.
void main() {
  setUp(AvatarStore.reset);

  const old = 'data:image/jpeg;base64,OLD';
  const fresh = 'data:image/jpeg;base64,NEW';

  test('a post built before the change shows the new picture', () {
    AvatarStore.update(username: 'rizos', previousUrl: old, url: fresh);
    // What a feed row holds: the author's name, and the URL it was served.
    expect(AvatarStore.resolve('rizos', old), fresh);
  });

  test('resolves for someone setting their very first picture', () {
    // Nothing to replace — the old value is empty, so only the username can
    // carry the answer.
    AvatarStore.update(username: 'rizos', previousUrl: '', url: fresh);
    expect(AvatarStore.resolve('rizos', ''), fresh);
  });

  test('a widget holding only the old URL still follows it forward', () {
    // Comments and conversations carry an avatar without an obvious username
    // to look it up by.
    AvatarStore.update(username: 'rizos', previousUrl: old, url: fresh);
    expect(AvatarStore.replacementFor(old), fresh);
  });

  test('changing twice in one session does not strand the first URL', () {
    const newest = 'data:image/jpeg;base64,NEWEST';
    AvatarStore.update(username: 'rizos', previousUrl: old, url: fresh);
    AvatarStore.update(username: 'rizos', previousUrl: fresh, url: newest);
    // Anything still holding the original must land on the newest, not on the
    // middle one that no longer exists.
    expect(AvatarStore.replacementFor(old), newest);
    expect(AvatarStore.resolve('rizos', old), newest);
  });

  test('username lookup ignores case and padding', () {
    AvatarStore.update(username: '  Rizos ', previousUrl: '', url: fresh);
    expect(AvatarStore.resolve('rizos', ''), fresh);
  });

  test('other people are left alone', () {
    AvatarStore.update(username: 'rizos', previousUrl: old, url: fresh);
    const theirs = 'data:image/jpeg;base64,THEIRS';
    expect(AvatarStore.resolve('someone_else', theirs), theirs);
  });

  test('a picture known at launch beats a stale cached feed row', () {
    // The relaunch case: the feed is drawn from a cache saved before the
    // picture changed, while /api/auth/me/ already knows the current one.
    AvatarStore.seed(username: 'rizos', url: fresh);
    expect(AvatarStore.resolve('rizos', old), fresh);
  });

  test('seeding an unloaded avatar does not blank it everywhere', () {
    AvatarStore.seed(username: 'rizos', url: '');
    expect(AvatarStore.resolve('rizos', old), old);
    expect(AvatarStore.revision.value, 0, reason: 'should not rebuild the app');
  });

  test('a widget holding a URL the store never saw still gets the new picture', () {
    // The nav-bar bug: it passed its own copy of the URL and relied on the
    // store recognising that exact string as one it had replaced. Anything
    // holding a *different* stale string — a session loaded at launch, say —
    // got nothing back and kept the old picture until the app restarted.
    // Resolving by username has no such dependency.
    AvatarStore.update(username: 'rizos', previousUrl: old, url: fresh);

    const unrelatedStale = 'data:image/jpeg;base64,SOMETHINGELSE';
    expect(AvatarStore.replacementFor(unrelatedStale), isNull,
        reason: 'the store cannot know this string');
    expect(AvatarStore.resolve('rizos', unrelatedStale), fresh,
        reason: 'but it knows whose avatar it is');
  });

  test('the app is told to rebuild, once per real change', () {
    final seen = <int>[];
    void listener() => seen.add(AvatarStore.revision.value);
    AvatarStore.revision.addListener(listener);
    addTearDown(() => AvatarStore.revision.removeListener(listener));

    AvatarStore.update(username: 'rizos', previousUrl: old, url: fresh);
    // Saving the same picture again must not rebuild the whole app.
    AvatarStore.update(username: 'rizos', previousUrl: old, url: fresh);

    expect(seen, [1]);
  });
}
