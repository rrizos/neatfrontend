import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neat/src/core/avatar_store.dart';
import 'package:neat/src/core/http_client.dart' as http;
import 'package:neat/src/core/profile_save_queue.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A fake application-support directory, so the queue's on-disk job can be
/// exercised without a device.
class _FakePaths extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('neat_queue_test');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    AvatarStore.reset();
    await ProfileSaveQueue.reset();
  });

  tearDown(() async {
    await ProfileSaveQueue.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('the change is written to disk before any upload is attempted', () async {
    // This is the "save for sure" half: the app can be killed the instant
    // after Save and the change still exists somewhere.
    await ProfileSaveQueue.enqueue(
      token: 'tok',
      body: const {'bio': 'νέο κείμενο'},
      username: 'rizos',
      previousAvatarUrl: 'data:image/jpeg;base64,OLD',
    );
    final job = File('${tmp.path}/pending_profile_save.json');
    expect(job.existsSync(), isTrue,
        reason: 'a queued save must survive the app being killed');
    expect(job.readAsStringSync(), contains('νέο κείμενο'));
  });

  test('it reports work outstanding until the server has it', () async {
    expect(ProfileSaveQueue.pending.value, isFalse);
    await ProfileSaveQueue.enqueue(
      token: 'tok',
      body: const {'bio': 'x'},
      username: 'rizos',
      previousAvatarUrl: '',
    );
    // No server in a unit test, so it stays owed — which is the point.
    expect(ProfileSaveQueue.pending.value, isTrue);
  });

  test('retryPending is a no-op when nothing is owed', () async {
    await ProfileSaveQueue.retryPending('tok');
    expect(ProfileSaveQueue.pending.value, isFalse);
  });

  const okBody = '{"user":{"id":1,"username":"rizos","email":"","fullName":"",'
      '"bio":"b","city":"","avatarUrl":"data:image/jpeg;base64,SERVER",'
      '"followers":0,"following":0,"isFollowing":false}}';

  test('a leftover job from a previous launch is delivered, then cleared', () async {
    File('${tmp.path}/pending_profile_save.json').writeAsStringSync(
      '{"body":{"bio":"from last time"},"username":"rizos",'
      '"previousAvatarUrl":"data:image/jpeg;base64,OLD",'
      '"queuedAt":"2026-08-19T00:00:00.000"}',
    );
    var sentBodies = <String>[];
    ProfileSaveQueue.sendOverride = (token, body) async {
      sentBodies.add(body);
      return http.Response(okBody, 200);
    };

    await ProfileSaveQueue.retryPending('tok');

    expect(sentBodies.single, contains('from last time'),
        reason: 'a save interrupted by an app kill must resume on next launch');
    expect(ProfileSaveQueue.pending.value, isFalse);
    expect(File('${tmp.path}/pending_profile_save.json').existsSync(), isFalse);
  });

  test('the server\'s own copy replaces the local one once it lands', () async {
    ProfileSaveQueue.sendOverride = (_, _) async => http.Response(okBody, 200);
    await ProfileSaveQueue.enqueue(
      token: 'tok',
      body: const {'avatarUrl': 'data:image/jpeg;base64,LOCAL'},
      username: 'rizos',
      previousAvatarUrl: 'data:image/jpeg;base64,OLD',
    );
    await ProfileSaveQueue.settle();
    // The app showed LOCAL immediately; the canonical re-encoded copy wins
    // once the server answers, so every device agrees.
    expect(AvatarStore.resolve('rizos', ''), 'data:image/jpeg;base64,SERVER');
  });

  test('a lost connection keeps the job for another attempt', () async {
    ProfileSaveQueue.sendOverride = (_, _) async => throw const SocketException('down');
    await ProfileSaveQueue.enqueue(
      token: 'tok',
      body: const {'bio': 'x'},
      username: 'rizos',
      previousAvatarUrl: '',
    );
    await ProfileSaveQueue.settle();
    expect(ProfileSaveQueue.pending.value, isTrue);
    expect(File('${tmp.path}/pending_profile_save.json').existsSync(), isTrue,
        reason: 'the only copy of the change must not be thrown away');
  });

  test('a refusal is not retried forever', () async {
    // A 400 means the same thing however many times it is asked, and a 401
    // needs signing in again — neither is fixed by this queue.
    var calls = 0;
    ProfileSaveQueue.sendOverride = (_, _) async {
      calls++;
      return http.Response('{"error":"nope"}', 400);
    };
    await ProfileSaveQueue.enqueue(
      token: 'tok',
      body: const {'bio': 'x'},
      username: 'rizos',
      previousAvatarUrl: '',
    );
    await ProfileSaveQueue.settle();
    expect(calls, 1);
    expect(ProfileSaveQueue.pending.value, isFalse);
    expect(File('${tmp.path}/pending_profile_save.json').existsSync(), isFalse);
  });
}
