import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'http_client.dart' as http;

import 'api.dart';

const _softChannelId = 'soft_channel';
const _messagesChannelId = 'messages_channel';

/// Background isolate entry point required by firebase_messaging. Real
/// notification display for background/killed app states is handled
/// natively by Android/iOS from the FCM `notification` payload — this is
/// just the mandatory hook the plugin needs registered.
@pragma('vm:entry-point')
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Runs in its own isolate with no app state, so it does the one thing it
  // can do safely: paint the count the push already carried. iOS applies
  // `aps.badge` itself for a backgrounded app, but Android has no equivalent
  // and a data-only push gets no help from either — this covers both.
  final raw = message.data['badge'];
  final badge = int.tryParse('$raw');
  if (badge == null) return;
  try {
    await const MethodChannel('com.neat/badge')
        .invokeMethod('setBadge', badge < 0 ? 0 : badge);
  } catch (_) {
    // No channel in this isolate on some platforms; the foreground path and
    // aps.badge both still apply it.
  }
}

/// Wires up Firebase Cloud Messaging: permission requests, device-token
/// registration, and tap-to-navigate. No tray notification is ever shown
/// while the app is foregrounded (on either platform) — only when
/// backgrounded/killed, which Android/iOS handle natively from the FCM
/// `notification` payload without any app code running.
///
/// Every push is either a "soft" notification-center item (likes, follows,
/// comments, event activity — silent, channel `soft_channel`) or a DM alert
/// (full ring + sender avatar, channel `messages_channel`); see
/// `push/senders.py` on the backend for how each is built.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();

  String? _authToken;
  String? _fcmToken;

  void Function(int conversationId)? onDmTap;
  VoidCallback? onSoftTap;
  // Receives the full push data map for an activity ("soft") notification so it
  // can navigate to the exact target (post / comment) like an in-app tap.
  void Function(Map<String, dynamic> data)? onNotificationTap;
  int? _pendingConversationId;
  bool _pendingSoft = false;
  Map<String, dynamic>? _pendingNotificationData;
  // Message ids already routed. A cold-start tap can be delivered twice —
  // once through onMessageOpenedApp and once through getInitialMessage (which
  // Android populates from the very same intent) — and without this the
  // conversation would be pushed onto the navigator twice.
  final _handledMessageIds = <String>{};

  Future<void>? _initFuture;

  /// Idempotent — safe to call from main() and to await from
  /// registerForSession/unregisterForSession, which may run before main()'s
  /// fire-and-forget init() has finished (e.g. an auto-login on cold start).
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // ── Tap routing is wired FIRST, and without an await in between ────────
    //
    // A tap that launched the app is pushed over the FCM method channel the
    // moment the native plugin has somewhere to send it — on iOS that's when
    // it installs its UNUserNotificationCenter delegate during engine init,
    // i.e. before any Dart in this method has run. Flutter's channel buffers
    // hold that one message until the plugin's Dart handler exists, which
    // happens on the first touch of FirebaseMessaging.instance (below) — and
    // it is then drained on the next event-loop turn into
    // FirebaseMessagingPlatform.onMessageOpenedApp, a plain broadcast
    // controller that silently discards events with no listener.
    //
    // So the instance lookup and the listen() must sit in the same
    // synchronous block: any await between them (permission requests, channel
    // setup — all of which used to come first) lets the drain happen while
    // nobody is listening, and the tap is lost for good. That is exactly why
    // the first push tapped after a launch went nowhere while every later one
    // worked: only the first one races an unlistened stream.
    //
    // getInitialMessage() is not a safety net for this. It only ever returns
    // a message the app was launched *with* via
    // UIApplicationLaunchOptionsRemoteNotificationKey, and this app runs the
    // UIScene lifecycle (see Info.plist / SceneDelegate.swift), where a
    // notification tap is delivered to the notification-center delegate
    // instead and never appears in launchOptions — so on iOS it always
    // resolves to null. It is still awaited below because Android does
    // populate it, and it costs nothing there.
    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      debugPrint('PushService: onMessageOpenedApp fired data=${m.data}');
      _dispatchTap(m.data, messageId: m.messageId);
    });

    // Fire-and-forget: this is only for routing a cold-start tap, unrelated
    // to token registration. On this device it has been observed to hang
    // indefinitely (a known FlutterFire/iOS issue), which must never block
    // init() — registerForSession() awaits the same _initFuture.
    unawaited(_checkInitialMessage(messaging));

    await _initLocalNotifications();

    await messaging.requestPermission(alert: true, badge: true, sound: true);
    // No foreground presentation: while the app is open, pushes must not pop a
    // tray notification (the in-app UI reflects activity instead — see below).
    // This matters now that iOS has a UNUserNotificationCenter delegate set (in
    // AppDelegate, to make notification taps route): without turning these off,
    // FCM's foreground handler would start showing banners on iOS while the app
    // is open. Tap routing (didReceive) is unaffected by these options.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      final authToken = _authToken;
      if (authToken != null) unawaited(_postToken(authToken, token));
    });

    // A foreground listener that shows nothing.
    //
    // iOS only applies `aps.badge` when the app is *not* in front, so a
    // message arriving while somebody is reading the feed left the icon
    // showing the previous number — which is why DMs appeared not to count.
    // This sets the badge and does nothing else: no tray notification, per the
    // rule below.
    FirebaseMessaging.onMessage.listen((message) {
      final badge = int.tryParse('${message.data['badge']}');
      if (badge != null) unawaited(setBadge(badge));
    });

    // Deliberately no tray notification from that listener: while the app is
    // foregrounded (the only time that stream fires), pushes shouldn't
    // interrupt with one — matching Instagram, and per
    // explicit request not to notify while already inside the app. The
    // in-app UI (notifications bell, conversation view) reflects new
    // activity through its own existing polling instead.
  }

  Future<void> _checkInitialMessage(FirebaseMessaging messaging) async {
    try {
      // A secondary path only — on this app it carries a cold-start tap on
      // Android alone; iOS's scene lifecycle keeps launchOptions empty, so it
      // resolves to null there and onMessageOpenedApp does the work (see
      // _doInit). Anything it does return has already been deduped by message
      // id in _dispatchTap.
      //
      // On iOS it can still hang if it runs before the APNs device token has
      // been set — the same ordering dependency getToken() has — hence the
      // wait, which Android has no equivalent of.
      if (!kIsWeb && Platform.isIOS) await _waitForApnsToken();
      final initialMessage =
          await messaging.getInitialMessage().timeout(const Duration(seconds: 10));
      debugPrint('PushService: getInitialMessage=${initialMessage?.data}');
      if (initialMessage != null) {
        _dispatchTap(initialMessage.data, messageId: initialMessage.messageId);
      }
    } catch (e) {
      debugPrint('PushService._checkInitialMessage failed: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('ic_stat_neat');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          _dispatchTap(jsonDecode(payload) as Map<String, dynamic>);
        } catch (_) {}
      },
    );

    final androidImpl = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      _softChannelId,
      'Δραστηριότητα',
      description: 'Μου αρέσει, ακόλουθοι, σχόλια και άλλη δραστηριότητα',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    ));
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      _messagesChannelId,
      'Μηνύματα',
      description: 'Νέα προσωπικά μηνύματα',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
  }

  // ── App icon badge ───────────────────────────────────────────────────────

  // iOS only; on Android this channel has no handler and the call throws a
  // MissingPluginException, which is caught and ignored below.
  static const _badgeChannel = MethodChannel('com.neat/badge');

  /// Pulls the authoritative count from the server and stamps it on the app
  /// icon. Call whenever the unread counts may have moved — reading a
  /// conversation, opening the bell, coming back to the foreground.
  ///
  /// Pushes carry the same number in `aps.badge`, so they keep the icon right
  /// while the app is closed. Only the app itself can take it back down: iOS
  /// holds whatever the last push said until something writes a new value.
  Future<void> refreshBadge() async {
    final authToken = _authToken;
    if (kIsWeb || authToken == null) return;
    try {
      final res = await http
          .get(pushBadgeEndpoint, headers: authGetHeaders(authToken))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      await setBadge(int.tryParse('${decoded['badge']}') ?? 0);
    } catch (e) {
      // A badge that stays as it was is the right failure here — guessing
      // would be worse than leaving the last known number on the icon.
      debugPrint('PushService.refreshBadge failed: $e');
    }
  }

  /// Writes [count] straight onto the icon. Zero removes the bubble.
  Future<void> setBadge(int count) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _badgeChannel.invokeMethod('setBadge', count < 0 ? 0 : count);
    } catch (e) {
      debugPrint('PushService.setBadge failed: $e');
    }
  }

  // ── Session wiring (called from auth_gate.dart on login/logout) ─────────

  Future<void> registerForSession(String authToken) async {
    debugPrint('PushService.registerForSession: starting');
    _authToken = authToken;
    try {
      await init();
      debugPrint('PushService.registerForSession: init done');
      if (!kIsWeb && Platform.isIOS) await _waitForApnsToken();
      debugPrint('PushService.registerForSession: apns wait done, calling getToken');
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 15));
      debugPrint('PushService.registerForSession: getToken returned ${token == null ? 'null' : 'a token'}');
      if (token == null) return;
      _fcmToken = token;
      await _postToken(authToken, token);
      // The icon may be carrying a count from pushes that arrived while the
      // app was closed, some of which the user has since dealt with.
      unawaited(refreshBadge());
      debugPrint('PushService.registerForSession: done');
    } catch (e) {
      debugPrint('PushService.registerForSession failed: $e');
    }
  }

  /// On iOS, FirebaseMessaging.getToken() errors out ("APNS device token not
  /// set") if called before the native APNs token has round-tripped through
  /// Apple's servers via didRegisterForRemoteNotificationsWithDeviceToken —
  /// which requestPermission() only kicks off, it doesn't wait for it. This
  /// has no Android equivalent, and getToken()'s failure here was previously
  /// swallowed silently, so registration always silently failed on iOS.
  Future<void> _waitForApnsToken() async {
    final messaging = FirebaseMessaging.instance;
    for (var i = 0; i < 10; i++) {
      if (await messaging.getAPNSToken() != null) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('PushService: APNS token never arrived after 5s');
  }

  Future<void> unregisterForSession(String authToken) async {
    final token = _fcmToken;
    _authToken = null;
    // Nobody is signed in — a leftover count on the icon would belong to an
    // account this device no longer has.
    unawaited(setBadge(0));
    if (token == null) return;
    try {
      await http.post(
        unregisterDeviceEndpoint,
        headers: authJsonHeaders(authToken),
        body: jsonEncode({'token': token}),
      );
    } catch (e) {
      debugPrint('PushService.unregisterForSession failed: $e');
    }
  }

  /// A stable id for this phone, so the server can retire the token it
  /// replaces.
  ///
  /// FCM issues a new token on reinstall and gives no way to connect it to the
  /// old one, so every reinstall left another live registration behind and
  /// every notification arrived once per leftover. Kept in the keychain rather
  /// than in preferences deliberately: on iOS the keychain survives deleting
  /// the app, so a reinstall is recognised as the same phone instead of
  /// looking like a new one all over again.
  static const _deviceIdKey = 'neat_device_id';

  Future<String> _deviceId() async {
    const storage = FlutterSecureStorage();
    try {
      final existing = await storage.read(key: _deviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final fresh = '${DateTime.now().microsecondsSinceEpoch}-'
          '${Random().nextInt(1 << 32)}';
      await storage.write(key: _deviceIdKey, value: fresh);
      return fresh;
    } catch (e) {
      debugPrint('PushService._deviceId failed: $e');
      return '';
    }
  }

  Future<void> _postToken(String authToken, String fcmToken) async {
    try {
      final deviceId = await _deviceId();
      final res = await http
          .post(
            registerDeviceEndpoint,
            headers: authJsonHeaders(authToken),
            body: jsonEncode({
              'token': fcmToken,
              'platform': Platform.isIOS ? 'ios' : 'android',
              if (deviceId.isNotEmpty) 'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('PushService._postToken: response ${res.statusCode}');
    } catch (e) {
      debugPrint('PushService._postToken failed: $e');
    }
  }

  // ── Tap → navigate ───────────────────────────────────────────────────────

  void _dispatchTap(Map<String, dynamic> data, {String? messageId}) {
    debugPrint('PushService._dispatchTap: type=${data['type']} id=$messageId '
        'dmHandler=${onDmTap != null} notifHandler=${onNotificationTap != null} data=$data');
    if (messageId != null && !_handledMessageIds.add(messageId)) {
      debugPrint('PushService._dispatchTap: already routed $messageId, ignoring');
      return;
    }
    if (data['type'] == 'dm') {
      final id = int.tryParse('${data['conversationId']}');
      if (id == null) return;
      final handler = onDmTap;
      if (handler != null) {
        handler(id);
      } else {
        _pendingConversationId = id;
      }
    } else if (data['type'] == 'notification') {
      // Activity push: navigate to the exact target (post/comment). Fall back
      // to just opening the notifications bell if the rich handler isn't wired.
      final handler = onNotificationTap;
      if (handler != null) {
        handler(data);
      } else if (onSoftTap != null) {
        onSoftTap!();
      } else {
        _pendingNotificationData = data;
      }
    } else {
      final handler = onSoftTap;
      if (handler != null) {
        handler();
      } else {
        _pendingSoft = true;
      }
    }
  }

  /// Called once HomePage has registered [onDmTap]/[onSoftTap], in case a
  /// push was tapped before the handlers existed (cold start).
  void replayPending() {
    debugPrint('PushService.replayPending: dm=$_pendingConversationId '
        'notif=${_pendingNotificationData != null} soft=$_pendingSoft');
    final id = _pendingConversationId;
    if (id != null) {
      _pendingConversationId = null;
      onDmTap?.call(id);
    }
    final notifData = _pendingNotificationData;
    if (notifData != null) {
      _pendingNotificationData = null;
      if (onNotificationTap != null) {
        onNotificationTap!(notifData);
      } else {
        onSoftTap?.call();
      }
    }
    if (_pendingSoft) {
      _pendingSoft = false;
      onSoftTap?.call();
    }
  }
}
