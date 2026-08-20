import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:giphy_flutter_sdk/giphy_dialog.dart';
import 'package:giphy_flutter_sdk/dto/giphy_content_type.dart';
import 'package:giphy_flutter_sdk/dto/giphy_media.dart';
import 'package:giphy_flutter_sdk/dto/giphy_settings.dart';
import 'package:giphy_flutter_sdk/dto/giphy_theme.dart';
import '../core/http_client.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../core/api.dart';
import '../core/avatar_store.dart';
import '../core/link_preview.dart';
import '../core/media_cache.dart';
import '../core/mentions.dart';
import '../core/models.dart';
import '../core/neat_loader.dart';
import '../core/post_card.dart';
import '../core/push_service.dart';
import '../core/realtime_service.dart';
import '../core/report_post_sheet.dart';
import '../core/share_sheet.dart';
import '../events/events_page.dart';
import '../map/city_map_view.dart';
import '../map/spectator_intro_page.dart';
import '../messages/messages_page.dart';
import '../profile/profile_page.dart';

// Top-level so it can run on a background isolate via `compute`. Decoding a
// large city feed and mapping every entry to a FeedPost is CPU work that would
// otherwise block the UI isolate (janking the frame on load/refresh). Must stay
// a pure top-level function with no captured state for `compute` to accept it.
/// One page of the feed, as the server sends it.
class _FeedPage {
  const _FeedPage(this.posts, {this.hasMore = false});
  final List<FeedPost> posts;
  final bool hasMore;
}

/// Parses either shape the feed can arrive in.
///
/// The current one is `{posts, avatars, has_more}`: a page rather than the
/// whole city, and each author's avatar sent once by name instead of copied
/// into every post they have ever made. The bare list is what a server that
/// predates that sends, and what the cache on disk may still hold.
_FeedPage _parseFeedPosts(String body) {
  final decoded = jsonDecode(body);
  if (decoded is List) {
    return _FeedPage(
      decoded.whereType<Map<String, dynamic>>().map(FeedPost.fromJson).toList(),
    );
  }
  final page = decoded as Map<String, dynamic>;
  final avatars = (page['avatars'] as Map<String, dynamic>? ?? const {});
  final posts = (page['posts'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((json) {
        // Put each author's picture back on their posts, so everything
        // downstream sees the same FeedPost it always did.
        final author = json['author']?.toString() ?? '';
        final avatar = avatars[author]?.toString() ?? '';
        if (avatar.isNotEmpty) json['avatarUrl'] = avatar;
        return FeedPost.fromJson(json);
      })
      .toList();
  return _FeedPage(posts, hasMore: page['has_more'] == true);
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.session,
    required this.onSessionChanged,
    required this.onLogout,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final AuthSession session;
  final ValueChanged<AuthSession> onSessionChanged;
  final Future<void> Function() onLogout;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

const _kSpectatorIntroSeenKey = 'neat_spectator_intro_seen';

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static final _kTabChannel = const MethodChannel('com.neat/tabbar');

  final TextEditingController _compose = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<FeedPost> _posts = [];
  final List<NotificationItem> _notificationsList = [];
  final Set<String> _followingAuthors = {};
  final List<UserProfile> _followingProfiles = [];
  final Set<String> _followerAuthors = {};
  final _cityScroll = ScrollController();
  final _followingScroll = ScrollController();
  int _nav = 0;
  // Null until SharedPreferences has been read; the map tab simply behaves as
  // "already seen" during that window rather than risking a late intro.
  bool _spectatorIntroSeen = true;
  int _selectedTab = 0;
  final Set<int> _visitedTabs = <int>{0};
  final _viralViewKey = GlobalKey<_ViralViewState>();
  bool _loading = true;
  bool _isOffline = false;
  String? _activeCity;
  int _profileRefreshKey = 0;
  final _composeMedia = <_ComposeMedia>[];
  bool _composeMediaLoading = false;
  bool _posting = false;

  /// Fraction of the compose upload's bytes written, or null while there is
  /// nothing large enough in flight to be worth a determinate bar.
  /// Fraction of the media currently going up, or null when nothing is.
  ///
  /// A notifier rather than state: the upload now starts when media is picked
  /// and runs while the caption is being written, so it has to drive the
  /// compose sheet's indicator from outside that sheet's own setState.
  final ValueNotifier<double?> _uploadProgress = ValueNotifier<double?>(null);

  /// What the top banner says while a post is being delivered, or null when
  /// there is nothing to report.
  final ValueNotifier<String?> _postingLabel = ValueNotifier<String?>(null);

  /// The client carrying the current upload, kept so it can be aborted.
  ///
  /// Uploads go through their own client rather than the shared one because
  /// closing a client is what cancels its in-flight request — and closing the
  /// shared one would take every other request in the app down with it.
  http.Client? _uploadClient;
  bool _cancelledUpload = false;

  /// Follow-up refresh while a just-posted video is still encoding.
  /// See _scheduleProcessingRefresh.
  Timer? _processingPollTimer;
  int _processingPolls = 0;
  static const _kProcessingPollLimit = 24;
  bool _composePollActive = false;
  final _composePollControllers = <TextEditingController>[];
  int _unreadMessages = 0;
  bool _hasOfficialEvents = false;
  String? _returningToCity;
  bool _showInlineProfile = false;
  String _inlineProfileUsername = '';
  int? _inlinePostId;
  bool _isIOS26 = false;
  int _navBarHideCount = 0; // reference count; bar only shows when this reaches 0
  // One WebSocket connection for the whole logged-in session (native only —
  // see realtime_service.dart); owned here and handed down to the messaging
  // and profile screens so it survives navigating between them.
  late final RealtimeService _realtime = RealtimeService(token: widget.session.token);
  StreamSubscription<RealtimeEvent>? _realtimeBadgeSub;

  @override
  void initState() {
    super.initState();
    AvatarStore.revision.addListener(_onAvatarRevisionChanged);
    _setupNativeTabChannel();
    // Paint last-known posts instantly instead of a blank spinner while the
    // network round-trip for fresh ones is still in flight.
    unawaited(_loadCachedPosts());
    unawaited(_restoreSpectatorIntroSeen());
    _load();
    _loadNotifications(silent: true);
    PushService.instance.onDmTap = _openConversationById;
    PushService.instance.onSoftTap = _openNotifications;
    PushService.instance.onNotificationTap = _openNotificationTargetFromPush;
    // Deferred by one frame rather than replayed inline: a push tapped from a
    // killed app now reliably lands in PushService before this screen exists
    // (see push_service.dart), so this is the path that actually routes a
    // cold-start tap — and the handlers above open sheets and push routes,
    // which need Theme.of/Navigator.of. Those throw if called before
    // initState has returned, and the navigator isn't mounted yet either.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PushService.instance.replayPending();
    });
    _realtime.start();
    // Instant nav-badge updates on native, on top of the existing on-demand
    // refresh triggers below — web has no RealtimeService, so this stream
    // simply never fires there.
    _realtimeBadgeSub = _realtime.events.listen((_) => _loadUnreadMessages());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Pushes that landed while the app was away have moved the icon badge on
    // their own, and the user may have read some of it on another device.
    // Recounting on the way back keeps the icon and the in-app counts honest.
    // Deliberately a recount, not a clear: the badge is meant to survive
    // merely opening the app, and only fall as things are actually read.
    if (state == AppLifecycleState.resumed) unawaited(_loadUnreadMessages());
  }

  bool _cityMapPrewarmed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Warm the Map tab's WebView in the background as soon as home loads,
    // well before the user actually taps the tab — the Map tab itself still
    // mounts lazily on first visit, but by then the slow part (mapkit.js
    // parse) is already done.
    if (!_cityMapPrewarmed) {
      _cityMapPrewarmed = true;
      unawaited(prewarmCityMap(
        homeCity: widget.session.user.city,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ));
    }
  }

  void _setupNativeTabChannel() {
    _kTabChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTabTapped':
          _onNavTap(call.arguments as int);
        case 'nativeTabBarReady':
          // The bar came up after this screen did — the ordering on a warm
          // start with a restored session.
          _adoptNativeTabBar();
      }
    });
    // ...and the other ordering: the bar was built at engine init, which is
    // what happens when the user signs up or logs in, because HomePage only
    // exists minutes later. That push is long gone, so ask instead of wait —
    // otherwise the native bar stays hidden and Flutter draws its own until
    // the app is relaunched.
    unawaited(_askForNativeTabBar());
  }

  Future<void> _askForNativeTabBar() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      final ready = await _kTabChannel.invokeMethod<bool>('isNativeTabBarReady');
      if (ready == true) _adoptNativeTabBar();
    } on PlatformException catch (_) {
      // Pre-iOS 26: the channel exists but the handler doesn't. Flutter's own
      // bar stays, which is the correct outcome there.
    } on MissingPluginException catch (_) {
      // Android and older builds — same story.
    }
  }

  /// Hands the bottom bar over to the native one: Flutter's own is replaced by
  /// a placeholder, and the native bar is unhidden unless something on screen
  /// is deliberately holding it down.
  void _adoptNativeTabBar() {
    if (!mounted) return;
    if (!_isIOS26) setState(() => _isIOS26 = true);
    if (_navBarHideCount == 0) _kTabChannel.invokeMethod('showTabBar');
    _syncNativeProfileIcon();
  }

  @override
  void dispose() {
    // A socket left open by a screen that no longer exists.
    _uploadClient?.close();
    _uploadClient = null;
    AvatarStore.revision.removeListener(_onAvatarRevisionChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (_isIOS26) _kTabChannel.invokeMethod('hideTabBar');
    _kTabChannel.setMethodCallHandler(null);
    if (identical(PushService.instance.onDmTap, _openConversationById)) {
      PushService.instance.onDmTap = null;
    }
    if (identical(PushService.instance.onSoftTap, _openNotifications)) {
      PushService.instance.onSoftTap = null;
    }
    if (identical(PushService.instance.onNotificationTap, _openNotificationTargetFromPush)) {
      PushService.instance.onNotificationTap = null;
    }
    _processingPollTimer?.cancel();
    _uploadProgress.dispose();
    _postingLabel.dispose();
    _compose.dispose();
    for (final c in _composePollControllers) { c.dispose(); }
    _cityScroll.dispose();
    _followingScroll.dispose();
    _realtimeBadgeSub?.cancel();
    _realtime.dispose();
    super.dispose();
  }


  String get _postsCacheKey =>
      _activeCity == null ? 'cached_posts_home' : 'cached_posts_city_$_activeCity';

  Future<void> _saveCachedPosts(String rawBody) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_postsCacheKey, rawBody);
    } catch (_) {}
  }

  Future<void> _loadCachedPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_postsCacheKey);
      if (raw == null || !mounted) return;
      final page = await compute(_parseFeedPosts, raw);
      if (mounted) {
        setState(() {
          _posts
            ..clear()
            ..addAll(page.posts);
          _loading = false;
        });
      }
    } catch (_) {}
  }

  /// Whether the server said there are posts older than the ones we hold.
  bool _hasOlderPosts = false;
  bool _loadingOlderPosts = false;

  Future<void> _load() async {
    try {
      final res = await http.get(
        postsEndpoint(fresh: true, city: _activeCity),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode == 401) return widget.onLogout();
      final page = await compute(_parseFeedPosts, res.body);
      unawaited(_saveCachedPosts(res.body));
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _hasOlderPosts = page.hasMore;
        _loading = false;
        _isOffline = false;
      });
      _scheduleProcessingRefresh();
      await Future.wait([_loadFollowingAuthors(), _loadFollowerAuthors(), _loadUnreadMessages(), _loadOfficialEventsBadge()]);
    } catch (_) {
      await _loadCachedPosts();
      if (mounted) setState(() { _loading = false; _isOffline = true; });
    }
  }

  /// Re-fetches the feed while any video in it is still being encoded.
  ///
  /// A post now reaches the feed a few seconds before its video does, so
  /// without this the poster would sit looking at their own "Processing video"
  /// tile until they thought to pull-to-refresh. Only runs when something is
  /// actually processing, and gives up after [_kProcessingPollLimit] tries so a
  /// video that never finishes can't leave the app polling forever.
  void _scheduleProcessingRefresh() {
    _processingPollTimer?.cancel();
    final processing = _posts.any((p) => p.media.any((m) => m.isProcessing));
    if (!processing) {
      _processingPolls = 0;
      return;
    }
    if (_processingPolls >= _kProcessingPollLimit) return;
    _processingPolls++;
    _processingPollTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _loadUnreadMessages() async {
    try {
      final res = await http.get(inboxEndpoint, headers: authGetHeaders(widget.session.token));
      if (res.statusCode != 200 || !mounted) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final convs = (decoded['conversations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      final unread = convs
          .where((c) => c['otherUser']?.toString() != widget.session.user.username)
          .fold<int>(0, (sum, c) => sum + (int.tryParse(c['unreadCount']?.toString() ?? '') ?? 0));
      if (mounted) setState(() => _unreadMessages = unread);
    } catch (_) {}
    // This runs at every point the unread counts can move — first load, a
    // realtime event, returning from a conversation — which is exactly when
    // the icon badge needs restating. Pushes can only ever raise it.
    unawaited(PushService.instance.refreshBadge());
  }

  Future<void> _loadOfficialEventsBadge() async {
    try {
      final city = _activeCity ?? widget.session.user.city;
      if (city.isEmpty) return;
      final res = await http.get(
        eventsEndpoint(city: city, type: 'official'),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode != 200 || !mounted) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final events = (decoded['events'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();
      final today = DateTime.now();
      final todayMidnight = DateTime(today.year, today.month, today.day);
      final upcomingIds = events
          .where((e) {
            final dateStr = e['date']?.toString() ?? e['eventDate']?.toString() ?? e['event_date']?.toString() ?? e['scheduledAt']?.toString() ?? '';
            if (dateStr.isEmpty) return true;
            final d = DateTime.tryParse(dateStr);
            if (d == null) return true;
            return !DateTime(d.year, d.month, d.day).isBefore(todayMidnight);
          })
          .map((e) => e['id']?.toString() ?? e['eventId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final prefs = await SharedPreferences.getInstance();
      final seenIds = (prefs.getStringList('seen_official_event_ids_$city') ?? []).toSet();
      final hasNew = upcomingIds.any((id) => !seenIds.contains(id));
      if (mounted) setState(() => _hasOfficialEvents = hasNew);
    } catch (_) {}
  }

  Future<void> _markOfficialEventsSeen() async {
    try {
      final city = _activeCity ?? widget.session.user.city;
      if (city.isEmpty) return;
      final res = await http.get(
        eventsEndpoint(city: city, type: 'official'),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final ids = (decoded['events'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => e['id']?.toString() ?? e['eventId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('seen_official_event_ids_$city', ids);
    } catch (_) {}
  }

  Future<void> _loadFollowingAuthors() async {
    try {
      final res = await http.get(
        followingEndpoint(widget.session.user.username),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode == 401) return widget.onLogout();
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _followingAuthors
          ..clear()
          ..addAll(users.map((user) => user.username));
        _followingProfiles
          ..clear()
          ..addAll(users);
      });
    } catch (_) {}
  }

  Future<void> _loadFollowerAuthors() async {
    try {
      final res = await http.get(
        followersEndpoint(widget.session.user.username),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((j) => j['username']?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toSet();
      if (!mounted) return;
      setState(() {
        _followerAuthors
          ..clear()
          ..addAll(users);
      });
    } catch (_) {}
  }

  static const _kNotifCacheKey = 'neat_notifications_cache';

  Future<void> _saveNotificationsCache(List<dynamic> raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kNotifCacheKey, jsonEncode(raw));
    } catch (_) {}
  }

  Future<List<NotificationItem>> _loadNotificationsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kNotifCacheKey);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(NotificationItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    try {
      final res = await http.get(
        notificationsEndpoint,
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode == 401) return widget.onLogout();
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final rawList = (decoded['notifications'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      unawaited(_saveNotificationsCache(rawList));
      final notifications = rawList.map(NotificationItem.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _notificationsList
          ..clear()
          ..addAll(notifications);
      });
    } catch (_) {
      // On offline: populate from cache so badge count stays accurate
      final cached = await _loadNotificationsCache();
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _notificationsList
            ..clear()
            ..addAll(cached);
        });
      }
    }
  }

  Future<List<NotificationItem>> _fetchNotifications() async {
    try {
      final res = await http.get(
        notificationsEndpoint,
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode == 401) {
        await widget.onLogout();
        return const [];
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final rawList = (decoded['notifications'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      unawaited(_saveNotificationsCache(rawList));
      return rawList.map(NotificationItem.fromJson).toList();
    } catch (_) {
      return _loadNotificationsCache();
    }
  }

  Future<void> _markNotificationsRead(Iterable<NotificationItem> items) async {
    final ids = items
        .where((item) => !item.isRead)
        .map((item) => item.id)
        .toList();
    if (ids.isEmpty) return;
    await http.post(
      notificationsEndpoint,
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({'ids': ids}),
    );
    if (!mounted) return;
    setState(() {
      for (final item in _notificationsList) {
        if (ids.contains(item.id)) {
          final index = _notificationsList.indexOf(item);
          if (index != -1) {
            _notificationsList[index] = NotificationItem(
              id: item.id,
              actor: item.actor,
              actorAvatarUrl: item.actorAvatarUrl,
              verb: item.verb,
              targetType: item.targetType,
              targetId: item.targetId,
              targetText: item.targetText,
              imageUrl: item.imageUrl,
              videoUrl: item.videoUrl,
              isRead: true,
              created: item.created,
            );
          }
        }
      }
    });
    // Half the icon badge is unread activity, so clearing some of it here has
    // to be reflected on the icon too.
    unawaited(PushService.instance.refreshBadge());
  }

  static const _kMaxImageBytes = 6 * 1024 * 1024; // 6 MB per image

  /// Ceiling for a picked video, in bytes.
  ///
  /// This is what the length limit actually was: at the ~17 Mbit/s a phone
  /// shoots 1080p at, the old 20 MB cap rejected anything past roughly five
  /// seconds, whatever [_kMaxVideoDuration] said. 140 MB clears a minute of
  /// 1080p with room to spare and still sits under the server's 150 MB cap.
  /// Nothing is served at this size — the box re-encodes every upload to
  /// 960p/2 Mbit/s — so it only bounds what has to travel up the wire.
  static const _kMaxVideoBytes = 140 * 1024 * 1024; // 140 MB per video
  static const _kMaxVideoDuration = Duration(minutes: 3);

  /// Closes the sheet and posts behind you.
  ///
  /// Posting used to hold the compose sheet open for the whole upload, which
  /// on a phone connection is a minute of staring at a spinner for something
  /// you have already decided to do. The sheet now closes on the tap and the
  /// work continues in the background, with a bar at the top of the feed
  /// carrying the progress — the same thing Instagram does, and the reason
  /// posting there feels instant even when the upload is not.
  Future<void> _createPost(StateSetter setPageState) async {
    final text = _compose.text.trim();
    if (text.isEmpty || _posting) return;

    // Everything the delivery needs, taken before the sheet is torn down.
    final media = List<_ComposeMedia>.from(_composeMedia);
    final pollOptions = _composePollActive
        ? _composePollControllers
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList()
        : <String>[];

    Navigator.of(context).pop();
    _compose.clear();
    setState(() {
      _composeMedia.clear();
      _composePollActive = false;
      for (final c in _composePollControllers) {
        c.dispose();
      }
      _composePollControllers.clear();
    });

    unawaited(_deliverPost(text, media, pollOptions));
  }

  /// Uploads and creates the post, with nothing waiting on it.
  Future<void> _deliverPost(
    String text,
    List<_ComposeMedia> media,
    List<String> pollOptions,
  ) async {
    // Only counts as a big upload if the bytes still have to go now — a video
    // already staged while the caption was written costs a few hundred bytes.
    final hasVideo = media.any(
      (m) => m.isVideo && m.videoPath != null && m.uploadId == null,
    );
    setState(() => _posting = true);
    _postingLabel.value = AppLocalizations.of(context).postingLabel;
    // Only start from zero if nothing is already in flight. Pressing Post
    // while the staged upload is at 60% must not send the bar back to the
    // start — it is the same bytes, still going.
    if (hasVideo && _uploadProgress.value == null) _uploadProgress.value = 0;
    try {
      final request = _ProgressMultipartRequest(
        'POST',
        postsEndpoint(),
        onProgress: (sent, total) {
          if (!hasVideo || total <= 0 || !mounted) return;
          final next = sent / total;
          // Repaint on whole percentage points only — a chunk callback fires
          // far more often than a progress ring can usefully change.
          final shown = _uploadProgress.value;
          if (shown != null && (next - shown).abs() < 0.01 && next < 1) return;
          _uploadProgress.value = next;
        },
      )..headers['Authorization'] = 'Token ${widget.session.token}';
      request.fields['text'] = text;

      // Anything still going up gets waited on here rather than re-sent. By
      // this point it has had the whole caption-writing to finish, so it is
      // usually already done and this returns immediately.
      for (final m in media) {
        if (m.uploadId == null && m.staging != null) {
          await m.staging;
        }
      }

      final mediaInfo = <Map<String, dynamic>>[];
      int fileIndex = 0;
      for (final m in media) {
        if (m.externalUrl != null) {
          mediaInfo.add({'type': m.type, 'url': m.externalUrl!, 'order': mediaInfo.length});
        } else if (m.uploadId != null) {
          // Already on the server; the post carries only its id.
          mediaInfo.add({
            'type': m.type,
            'upload_id': m.uploadId,
            'order': mediaInfo.length,
          });
        } else if (m.isVideo && m.videoPath != null) {
          mediaInfo.add({'type': 'video', 'file_index': fileIndex, 'order': mediaInfo.length});
          request.files.add(await http.MultipartFile.fromPath(
            'media_$fileIndex',
            m.videoPath!,
            filename: 'video.mp4',
          ));
          fileIndex++;
        } else if (m.imageBytes != null) {
          mediaInfo.add({'type': 'image', 'file_index': fileIndex, 'order': mediaInfo.length});
          request.files.add(http.MultipartFile.fromBytes(
            'media_$fileIndex',
            m.imageBytes!,
            filename: 'image.jpg',
          ));
          fileIndex++;
        }
      }
      request.fields['media'] = jsonEncode(mediaInfo);

      if (pollOptions.length >= 2) {
        request.fields['poll'] = jsonEncode({'options': pollOptions});
      }

      // Generous, because it has to cover both the wire time for up to 140 MB
      // on a phone connection and the server-side transcode that follows it.
      // The progress ring is what tells the user it is alive; this only has to
      // be long enough not to kill an upload that is genuinely still moving.
      final client = http.Client();
      _uploadClient = client;
      _cancelledUpload = false;
      final streamed = await client
          .send(request)
          .timeout(Duration(seconds: hasVideo ? 900 : 180));
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode == 201) {
        // Deliberately does not navigate anywhere. The sheet closed when Post
        // was tapped and the user has been reading the feed ever since —
        // yanking them to their profile now would be the app grabbing the
        // wheel back long after they let go.
        if (mounted) {
          _postingLabel.value = AppLocalizations.of(context).postShared;
          _load();
          Future<void>.delayed(const Duration(seconds: 2), () {
            if (mounted) _postingLabel.value = null;
          });
        }
      } else if (res.statusCode == 413) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).fileTooLarge)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyHttpError(res))),
        );
      }
    } catch (e) {
      // An aborted upload throws on the way out; that is the user's own doing,
      // not a failure to report back to them.
      if (mounted && !_cancelledUpload) {
        final msg = e.toString().contains('TimeoutException')
            ? AppLocalizations.of(context).uploadTimedOut
            : AppLocalizations.of(context).networkError;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      _uploadClient?.close();
      _uploadClient = null;
      if (mounted) {
        setState(() {
          _posting = false;
        });
        _uploadProgress.value = null;
      }
    }
  }

  /// Stops an upload in progress and lets the sheet close.
  ///
  /// Closing the client aborts the request it is carrying — the only way to
  /// actually stop a send in flight. Without this, Cancel and the media X were
  /// both dead while a video uploaded: the sheet refused to pop, the buttons
  /// were disabled, and a minute-long upload (or a stalled one) left the user
  /// with nowhere to go but force-quitting the app.
  void _cancelUpload() {
    if (!_posting) return;
    _cancelledUpload = true;
    _uploadClient?.close();
    _uploadClient = null;
    if (mounted) {
      setState(() => _posting = false);
      _uploadProgress.value = null;
      // Left standing only when it says "Posted", which clears itself.
      if (_postingLabel.value == AppLocalizations.of(context).postingLabel) {
        _postingLabel.value = null;
      }
    }
  }

  Future<void> _pickComposeImages(StateSetter setPageState) async {
    final remaining = 4 - _composeMedia.where((m) => !m.isVideo).length;
    if (remaining <= 0) return;
    final picked = await _imagePicker.pickMultiImage(
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _composeMediaLoading = true);
    setPageState(() {});
    final toAdd = picked.take(remaining);
    final newItems = <_ComposeMedia>[];
    int skipped = 0;
    for (final f in toAdd) {
      final fileSize = await f.length();
      if (fileSize > _kMaxImageBytes) {
        skipped++;
        continue;
      }
      final bytes = await f.readAsBytes();
      newItems.add(_ComposeMedia.localImage(imageBytes: bytes));
    }
    if (!mounted) return;
    setState(() {
      _composeMediaLoading = false;
      _composeMedia.removeWhere((m) => m.isVideo);
      _composeMedia.addAll(newItems);
    });
    for (final item in newItems) {
      _beginStaging(item);
    }
    setPageState(() {});
    if (skipped > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photosSkipped(skipped)),
        ),
      );
    }
  }

  Future<void> _pickComposeCamera(StateSetter setPageState) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    setState(() => _composeMediaLoading = true);
    setPageState(() {});
    final fileSize = await picked.length();
    if (!mounted) return;
    if (fileSize > _kMaxImageBytes) {
      setState(() => _composeMediaLoading = false);
      setPageState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).photoTooLarge)),
      );
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _composeMediaLoading = false;
      _composeMedia.removeWhere((m) => m.isVideo);
      _composeMedia.add(_ComposeMedia.localImage(imageBytes: bytes));
    });
    _beginStaging(_composeMedia.last);
    setPageState(() {});
  }

  Future<void> _pickComposeVideo(StateSetter setPageState) async {
    final picked = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: _kMaxVideoDuration,
    );
    if (picked == null || !mounted) return;

    // Straight to the compose sheet. Compressing takes twenty to forty seconds
    // for a minute of video, and it used to happen right here, in front of a
    // spinner, with the network idle throughout — so the wait was the encode
    // *and then* the upload. Both still happen; they now happen behind this
    // sheet, while the caption is being written, which is the same span of
    // time. See _prepareAndStage.
    //
    // The size check moved with it: how big the file ends up is not known
    // until compression has run, so an oversized video is reported from there.
    setState(() {
      _composeMediaLoading = false;
      _composeMedia.clear();
      _composeMedia.add(_ComposeMedia.localVideo(videoPath: picked.path));
    });
    _beginStaging(_composeMedia.last);
    setPageState(() {});
  }

  /// Re-encodes [sourcePath] to something worth uploading, or returns it
  /// unchanged if that fails.
  ///
  /// Never fatal: a phone that refuses to compress (an unusual codec, no
  /// hardware encoder, a plugin that throws) should still be able to post its
  /// video, just slowly. That is the old behaviour, so falling back to it
  /// cannot be a regression.
  Future<String> _compressVideo(String sourcePath) async {
    try {
      final info = await VideoCompress.compressVideo(
        sourcePath,
        // 1080p, matching the server's own target exactly
        // (_TARGET_MAX_EDGE in posts/transcode.py). The match is what matters
        // as much as the number: when the two disagree the server re-encodes
        // every upload, which is twenty seconds of "processing" instead of
        // about one. They have to be changed together.
        quality: VideoQuality.Res1920x1080Quality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final out = info?.path;
      if (out == null || out.isEmpty) return sourcePath;
      // Trust it only if it actually came out smaller; some sources compress
      // to something larger than they started.
      final before = await File(sourcePath).length();
      final after = await File(out).length();
      if (after <= 0 || after >= before) return sourcePath;
      debugPrint(
        '[compose] video ${(before / 1048576).toStringAsFixed(1)} MB -> '
        '${(after / 1048576).toStringAsFixed(1)} MB',
      );
      return out;
    } catch (e) {
      debugPrint('[compose] compression unavailable, uploading original: $e');
      return sourcePath;
    }
  }

  /// Starts uploading a picked file immediately, returning its staged id.
  ///
  /// This is the whole point of the compose flow: picking a video and writing
  /// a caption are the same span of time, and the upload used to wait for the
  /// end of it. Failing here is not fatal — the media simply travels with the
  /// post request as it always did.
  Future<String?> _stageUpload(_ComposeMedia media) async {
    try {
      // Reports as it goes, so the compose sheet can show the video climbing
      // while the caption is being written. Without this the indicator sat at
      // 0% for the whole upload — the bytes were moving, nothing was watching.
      final request = _ProgressMultipartRequest(
        'POST',
        stageUploadEndpoint,
        onProgress: (sent, total) {
          if (total <= 0) return;
          final next = sent / total;
          final shown = _uploadProgress.value;
          if (shown != null && (next - shown).abs() < 0.01 && next < 1) return;
          _uploadProgress.value = next;
        },
      )
        ..headers.addAll(authGetHeaders(widget.session.token))
        ..fields['type'] = media.type;

      final videoFile = media.uploadPath ?? media.videoPath;
      if (videoFile != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'file', videoFile, filename: 'video.mp4'));
      } else if (media.imageBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file', media.imageBytes!, filename: 'image.jpg'));
      } else {
        return null; // a Giphy URL has nothing to upload
      }

      final res = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 900)),
      );
      if (res.statusCode != 201) {
        debugPrint('[compose] staging refused: ${res.statusCode}');
        return null;
      }
      final id = (jsonDecode(res.body) as Map<String, dynamic>)['id']?.toString();
      media.uploadId = id;
      _uploadProgress.value = null;
      debugPrint('[compose] staged ${media.type} as $id');
      return id;
    } catch (e) {
      // Not fatal: the file travels with the post request instead, exactly as
      // it did before staging existed.
      _uploadProgress.value = null;
      debugPrint('[compose] staging failed, will send with the post: $e');
      return null;
    }
  }

  /// Kicks off preparing and staging for [media] without waiting for either.
  ///
  /// Pressing Post before this finishes is already handled: the post awaits
  /// `media.staging`, and that future now covers the compression too.
  void _beginStaging(_ComposeMedia media) {
    media.staging = _prepareAndStage(media);
    unawaited(media.staging!);
  }

  /// Compresses if it is worth it, then uploads — all behind the compose sheet.
  ///
  /// Compression used to run *before* the sheet appeared, so picking a minute
  /// of video meant twenty to forty seconds of a spinner with the network
  /// completely idle, and only then an upload. The phone encoding and the
  /// bytes leaving are both unavoidable; making the user watch the first one
  /// finish before the second can start is not.
  Future<String?> _prepareAndStage(_ComposeMedia media) async {
    if (media.isVideo && media.videoPath != null) {
      if (mounted) setState(() => media.preparing = true);
      final prepared = await _prepareVideo(media.videoPath!);
      if (mounted) setState(() => media.preparing = false);
      if (!mounted) return null;
      final size = await File(prepared).length();
      if (size > _kMaxVideoBytes) {
        // Only knowable once compression has run, so it is reported here
        // rather than at the picker.
        _rejectOversizeVideo(media, size);
        return null;
      }
      media.uploadPath = prepared;
    }
    return _stageUpload(media);
  }

  /// Drops a video that turned out too big even after compressing.
  void _rejectOversizeVideo(_ComposeMedia media, int size) {
    if (!mounted) return;
    setState(() => _composeMedia.remove(media));
    _uploadProgress.value = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).videoTooLarge(
            (size / 1024 / 1024).round(),
            _kMaxVideoBytes ~/ (1024 * 1024),
          ),
        ),
      ),
    );
  }

  /// The file worth uploading for [sourcePath].
  ///
  /// Re-encoding is skipped when the source is already within what the server
  /// targets, mirroring `needs_reencode` in posts/transcode.py. The client
  /// cannot read the codec, but the codec is not what costs the user anything
  /// — the bytes are — so the decision is made on resolution and bitrate, and
  /// the server still remuxes or re-encodes in the background if it must.
  Future<String> _prepareVideo(String sourcePath) async {
    if (!await _needsCompressing(sourcePath)) {
      debugPrint('[compose] already within target, uploading as picked');
      return sourcePath;
    }
    return _compressVideo(sourcePath);
  }

  /// Matches the server's own thresholds; see _TARGET_MAX_EDGE and
  /// _TARGET_MAX_BITRATE in posts/transcode.py. They have to move together.
  static const _kTargetMaxEdge = 1920;
  static const _kTargetMaxBitrate = 6000000; // bits per second

  Future<bool> _needsCompressing(String path) async {
    try {
      final info = await VideoCompress.getMediaInfo(path);
      final width = info.width ?? 0;
      final height = info.height ?? 0;
      final durationMs = info.duration ?? 0;
      final size = info.filesize ?? 0;
      // Anything we cannot measure is compressed: guessing wrong the other way
      // ships an oversized file over a mobile connection.
      if (width <= 0 || height <= 0 || durationMs <= 0 || size <= 0) return true;
      if (width > _kTargetMaxEdge && height > _kTargetMaxEdge) return true;
      if (width.toInt() > _kTargetMaxEdge || height.toInt() > _kTargetMaxEdge) {
        return true;
      }
      final bitrate = size * 8 / (durationMs / 1000);
      return bitrate > _kTargetMaxBitrate;
    } catch (e) {
      debugPrint('[compose] could not inspect video, compressing: $e');
      return true;
    }
  }

  void _removeComposeMedia(int index, StateSetter setPageState) {
    // Mid-upload the request already holds its own copy of this list, so
    // removing an item here changed nothing visible and the X looked broken.
    // Taking the media out of a post that is being sent means stopping it.
    if (_posting) _cancelUpload();
    setState(() => _composeMedia.removeAt(index));
    setPageState(() {});
  }

  Future<bool> _likePost(FeedPost post) async {
    try {
      final res = await http.post(
        postLikeEndpoint(post.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({'liked': post.liked}),
      );
      if (res.statusCode == 401) { await widget.onLogout(); return false; }
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _savePost(FeedPost post) async {
    try {
      final res = await http.post(
        postSaveEndpoint(post.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({'saved': post.saved}),
      );
      if (res.statusCode == 401) { await widget.onLogout(); return false; }
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recordShare(FeedPost post) async {
    try {
      final res = await http.post(
        postShareEndpoint(post.id),
        headers: authJsonHeaders(widget.session.token),
      );
      if (res.statusCode == 401) await widget.onLogout();
    } catch (_) {}
  }

  Future<bool> _voteOnPoll(FeedPost post, int optionId) async {
    try {
      final res = await http.post(
        postPollVoteEndpoint(post.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({'option_id': optionId}),
      );
      if (res.statusCode == 401) await widget.onLogout();
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<void> _follow(String username) async {
    setState(() => _followingAuthors.add(username));
    final res = await http.post(
      followEndpoint(username),
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({'follow': true}),
    );
    if (res.statusCode == 401) {
      if (mounted) setState(() => _followingAuthors.remove(username));
      await widget.onLogout();
      return;
    }
    if (res.statusCode >= 400) {
      if (mounted) setState(() => _followingAuthors.remove(username));
    }
  }

  Future<void> _unfollow(String username) async {
    final removed = _followingProfiles.where((p) => p.username == username).toList();
    setState(() {
      _followingAuthors.remove(username);
      _followingProfiles.removeWhere((p) => p.username == username);
    });
    final res = await http.post(
      followEndpoint(username),
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({'follow': false}),
    );
    if (res.statusCode == 401) {
      if (mounted) {
        setState(() {
          _followingAuthors.add(username);
          _followingProfiles.addAll(removed);
        });
      }
      await widget.onLogout();
      return;
    }
    if (res.statusCode >= 400) {
      if (mounted) {
        setState(() {
          _followingAuthors.add(username);
          _followingProfiles.addAll(removed);
        });
      }
    }
  }

  Future<void> _deletePost(FeedPost post) async {
    final res = await http.delete(
      postDeleteEndpoint(post.id),
      headers: authGetHeaders(widget.session.token),
    );
    if (res.statusCode == 200) {
      await _load();
    }
  }

  void _pushProfileRoute(String username, {int? postId, bool? followEnabled, bool bouncePost = false, String? highlightCommentActor, int? autoOpenCommentId, FeedPost? autoOpenCommentPost}) {
    // Profile pages always show the native bar. Save the current hide count
    // so we can restore it when the profile pops (e.g. back into messages).
    final savedCount = _navBarHideCount;
    _navBarHideCount = 0;
    if (_isIOS26) _kTabChannel.invokeMethod('showTabBar');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(
          key: ValueKey('route:$username:${postId ?? ""}'),
          username: username,
          currentUser: widget.session.user,
          token: widget.session.token,
          posts: _posts,
          onOpenUserProfile: _pushProfileRoute,
          onOpenProfileAtPost: (u, id) => _pushProfileRoute(u, postId: id),
          onLogout: widget.onLogout,
          onSessionUpdated: widget.onSessionChanged,
          onPostTap: _openComments,
          onPostTapWithHighlight: (post, actor) => _openComments(post, highlightActor: actor),
          onOpenCommentsExact: (post, commentId, actor) =>
              _openComments(post, highlightCommentId: commentId, highlightActor: actor),
          initialPostId: postId,
          bouncePost: bouncePost,
          autoOpenCommentActor: highlightCommentActor,
          autoOpenCommentId: autoOpenCommentId,
          autoOpenCommentPost: autoOpenCommentPost,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onHideNavBar: _hideNativeBar,
          onShowNavBar: _showNativeBar,
          followEnabled: followEnabled ?? _activeCity == null,
          realtime: _realtime,
        ),
      ),
    ).then((_) {
      _navBarHideCount = savedCount;
      if (savedCount > 0 && _isIOS26 && mounted) {
        _kTabChannel.invokeMethod('hideTabBar');
      } else if (_isIOS26 && mounted) {
        _kTabChannel.invokeMethod('showTabBar');
      }
    });
  }

  Future<void> _openCityFeed(String city) async {
    setState(() {
      _activeCity = city.trim();
      _selectedTab = 0;
      _nav = 0;
      _loading = true;
    });
    if (_isIOS26) _kTabChannel.invokeMethod('syncTab', 0);
    await _load();
  }

  Future<void> _goHome() async {
    if (_activeCity == null) {
      setState(() {
        _nav = 0;
        _showInlineProfile = false;
        _inlinePostId = null;
      });
      return;
    }
    final homeCity = widget.session.user.city;
    // Do NOT set _loading here — it triggers the early-return guard in build()
    // which bypasses the Stack, making the overlay invisible.
    setState(() {
      _returningToCity = homeCity;
      _activeCity = null;
      _nav = 0;
      _showInlineProfile = false;
      _inlinePostId = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _returningToCity = null;
      _loading = true;
    });
    await _load();
  }

  Future<void> _openEvents({int initialTab = 0, int? initialEventId}) async {
    setState(() => _hasOfficialEvents = false);
    unawaited(_markOfficialEventsSeen());
    _hideNativeBar();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventsPage(
          token: widget.session.token,
          city: _activeCity ?? widget.session.user.city,
          currentUser: widget.session.user,
          onOpenUserProfile: _pushProfileRoute,
          preferredTab: initialTab,
          attendEnabled: _activeCity == null,
          initialEventId: initialEventId,
        ),
      ),
    );
    _showNativeBar();
  }

  // Verbs whose target is a specific comment/reply — these open the comment
  // panel scrolled to that exact comment, not the actor's profile.
  static const _kCommentVerbs = {
    'commented on your post',
    'replied to your comment',
    'liked your comment',
    'mentioned you in a comment',
  };

  /// The single navigation entry point for a notification, used identically by
  /// both the in-app notifications list and a tapped push (see
  /// [_openNotificationTargetFromPush]) so the two behave the same.
  Future<void> _openNotificationTarget(NotificationItem item, {String? eventType}) async {
    if (item.targetType == 'event') {
      final tab = eventType == 'community' ? 1 : 0;
      await _openEvents(
        initialTab: tab,
        initialEventId: int.tryParse(item.targetId),
      );
      return;
    }
    if (item.targetType == 'post' && item.targetId.isNotEmpty) {
      final postId = int.tryParse(item.targetId);

      if (item.verb == 'liked your post' && postId != null) {
        _pushProfileRoute(
          widget.session.user.username,
          postId: postId,
          bouncePost: true,
        );
        return;
      }

      if (item.verb == 'mentioned you in a post' && postId != null) {
        await _openPostThenComments(postId);
        return;
      }

      if (_kCommentVerbs.contains(item.verb) && postId != null) {
        await _openPostThenComments(
          postId,
          highlightCommentId: item.targetCommentId > 0 ? item.targetCommentId : null,
          highlightActor: item.actor,
        );
        return;
      }
    }
    _pushProfileRoute(item.actor);
  }

  /// Reconstructs a [NotificationItem] from a tapped push's data payload (see
  /// push/signals.py) and routes it through the same [_openNotificationTarget]
  /// the in-app list uses — so a push tap scrolls to the post / opens the
  /// comment panel exactly like tapping the notification inside the app.
  Future<void> _openNotificationTargetFromPush(Map<String, dynamic> data) async {
    int parseInt(Object? v) => int.tryParse('${v ?? ''}') ?? 0;
    final item = NotificationItem(
      id: parseInt(data['notificationId']),
      actor: data['actor']?.toString() ?? '',
      actorAvatarUrl: '',
      verb: data['verb']?.toString() ?? '',
      targetType: data['targetType']?.toString() ?? '',
      targetId: data['targetId']?.toString() ?? '',
      targetCommentId: parseInt(data['targetCommentId']),
      targetText: '',
      imageUrl: '',
      videoUrl: '',
      isRead: true,
      created: DateTime.now(),
    );
    await _openNotificationTarget(item);
  }

  /// TikTok-style comment-notification flow: land on the exact post (scrolled
  /// to it in the author's profile, like the "liked your post" flow), then open
  /// its comment panel scrolled to [highlightCommentId] (falling back to
  /// [highlightActor]). Fetches the post fresh so the just-arrived comment is
  /// present, and passes it along so the panel opens even if the post isn't in
  /// the loaded feed.
  Future<void> _openPostThenComments(
    int postId, {
    int? highlightCommentId,
    String? highlightActor,
  }) async {
    FeedPost? post;
    try {
      final res = await http.get(
        postDetailEndpoint(postId),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode == 401) { await widget.onLogout(); return; }
      if (res.statusCode == 200) {
        post = FeedPost.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (post == null) {
      for (final p in _posts) {
        if (p.id == postId) { post = p; break; }
      }
    }
    if (post == null || !mounted) return;
    _pushProfileRoute(
      post.author,
      postId: postId,
      autoOpenCommentPost: post,
      autoOpenCommentId: highlightCommentId,
      highlightCommentActor: highlightActor,
    );
  }

  void _openNotifications() {
    _hideNativeBar();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff000000),
      isScrollControlled: true,
      builder: (sheetCtx) => SizedBox(
        height: MediaQuery.of(sheetCtx).size.height * 0.85,
        child: _NotificationsSheet(
          fetchNotifications: _fetchNotifications,
          followingAuthors: Set.of(_followingAuthors),
          followerAuthors: Set.of(_followerAuthors),
          token: widget.session.token,
          onFollow: _follow,
          onUnfollow: _unfollow,
          onOpenUserProfile: _pushProfileRoute,
          onTapItem: (item, eventType) async {
            await _markNotificationsRead([item]);
            if (!mounted) return;
            await _openNotificationTarget(item, eventType: eventType);
          },
        ),
      ),
    ).whenComplete(_showNativeBar);
  }

  /// Opens a DM conversation directly from a tapped push notification —
  /// mirrors _MessagesPageState._open in messages_page.dart, but fetches the
  /// conversation by id first since a push only carries the id (see
  /// push_service.dart / push/senders.py on the backend).
  Future<void> _openConversationById(int conversationId) async {
    try {
      final res = await http.get(
        messageConversationEndpoint(conversationId),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode == 401) {
        await widget.onLogout();
        return;
      }
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final conv = ConversationSummary.fromJson(
        decoded['conversation'] as Map<String, dynamic>,
      );
      if (!mounted) return;
      _hideNativeBar();
      await Navigator.of(context).push(PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (ctx, anim, secAnim) => ConversationPage(
          token: widget.session.token,
          currentUsername: widget.session.user.username,
          currentAvatarUrl: widget.session.user.avatarUrl,
          conversationId: conv.id,
          otherUsername: conv.otherUser,
          otherFullName: conv.otherFullName,
          otherAvatarUrl: conv.otherAvatarUrl,
          otherLastActive: conv.otherLastActive,
          onLogout: widget.onLogout,
          onOpenPost: (author, postId) {
            _pushProfileRoute(author, postId: postId);
          },
          onOpenUserProfile: _pushProfileRoute,
          realtime: _realtime,
        ),
        transitionsBuilder: (ctx, animation, secAnim, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
          child: child,
        ),
      ));
      _showNativeBar();
      _loadUnreadMessages();
    } catch (_) {}
  }

  void _openComments(FeedPost post, {String? highlightActor, int? highlightCommentId}) {
    _hideNativeBar();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff000000),
      builder: (_) => _CommentSheet(
        post: post,
        session: widget.session,
        onRefresh: () {},
        onOpenUserProfile: _pushProfileRoute,
        likingEnabled: _activeCity == null,
        highlightActor: highlightActor,
        highlightCommentId: highlightCommentId,
        onHideNavBar: _hideNativeBar,
        onShowNavBar: _showNativeBar,
      ),
    ).whenComplete(_showNativeBar);
  }

  void _openCreatePost() {
    _compose.clear();
    _composeMedia.clear();
    _composePollActive = false;
    for (final c in _composePollControllers) { c.dispose(); }
    _composePollControllers.clear();
    if (_isIOS26) _kTabChannel.invokeMethod('syncTab', _nav);
    _hideNativeBar();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (pageContext) {
          final isLight = Theme.of(pageContext).brightness == Brightness.light;
          final dimColor = isLight ? Colors.black : Colors.white;
          return StatefulBuilder(
            builder: (pageContext, setPageState) {
          // ── helper: single media cell with X button ──────────────────────
          Widget mediaCell(_ComposeMedia item, int index, double size) {
            // Freshly-picked photos can be huge; decode only to the cell size.
            final cellPx =
                (size * MediaQuery.devicePixelRatioOf(context)).round();
            Widget preview;
            if (item.isVideo && item.videoPath != null) {
              preview = _ComposeVideoPreview(path: item.videoPath!);
            } else if (item.imageBytes != null) {
              preview = Image.memory(item.imageBytes!, fit: BoxFit.cover, cacheWidth: cellPx);
            } else if (item.externalUrl != null) {
              preview = CachedNetworkImage(
                imageUrl: item.externalUrl!,
                cacheManager: imageCacheManager,
                fit: BoxFit.cover,
                memCacheWidth: cellPx,
                fadeInDuration: Duration.zero,
              );
            } else {
              preview = const ColoredBox(color: Color(0xff141414));
            }
            return SizedBox(
              width: size,
              height: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: preview,
                  ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: GestureDetector(
                      onTap: () => _removeComposeMedia(index, setPageState),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(5),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // ── helper: media grid (1→full-width, 2-4→grid) ─────────────────
          Widget buildMediaGrid(double width) {
            if (_composeMedia.isEmpty) return const SizedBox.shrink();
            final gap = 6.0;
            final half = (width - gap) / 2;

            if (_composeMedia.length == 1) {
              final item = _composeMedia.first;
              final singlePx =
                  (width * MediaQuery.devicePixelRatioOf(context)).round();
              Widget preview;
              if (item.isVideo && item.videoPath != null) {
                preview =
                    _ComposeVideoPreview(path: item.videoPath!, badgeSize: 48);
              } else if (item.imageBytes != null) {
                preview = Image.memory(item.imageBytes!, fit: BoxFit.cover, cacheWidth: singlePx);
              } else if (item.externalUrl != null) {
                preview = CachedNetworkImage(
                  imageUrl: item.externalUrl!,
                  cacheManager: imageCacheManager,
                  fit: BoxFit.cover,
                  memCacheWidth: singlePx,
                  fadeInDuration: Duration.zero,
                );
              } else {
                preview = const ColoredBox(color: Color(0xff141414));
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(children: [
                  AspectRatio(aspectRatio: 1.15, child: preview),
                  if (item.preparing)
                    Positioned(
                      left: 10, bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context).preparingVideo,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 10, right: 10,
                    child: GestureDetector(
                      onTap: () => _removeComposeMedia(0, setPageState),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(7),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 17),
                      ),
                    ),
                  ),
                  // A minute of video is a long enough upload that the button's
                  // progress ring alone is too small to reassure anyone.
                  // Listens, because the upload is usually already running
                  // before this sheet's own state ever changes.
                  ValueListenableBuilder<double?>(
                    valueListenable: _uploadProgress,
                    builder: (context, progress, _) {
                      if (progress == null) return const SizedBox.shrink();
                      return Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            AppLocalizations.of(context)
                                .uploadingVideo((progress * 100).round()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ]),
              );
            }

            // 2-4 items: grid
            final items = _composeMedia;
            if (items.length == 2) {
              return Row(
                children: [
                  mediaCell(items[0], 0, half),
                  SizedBox(width: gap),
                  mediaCell(items[1], 1, half),
                ],
              );
            }
            if (items.length == 3) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mediaCell(items[0], 0, half),
                  SizedBox(width: gap),
                  Column(
                    children: [
                      mediaCell(items[1], 1, half),
                      SizedBox(height: gap),
                      mediaCell(items[2], 2, half),
                    ],
                  ),
                ],
              );
            }
            // 4 items: 2×2
            return Column(
              children: [
                Row(children: [
                  mediaCell(items[0], 0, half),
                  SizedBox(width: gap),
                  mediaCell(items[1], 1, half),
                ]),
                SizedBox(height: gap),
                Row(children: [
                  mediaCell(items[2], 2, half),
                  SizedBox(width: gap),
                  mediaCell(items[3], 3, half),
                ]),
              ],
            );
          }

              return PopScope(
                // Always poppable. Refusing to pop while posting is what left
                // people stuck in this sheet with no way out; the upload is
                // cancelled on the way instead.
                canPop: true,
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) _cancelUpload();
                },
                child: Scaffold(
                backgroundColor:
                    isLight ? Colors.white : const Color(0xff000000),
                body: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // ── top bar ──────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                _cancelUpload();
                                Navigator.of(pageContext).pop();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: isLight ? Colors.black : Colors.white,
                                disabledForegroundColor: const Color(0xff8a8a8a),
                                padding: EdgeInsets.zero,
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              child: Text(AppLocalizations.of(context).cancel),
                            ),
                            const Spacer(),
                            Text(
                              AppLocalizations.of(context).newPost,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: dimColor,
                              ),
                            ),
                            const Spacer(),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _compose,
                              builder: (_, value, _) {
                                final canPost = value.text.trim().isNotEmpty;
                                return FilledButton(
                                  onPressed: canPost
                                      ? (_posting
                                          ? () {}
                                          : () => _createPost(setPageState))
                                      : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: dimColor,
                                    foregroundColor: isLight
                                        ? Colors.white
                                        : Colors.black,
                                    disabledBackgroundColor: isLight
                                        ? const Color(0xffd9dee6)
                                        : const Color(0xff2f2f2f),
                                    disabledForegroundColor:
                                        const Color(0xff8a8a8a),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                  ),
                                  child: _posting
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            // Determinate once there are
                                            // megabytes in flight: a minute of
                                            // video takes long enough that a
                                            // spinner alone reads as a hang.
                                            value: _uploadProgress.value,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              isLight ? Colors.white : Colors.black,
                                            ),
                                          ),
                                        )
                                      : Text(AppLocalizations.of(context).post),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: isLight
                            ? const Color(0xffd9dee6)
                            : const Color(0xff242424),
                      ),
                      // ── scrollable compose area ──────────────────────────
                      Expanded(
                        child: SingleChildScrollView(
                          padding:
                              const EdgeInsets.fromLTRB(16, 20, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  PostAvatar(
                                    username:
                                        widget.session.user.username,
                                    avatarUrl:
                                        widget.session.user.avatarUrl,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        TextField(
                                          controller: _compose,
                                          autofocus: true,
                                          maxLines: null,
                                          maxLength: 280,
                                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                                          style: TextStyle(
                                            color: dimColor,
                                            fontSize: 17,
                                            height: 1.4,
                                          ),
                                          cursorColor: dimColor,
                                          decoration: InputDecoration(
                                            hintText: 'Δημοσιεύστε ενα neet...',
                                            hintStyle: TextStyle(
                                              color: isLight
                                                  ? const Color(0xff616161)
                                                  : const Color(0xff8f8f8f),
                                            ),
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                            counterText: '',
                                          ),
                                        ),
                                        MentionSuggestions(
                                          controller: _compose,
                                          token: widget.session.token,
                                        ),
                                        // ── media grid / loading ─────────
                                        if (_composeMediaLoading) ...[
                                          const SizedBox(height: 20),
                                          const Center(child: CircularProgressIndicator()),
                                          const SizedBox(height: 6),
                                        ] else if (_composeMedia.isNotEmpty) ...[
                                          const SizedBox(height: 14),
                                          LayoutBuilder(
                                            builder: (_, constraints) =>
                                                buildMediaGrid(
                                                    constraints.maxWidth),
                                          ),
                                        ],
                                        // ── poll editor ──────────────────
                                        if (_composePollActive)
                                          _ComposePollEditor(
                                            controllers: _composePollControllers,
                                            isLight: isLight,
                                            onAddOption: () {
                                              if (_composePollControllers.length < 4) {
                                                setPageState(() => _composePollControllers.add(TextEditingController()));
                                              }
                                            },
                                            onRemoveOption: (index) {
                                              if (_composePollControllers.length > 2) {
                                                setPageState(() {
                                                  _composePollControllers[index].dispose();
                                                  _composePollControllers.removeAt(index);
                                                });
                                              }
                                            },
                                            onCancel: () {
                                              setPageState(() {
                                                for (final c in _composePollControllers) { c.dispose(); }
                                                _composePollControllers.clear();
                                                _composePollActive = false;
                                              });
                                            },
                                          ),
                                        // ── action row ───────────────────
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            // Photos (max 4, disabled if video or poll present)
                                            if (!_composePollActive &&
                                                !_composeMediaLoading &&
                                                !_composeMedia.any(
                                                (m) => m.isVideo) &&
                                                _composeMedia.length < 4)
                                              _ComposeAction(
                                                icon: Icons.photo_library_outlined,
                                                onTap: () =>
                                                    _pickComposeImages(
                                                        setPageState),
                                              ),
                                            // Camera (disabled if video or poll present or 4 photos)
                                            if (!_composePollActive &&
                                                !_composeMediaLoading &&
                                                !_composeMedia.any(
                                                (m) => m.isVideo) &&
                                                _composeMedia.length < 4)
                                              _ComposeAction(
                                                icon: Icons.camera_alt_outlined,
                                                onTap: () =>
                                                    _pickComposeCamera(
                                                        setPageState),
                                              ),
                                            // Video (disabled if any media or poll present)
                                            if (!_composePollActive &&
                                                !_composeMediaLoading &&
                                                _composeMedia.isEmpty)
                                              _ComposeAction(
                                                icon: Icons
                                                    .videocam_outlined,
                                                onTap: () =>
                                                    _pickComposeVideo(
                                                        setPageState),
                                              ),
                                            // GIF (disabled if any media or poll present)
                                            if (!_composePollActive && _composeMedia.isEmpty)
                                              _ComposeAction(
                                                icon: Icons
                                                    .gif,
                                                iconSize: 28,
                                                onTap: () async {
                                                  final completer =
                                                      Completer<String?>();
                                                  final listener =
                                                      _GifPickerListener(
                                                    onSelect:
                                                        (GiphyMedia media) {
                                                      final url = media
                                                              .images
                                                              .fixedWidth
                                                              ?.gifUrl ??
                                                          media.images
                                                              .original
                                                              ?.gifUrl ??
                                                          '';
                                                      if (!completer
                                                          .isCompleted) {
                                                        completer.complete(
                                                          url.isNotEmpty
                                                              ? url
                                                              : null,
                                                        );
                                                      }
                                                    },
                                                    onDismissed: () {
                                                      if (!completer
                                                          .isCompleted) {
                                                        completer
                                                            .complete(null);
                                                      }
                                                    },
                                                  );
                                                  GiphyDialog.instance
                                                      .addListener(listener);
                                                  GiphyDialog.instance
                                                      .configure(
                                                    settings: GiphySettings(
                                                      theme: GiphyTheme
                                                          .automaticTheme,
                                                      mediaTypeConfig: [
                                                        GiphyContentType.gif,
                                                        GiphyContentType
                                                            .sticker,
                                                      ],
                                                      selectedContentType:
                                                          GiphyContentType
                                                              .gif,
                                                      showSuggestionsBar:
                                                          true,
                                                      showConfirmationScreen:
                                                          false,
                                                    ),
                                                  );
                                                  GiphyDialog.instance
                                                      .show();
                                                  final url =
                                                      await completer
                                                          .future;
                                                  GiphyDialog.instance
                                                      .removeListener(
                                                          listener);
                                                  if (!mounted) return;
                                                  if (url != null &&
                                                      url.isNotEmpty) {
                                                    setState(() {
                                                      _composeMedia.clear();
                                                      _composeMedia.add(
                                                        _ComposeMedia.external(
                                                          externalUrl: url,
                                                          mediaType: 'image',
                                                        ),
                                                      );
                                                    });
                                                    setPageState(() {});
                                                  }
                                                },
                                              ),
                                            // Poll toggle (hidden if media present)
                                            if (_composeMedia.isEmpty && !_composeMediaLoading)
                                              _ComposeAction(
                                                icon: Icons.poll_outlined,
                                                active: _composePollActive,
                                                onTap: () {
                                                  setPageState(() {
                                                    _composePollActive = !_composePollActive;
                                                    if (_composePollActive) {
                                                      for (final c in _composePollControllers) { c.dispose(); }
                                                      _composePollControllers.clear();
                                                      _composePollControllers.add(TextEditingController());
                                                      _composePollControllers.add(TextEditingController());
                                                    } else {
                                                      for (final c in _composePollControllers) { c.dispose(); }
                                                      _composePollControllers.clear();
                                                    }
                                                  });
                                                },
                                              ),
                                            const Spacer(),
                                            ValueListenableBuilder<
                                                TextEditingValue>(
                                              valueListenable: _compose,
                                              builder: (_, value, _) {
                                                final count =
                                                    value.text.length;
                                                return Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: isLight
                                                        ? const Color(
                                                            0xffeef1f5)
                                                        : const Color(
                                                            0xff141414),
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(999),
                                                    border: Border.all(
                                                      color: isLight
                                                          ? const Color(
                                                              0xffd9dee6)
                                                          : const Color(
                                                              0xff2c2c2c),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '$count/280',
                                                    softWrap: false,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isLight
                                                          ? const Color(
                                                              0xff616161)
                                                          : const Color(
                                                              0xff9a9a9a),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              );
            },
          );
        },
      ),
    ).whenComplete(_showNativeBar);
  }

  void _hideNativeBar() {
    _navBarHideCount++;
    if (_isIOS26) _kTabChannel.invokeMethod('hideTabBar');
  }

  void _showNativeBar() {
    _navBarHideCount = (_navBarHideCount - 1).clamp(0, 999);
    if (_navBarHideCount == 0 && _isIOS26 && mounted) {
      _kTabChannel.invokeMethod('showTabBar');
    }
  }

  void _openSheet({required String title, required Widget child}) {
    _hideNativeBar();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xff000000),
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        );
      },
    ).whenComplete(_showNativeBar);
  }

  Widget _buildFeedScrollView(
    List<FeedPost> posts,
    ScrollController scroll,
    bool isLight,
  ) {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        controller: scroll,
        slivers: [
          const SliverToBoxAdapter(child: SizedBox.shrink()),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              selectedTab: _selectedTab,
              city: _activeCity ?? widget.session.user.city,
              showFollowing: _activeCity == null,
              scrollController: scroll,
              onTabChanged: (value) => setState(() => _selectedTab = value),
            ),
          ),
          if (posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  AppLocalizations.of(context).noPostsYet,
                  style: TextStyle(
                    color: isLight
                        ? const Color(0xff888888)
                        : const Color(0xffe8e8e8),
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return FeedPostCard(
                  key: ValueKey(post.id),
                  post: post,
                  token: widget.session.token,
                  currentUser: widget.session.user,
                  followingAuthors: _followingAuthors,
                  onFollowUser: _activeCity == null ? _follow : null,
                  onUnfollowUser: _activeCity == null ? _unfollow : null,
                  likingEnabled: _activeCity == null,
                  onLike: () => _likePost(post),
                  onSave: () => _savePost(post),
                  onShare: () async {
                    bool shared = false;
                    _hideNativeBar();
                    await showShareSheet(
                      context: context,
                      post: post,
                      token: widget.session.token,
                      currentUser: widget.session.user,
                      onLogout: widget.onLogout,
                      onShared: () { shared = true; },
                    );
                    _showNativeBar();
                    if (shared) unawaited(_recordShare(post));
                    return shared;
                  },
                  onMore: () => _openSheet(
                    title: post.author,
                    child: Column(
                      children: [
                        if (post.author == widget.session.user.username || widget.session.user.isAdmin)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.delete_outline,
                              color: Color(0xfff66c6c),
                            ),
                            title: Text(AppLocalizations.of(context).deletePost),
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _deletePost(post);
                            },
                          ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.flag_outlined),
                          title: Text(AppLocalizations.of(context).reportPost),
                          onTap: () {
                            Navigator.of(context).pop();
                            _hideNativeBar();
                            showReportPostSheet(
                              context,
                              postId: post.id,
                              token: widget.session.token,
                            ).whenComplete(_showNativeBar);
                          },
                        ),
                      ],
                    ),
                  ),
                  onComment: () => _openComments(post),
                  onProfileTap: () => _pushProfileRoute(post.author),
                  onOpenUserProfile: _pushProfileRoute,
                  onFollow: (post.author != widget.session.user.username && _activeCity == null)
                      ? () => _follow(post.author)
                      : null,
                  onUnfollow: (post.author != widget.session.user.username && _activeCity == null)
                      ? () => _unfollow(post.author)
                      : null,
                  isFollowing: _followingAuthors.contains(post.author),
                  followerAuthors: _followerAuthors,
                  onHideNavBar: _hideNativeBar,
                  onShowNavBar: _showNativeBar,
                  onVote: (optionId) => _voteOnPoll(post, optionId),
                );
              },
            ),
          // Reaching the end of the page asks for the next one, so the feed
          // keeps going instead of stopping at whatever the first request
          // happened to bring back.
          if (posts.isNotEmpty && _hasOlderPosts)
            SliverToBoxAdapter(
              child: _FeedPageLoader(onVisible: _loadOlderPosts),
            ),
        ],
      ),
    );
  }

  /// Fetches the page of posts older than the last one on screen.
  Future<void> _loadOlderPosts() async {
    if (_loadingOlderPosts || !_hasOlderPosts || _posts.isEmpty) return;
    _loadingOlderPosts = true;
    try {
      final res = await http.get(
        postsEndpoint(city: _activeCity, before: _posts.last.id),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode != 200 || !mounted) return;
      final page = await compute(_parseFeedPosts, res.body);
      if (!mounted) return;
      // The feed can have been refreshed out from under this request.
      final known = _posts.map((p) => p.id).toSet();
      setState(() {
        _posts.addAll(page.posts.where((p) => !known.contains(p.id)));
        _hasOlderPosts = page.hasMore;
      });
    } catch (_) {
      // Leave _hasOlderPosts alone — the page is still there, the network isn't.
    } finally {
      _loadingOlderPosts = false;
    }
  }

  Widget _buildViralPostCard(FeedPost post, {required bool interactive}) {
    return FeedPostCard(
      key: ValueKey('viral_${post.id}'),
      post: post,
      token: widget.session.token,
      currentUser: widget.session.user,
      followingAuthors: _followingAuthors,
      followerAuthors: _followerAuthors,
      likingEnabled: interactive,
      onLike: interactive ? () => _likePost(post) : () async => false,
      onSave: interactive ? () => _savePost(post) : () async => false,
      onShare: () async {
        bool shared = false;
        _hideNativeBar();
        await showShareSheet(
          context: context,
          post: post,
          token: widget.session.token,
          currentUser: widget.session.user,
          onLogout: widget.onLogout,
          onShared: () { shared = true; },
        );
        _showNativeBar();
        if (shared) unawaited(_recordShare(post));
        return shared;
      },
      onMore: () => _openSheet(
        title: post.author,
        child: Column(
          children: [
            if (post.author == widget.session.user.username || widget.session.user.isAdmin)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline, color: Color(0xfff66c6c)),
                title: Text(AppLocalizations.of(context).deletePost),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _deletePost(post);
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: Text(AppLocalizations.of(context).reportPost),
              onTap: () {
                Navigator.of(context).pop();
                _hideNativeBar();
                showReportPostSheet(context, postId: post.id, token: widget.session.token)
                    .whenComplete(_showNativeBar);
              },
            ),
          ],
        ),
      ),
      onComment: () {
        _hideNativeBar();
        final isLight = Theme.of(context).brightness == Brightness.light;
        showModalBottomSheet(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: isLight ? Colors.white : const Color(0xff000000),
          builder: (_) => _CommentSheet(
            post: post,
            session: widget.session,
            onRefresh: () {},
            onOpenUserProfile: _pushProfileRoute,
            likingEnabled: interactive,
            onHideNavBar: _hideNativeBar,
            onShowNavBar: _showNativeBar,
          ),
        ).whenComplete(_showNativeBar);
      },
      onProfileTap: () => _pushProfileRoute(post.author, followEnabled: interactive),
      onOpenUserProfile: (u) => _pushProfileRoute(u, followEnabled: interactive),
      onFollow: (interactive && post.author != widget.session.user.username) ? () => _follow(post.author) : null,
      onUnfollow: (interactive && post.author != widget.session.user.username) ? () => _unfollow(post.author) : null,
      isFollowing: _followingAuthors.contains(post.author),
      onHideNavBar: _hideNativeBar,
      onShowNavBar: _showNativeBar,
      onVote: interactive ? (optionId) => _voteOnPoll(post, optionId) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: NeatLoader());
    }

    final cityPosts = _posts;
    final followingPosts = _followingAuthors.isEmpty
        ? const <FeedPost>[]
        : _posts.where((p) => _followingAuthors.contains(p.author)).toList();

    final isLight = Theme.of(context).brightness == Brightness.light;

    final returningCity = _returningToCity;

    return Scaffold(
      backgroundColor: isLight ? const Color(0xfff3f4f6) : const Color(0xff000000),
      extendBody: _isIOS26,
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            _TopBar(
              notifications: _notificationsList
                  .where((item) => !item.isRead)
                  .length,
              unreadMessages: _unreadMessages,
              hasOfficialEvents: _hasOfficialEvents,
              activeCity: _activeCity,
              homeCity: widget.session.user.city,
              onReturnHome: _goHome,
              onEventsTap: () => _openEvents(),
              onNotificationsTap: _openNotifications,
              onMessagesTap: () async {
                _hideNativeBar();
                await Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    opaque: false,
                    pageBuilder: (ctx, anim, secAnim) => MessagesPage(
                      token: widget.session.token,
                      currentUsername: widget.session.user.username,
                      currentAvatarUrl: widget.session.user.avatarUrl,
                      suggestedUsers: _followingProfiles,
                      onLogout: widget.onLogout,
                      onOpenPost: (author, postId) {
                        _pushProfileRoute(author, postId: postId);
                      },
                      onOpenUserProfile: _pushProfileRoute,
                      realtime: _realtime,
                    ),
                    transitionsBuilder: (ctx, animation, secAnim, child) => SlideTransition(
                      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                          .animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
                      child: child,
                    ),
                  ),
                );
                _showNativeBar();
                _loadUnreadMessages();
              },
            ),
            // Directly under the top bar, where Instagram puts it: in view
            // but not in the way of whatever the user went back to.
            _PostingBanner(
              label: _postingLabel,
              progress: _uploadProgress,
              isLight: isLight,
            ),
            Divider(
              height: 1,
              color: isLight ? const Color(0xffd6d9df) : const Color(0xff232323),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _isOffline
                  ? _OfflineBanner(isLight: isLight)
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Tabs — hidden (but kept alive) while profile is visible
                  Offstage(
                    offstage: _showInlineProfile,
                    child: IndexedStack(
                      index: _nav,
                      children: [
                        // 0: Feed — two independent scroll views keep their own positions
                        IndexedStack(
                          index: _selectedTab,
                          children: [
                            _buildFeedScrollView(cityPosts, _cityScroll, isLight),
                            _buildFeedScrollView(followingPosts, _followingScroll, isLight),
                          ],
                        ),
                        // 1: Viral — mounted lazily on first visit
                        _visitedTabs.contains(1)
                            ? _ViralView(
                                key: _viralViewKey,
                                token: widget.session.token,
                                currentUser: widget.session.user,
                                followingAuthors: _followingAuthors,
                                followerAuthors: _followerAuthors,
                                buildPostCard: _buildViralPostCard,
                                onOpenUserProfile: _pushProfileRoute,
                                onHideNavBar: _hideNativeBar,
                                onShowNavBar: _showNativeBar,
                              )
                            : const SizedBox.shrink(),
                        // 2: Create (intercepted by bottom nav, never shown)
                        const SizedBox.shrink(),
                        // 3: Map — mounted lazily on first visit
                        _visitedTabs.contains(3)
                            ? RepaintBoundary(
                                child: CityMapView(
                                  token: widget.session.token,
                                  homeCity: widget.session.user.city,
                                  onOpenUserProfile: _pushProfileRoute,
                                  onCitySelected: _openCityFeed,
                                ),
                              )
                            : const SizedBox.shrink(),
                        // 4: Profile (intercepted — shown as inline overlay)
                        const SizedBox.shrink(),
                      ],
                    ),
                  ),
                  // Profile — kept alive to preserve scroll, hidden when not shown
                  if (_inlineProfileUsername.isNotEmpty)
                    Offstage(
                      offstage: !_showInlineProfile,
                      child: ProfilePage(
                        key: ValueKey('$_inlineProfileUsername:${_inlinePostId ?? ""}:$_profileRefreshKey'),
                        username: _inlineProfileUsername,
                        currentUser: widget.session.user,
                        token: widget.session.token,
                        posts: _posts,
                        onOpenUserProfile: _pushProfileRoute,
                        onOpenProfileAtPost: (u, id) => _pushProfileRoute(u, postId: id),
                        onLogout: widget.onLogout,
                        onSessionUpdated: widget.onSessionChanged,
                        onPostTap: _openComments,
                        initialPostId: _inlinePostId,
                        themeMode: widget.themeMode,
                        onThemeModeChanged: widget.onThemeModeChanged,
                        onHideNavBar: _hideNativeBar,
                        onShowNavBar: _showNativeBar,
                        followEnabled: _activeCity == null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
          if (returningCity != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const NeatLoader(size: 72, color: Colors.white),
                    const SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(context).returningToCity(returningCity),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      // iOS 26: native UITabBar is added as a subview in SceneDelegate.
      // A transparent SizedBox(49) tells Flutter's layout how much bottom
      // space to reserve so SafeArea pads content correctly.
      bottomNavigationBar: _isIOS26
          ? SizedBox(height: 49 + MediaQuery.of(context).viewPadding.bottom)
          : _buildLegacyNavBar(isLight),
    );
  }

  // ── iOS legacy nav bar ─────────────────────────────────────────────────────

  ImageProvider? _resolveAvatarProvider(String url) {
    if (url.isEmpty) return null;
    final ImageProvider base;
    if (url.startsWith('data:')) {
      final bytes = decodeAvatarUrl(url);
      if (bytes == null) return null;
      base = MemoryImage(bytes);
    } else {
      final resolved = url.startsWith('/') ? '$apiBaseUrl$url' : url;
      base = CachedNetworkImageProvider(resolved);
    }
    // Avatars never render larger than a ~96px-logical circle; cap the decode
    // at 288 physical px (loss-free everywhere, tiny in memory).
    return ResizeImage(base, width: 288);
  }

  /// The last picture handed to the native bar, so an unchanged one is not
  /// re-encoded and pushed across the channel on every rebuild.
  String _nativeProfileIconUrl = '';

  /// Pushes the current avatar to the native iOS 26 tab bar.
  ///
  /// On iOS 26 the bottom bar is a real UITabBar owned by AppDelegate, and
  /// Flutter renders only a transparent spacer where it sits — so nothing in
  /// the Dart widget tree can repaint it. It has to be *told*, over the method
  /// channel, every time the picture changes.
  ///
  /// This used to be called once, from _adoptNativeTabBar at startup. That is
  /// why changing your profile picture updated the feed, your profile and your
  /// posts immediately while the bar underneath them kept the old one until the
  /// app was relaunched — the relaunch was not fixing anything, it was simply
  /// the only time this ran.
  Future<void> _syncNativeProfileIcon() async {
    if (!_isIOS26) return;
    // Resolve through the store: the session's copy can be older than the
    // picture the user just chose.
    final url = AvatarStore.resolve(
      widget.session.user.username,
      widget.session.user.avatarUrl,
    );
    if (url.isEmpty || url == _nativeProfileIconUrl) return;
    _nativeProfileIconUrl = url;
    try {
      // Always bytes, never a URL.
      //
      // The native side would fetch a URL with URLSession, which knows nothing
      // about the certificate pinning that lives in Dart's HTTP client — and
      // the API is served from a bare IP with a self-signed certificate, so
      // that download fails and the tab bar is left with no picture at all.
      // Fetching here means it goes through the pinned client like every other
      // request, and native only ever receives finished bytes.
      final bytes = url.startsWith('data:')
          ? decodeAvatarUrl(url)
          : await _fetchAvatarBytes(url);
      if (bytes != null) {
        await _kTabChannel.invokeMethod('setProfileImage', {'bytes': bytes});
      } else {
        _nativeProfileIconUrl = '';
      }
    } catch (e) {
      // A channel that isn't listening yet is not worth failing over; the next
      // change (or _adoptNativeTabBar) will try again.
      _nativeProfileIconUrl = '';
      debugPrint('[tabbar] could not set profile image: $e');
    }
  }

  /// Downloads an avatar through the app's own (certificate-pinned) client.
  ///
  /// Returns null if it cannot be fetched, which leaves the previous icon in
  /// place rather than blanking it.
  Future<Uint8List?> _fetchAvatarBytes(String url) async {
    try {
      final absolute = url.startsWith('/') ? '$apiBaseUrl$url' : url;
      final res = await http
          .get(Uri.parse(absolute))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return res.bodyBytes;
    } catch (e) {
      debugPrint('[tabbar] avatar fetch failed: $e');
      return null;
    }
  }

  /// Re-pushes the icon whenever the app's picture-of-record changes.
  void _onAvatarRevisionChanged() => unawaited(_syncNativeProfileIcon());

  Widget _buildLegacyNavBar(bool isLight) {
    final activeColor   = isLight ? Colors.black : Colors.white;
    // Same reasoning as LegacyNavBar: resolve by username so a picture changed
    // this session reaches the bar on that frame, rather than waiting for the
    // session to be refetched at next launch.
    final imageProvider = _resolveAvatarProvider(
      AvatarStore.resolve(
        widget.session.user.username,
        widget.session.user.avatarUrl,
      ),
    );

    Widget profileIcon({required bool active}) {
      if (!active) {
        return CircleAvatar(
          radius: 13,
          backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
          foregroundImage: imageProvider,
          child: imageProvider == null
              ? Icon(Icons.person_rounded, size: 15,
                  color: isLight ? const Color(0xff6d6d6d) : const Color(0xff8c8c8c))
              : null,
        );
      }
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: activeColor, width: 2),
        ),
        alignment: Alignment.center,
        child: CircleAvatar(
          radius: 12,
          backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
          foregroundImage: imageProvider,
          child: imageProvider == null
              ? Icon(Icons.person_rounded, size: 13, color: activeColor)
              : null,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BottomNavigationBar(
          currentIndex: _nav,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          selectedItemColor: activeColor,
          unselectedItemColor:
              isLight ? const Color(0xff6d6d6d) : const Color(0xff8c8c8c),
          elevation: 0,
          backgroundColor: isLight ? Colors.white : const Color(0xff000000),
          iconSize: 26,
          selectedFontSize: 0,
          unselectedFontSize: 0,
          onTap: _onNavTap,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              activeIcon: const Icon(Icons.home_rounded),
              label: AppLocalizations.of(context).navHome,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.search_outlined),
              activeIcon: const Icon(Icons.search_rounded),
              label: AppLocalizations.of(context).navSearch,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.add_circle_outline_rounded),
              activeIcon: const Icon(Icons.add_circle_rounded),
              label: AppLocalizations.of(context).navCreate,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.map_outlined),
              activeIcon: const Icon(Icons.map_rounded),
              label: AppLocalizations.of(context).navMap,
            ),
            BottomNavigationBarItem(
              icon: profileIcon(active: false),
              activeIcon: profileIcon(active: true),
              label: AppLocalizations.of(context).navProfile,
            ),
          ],
        ),
      ),
    );
  }

  void _onNavTap(int i) {
    if (_activeCity != null && (i == 1 || i == 2 || i == 4)) {
      if (_isIOS26) _kTabChannel.invokeMethod('syncTab', _nav);
      return;
    }
    // If a route is pushed on top (e.g. a profile opened from the feed),
    // pop back to root immediately so the tab switch is visible right away
    // rather than only after the user manually presses back.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    if (i == 2) {
      _openCreatePost();
      return;
    }
    if (i == 3 && !_spectatorIntroSeen) {
      _showSpectatorIntro();
      return;
    }
    if (i == 4) {
      if (_nav == 4 && _showInlineProfile) {
        setState(() => _profileRefreshKey++);
        return;
      }
      setState(() {
        _nav = 4;
        _visitedTabs.add(4);
        _inlineProfileUsername = widget.session.user.username;
        _inlinePostId = null;
        _showInlineProfile = true;
      });
      if (_isIOS26) _kTabChannel.invokeMethod('syncTab', 4);
      return;
    }
    if (i == 0) {
      if (_nav == 0 && !_showInlineProfile) {
        final activeScroll = _selectedTab == 0 ? _cityScroll : _followingScroll;
        if (activeScroll.hasClients) {
          activeScroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
        _load();
        return;
      }
      setState(() {
        _nav = 0;
        _showInlineProfile = false;
        _inlinePostId = null;
      });
      if (_isIOS26) _kTabChannel.invokeMethod('syncTab', 0);
      return;
    }
    if (i == _nav && !_showInlineProfile) {
      if (i == 1) { _viralViewKey.currentState?.refresh(); return; }
    }
    setState(() {
      _nav = i;
      _visitedTabs.add(i);
      _showInlineProfile = false;
    });
    if (_isIOS26) _kTabChannel.invokeMethod('syncTab', i);
  }

  Future<void> _restoreSpectatorIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _spectatorIntroSeen = prefs.getBool(_kSpectatorIntroSeenKey) ?? false;
    });
  }

  /// Explains Spectator Mode before the map opens for the first time.
  ///
  /// Deliberately shown *instead of* switching tabs, not on top of the map:
  /// the live map is a platform view, and anything of ours composited over it
  /// has a history of leaving it unable to pan. The map is warmed in the
  /// background meanwhile, so it is ready the moment the sheet is dismissed.
  Future<void> _showSpectatorIntro() async {
    unawaited(prewarmCityMap(
      homeCity: widget.session.user.city,
      isDark: Theme.of(context).brightness == Brightness.dark,
    ));
    // Marked seen up front: whether they read it or swiped it away, they have
    // been told, and a second showing would only be noise.
    _spectatorIntroSeen = true;
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool(_kSpectatorIntroSeenKey, true)),
    );
    // The iOS 26 tab bar is a native view outside Flutter's hierarchy, so it
    // survives pushed routes and would sit on top of this screen's button.
    _hideNativeBar();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SpectatorIntroPage(themeMode: widget.themeMode),
      ),
    );
    _showNativeBar();
    if (!mounted) return;
    // Dismissed by the button or by a back swipe — either way they asked for
    // the map, so land there.
    setState(() {
      _nav = 3;
      _visitedTabs.add(3);
      _showInlineProfile = false;
    });
    if (_isIOS26) _kTabChannel.invokeMethod('syncTab', 3);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.notifications,
    required this.unreadMessages,
    required this.hasOfficialEvents,
    required this.onEventsTap,
    required this.onNotificationsTap,
    required this.onMessagesTap,
    this.activeCity,
    this.homeCity,
    this.onReturnHome,
  });
  final int notifications;
  final int unreadMessages;
  final bool hasOfficialEvents;
  final VoidCallback onEventsTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onMessagesTap;
  final String? activeCity;
  final String? homeCity;
  final VoidCallback? onReturnHome;
  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const _LogoMark(),
            const Spacer(),
            if (activeCity != null) ...[
              GestureDetector(
                onTap: onReturnHome,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isLight ? const Color(0xfff0f2f5) : const Color(0xff141414),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isLight ? const Color(0xffe0e3e8) : const Color(0xff2a2a2a),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 14,
                          color: isLight ? Colors.black : Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        (homeCity != null && homeCity!.isNotEmpty)
                            ? homeCity!
                            : AppLocalizations.of(context).navHome,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (activeCity == null) ...[
              _iconWithDot(
                isLight: isLight,
                showDot: notifications > 0,
                onTap: onNotificationsTap,
                icon: Icons.favorite_border_rounded,
              ),
              _iconWithDot(
                isLight: isLight,
                showDot: unreadMessages > 0,
                onTap: onMessagesTap,
                child: PostShareIcon(
                  color: isLight ? Colors.black : Colors.white,
                  size: 26,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(bool isLight) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: const Color(0xffff3040),
      shape: BoxShape.circle,
      border: Border.all(
        color: isLight ? Colors.white : Colors.black,
        width: 1.5,
      ),
    ),
  );

  Widget _iconWithDot({
    required bool isLight,
    required bool showDot,
    required VoidCallback onTap,
    IconData? icon,
    Widget? child,
  }) {
    final iconWidget = icon != null
        ? Icon(icon, color: isLight ? Colors.black : Colors.white, size: 26)
        : child!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Center(child: iconWidget)),
        ),
        if (showDot)
          Positioned(right: 6, top: 6, child: _dot(isLight)),
      ],
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader({required this.selectedTab, required this.city, required this.onTabChanged, required this.showFollowing, required this.scrollController});
  final int selectedTab;
  final String city;
  final bool showFollowing;
  final ValueChanged<int> onTabChanged;
  final ScrollController scrollController;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _TabsHeaderContent(selectedTab: selectedTab, city: city, onTabChanged: onTabChanged, showFollowing: showFollowing, scrollController: scrollController);
  }
  @override
  double get maxExtent => 52;
  @override
  double get minExtent => 52;
  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.selectedTab != selectedTab || old.city != city || old.showFollowing != showFollowing;
}

class _TabsHeaderContent extends StatefulWidget {
  const _TabsHeaderContent({required this.selectedTab, required this.city, required this.onTabChanged, required this.showFollowing, required this.scrollController});
  final int selectedTab;
  final String city;
  final bool showFollowing;
  final ValueChanged<int> onTabChanged;
  final ScrollController scrollController;

  @override
  State<_TabsHeaderContent> createState() => _TabsHeaderContentState();
}

class _TabsHeaderContentState extends State<_TabsHeaderContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final CurvedAnimation _curved;
  double _bgOpacity = 1.0;

  static const _indicatorW = 44.0;

  void _onScroll() {
    final offset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final opacity = (1.0 - (offset / 24.0)).clamp(0.0, 1.0);
    if ((opacity - _bgOpacity).abs() > 0.01) {
      setState(() => _bgOpacity = opacity);
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.selectedTab.toDouble(),
    );
    _curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_TabsHeaderContent old) {
    super.didUpdateWidget(old);
    if (old.selectedTab != widget.selectedTab) {
      widget.selectedTab == 1 ? _ctrl.forward() : _ctrl.reverse();
    }
    if (old.scrollController != widget.scrollController) {
      old.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _curved.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final activeClr   = isLight ? Colors.black   : Colors.white;
    final inactiveClr = isLight ? const Color(0xff888888) : Colors.white38;
    final bg = isLight ? const Color(0xfff3f4f6) : const Color(0xff000000);

    // Spectating: single centered city tab, no indicator
    if (!widget.showFollowing) {
      return Container(
        color: bg.withValues(alpha: _bgOpacity),
        height: 52,
        alignment: Alignment.center,
        child: Text(
          widget.city,
          style: TextStyle(color: activeClr, fontSize: 17, fontWeight: FontWeight.w800),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabW  = constraints.maxWidth / 2;
        final fromX = (tabW - _indicatorW) / 2;
        final toX   = tabW + fromX;

        return AnimatedBuilder(
          animation: _curved,
          builder: (context, _) {
            final t    = _curved.value;
            final left = fromX + (toX - fromX) * t;

            final forYouClr    = Color.lerp(activeClr,   inactiveClr, t)!;
            final followingClr = Color.lerp(inactiveClr, activeClr,   t)!;

            return Container(
              color: bg.withValues(alpha: _bgOpacity),
              child: Stack(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.onTabChanged(0),
                          child: SizedBox(
                            height: 52,
                            child: Center(
                              child: Text(
                                widget.city,
                                style: TextStyle(
                                  color: forYouClr,
                                  fontSize: 17,
                                  fontWeight: t < 0.5 ? FontWeight.w800 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.onTabChanged(1),
                          child: SizedBox(
                            height: 52,
                            child: Center(
                              child: Text(
                                AppLocalizations.of(context).following,
                                style: TextStyle(
                                  color: followingClr,
                                  fontSize: 17,
                                  fontWeight: t >= 0.5 ? FontWeight.w800 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: left,
                    bottom: 4,
                    child: Container(
                      width: _indicatorW,
                      height: 3,
                      decoration: BoxDecoration(
                        color: activeClr,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Image.asset(
        'assets/neat_logo.png',
        height: 52,
        fit: BoxFit.contain,
        color: isLight ? Colors.black : Colors.white,
        colorBlendMode: BlendMode.srcIn,
      ),
    );
  }
}

// ── Viral posts tab ───────────────────────────────────────────────────────────

class _ViralView extends StatefulWidget {
  const _ViralView({
    super.key,
    required this.token,
    required this.currentUser,
    required this.followingAuthors,
    required this.followerAuthors,
    required this.buildPostCard,
    required this.onOpenUserProfile,
    required this.onHideNavBar,
    required this.onShowNavBar,
  });

  final String token;
  final UserProfile currentUser;
  final Set<String> followingAuthors;
  final Set<String> followerAuthors;
  final Widget Function(FeedPost, {required bool interactive}) buildPostCard;
  final ValueChanged<String> onOpenUserProfile;
  final VoidCallback onHideNavBar;
  final VoidCallback onShowNavBar;

  @override
  State<_ViralView> createState() => _ViralViewState();
}

enum _ViralPeriod { daily, weekly, monthly }

/// The charts are scoped to one of two places, never to an arbitrary city:
/// home, where the viewer can actually take part, or everywhere else, which is
/// read-only (see the spectator-mode introduction).
enum _ViralScope { myCity, otherCities }

class _ViralViewState extends State<_ViralView> {
  // ── Viral ──────────────────────────────────────────────────────────────────
  _ViralScope _scope = _ViralScope.myCity;
  List<FeedPost> _viralPosts = [];
  bool _loadingViral = true;
  // Always start at the narrowest window. Widening happens below when a window
  // turns out to be empty, so opening on `weekly` only meant today's posts were
  // never looked at — a city with a single post today still landed the reader
  // on the week's chart, and daily was reachable only by picking it by hand.
  _ViralPeriod _period = _ViralPeriod.daily;
  // True when [_period] was reached by widening past an empty window rather
  // than chosen by the user.
  bool _periodAutoWidened = false;

  // ── Search ─────────────────────────────────────────────────────────────────
  bool _searchActive = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _didSearch = false;
  bool _searchLoading = false;
  int _section = 0;

  // ── Search data ─────────────────────────────────────────────────────────────
  List<UserProfile> _suggestedUsers = [];
  List<UserProfile> _users = [];
  List<UserProfile> _topUsers = [];
  List<FeedPost> _cityPosts = [];
  final List<String> _recentQueries = [];
  final Set<String> _followingAuthors = {};
  final Map<String, UserProfile> _historyUsers = {};
  bool _loadingSuggestions = true;
  bool _loadingTop = true;
  int _historyShown = 5;

  static const _historyPrefsKey = 'search_history_queries';

  @override
  void initState() {
    super.initState();
    _loadViral();
    _loadSuggestions();
    _loadTopUsers();
    _loadCityPosts();
    _loadRecentQueries();
    _loadFollowingAuthors();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // Orders the (at most 10) already-ranked posts the server returns; the
  // number itself is never shown. Ranking/filtering happens server-side (see
  // viral_posts in posts/views.py) instead of downloading the whole city feed
  // and sorting it locally on every load.
  double _score(FeedPost p) => (p.likes * 0.33 + p.commentCount * 0.33 + p.shares * 0.33) * 100;

  String get _homeCity => widget.currentUser.city;

  String _paramFor(_ViralPeriod period) => switch (period) {
        _ViralPeriod.daily => 'daily',
        _ViralPeriod.weekly => 'weekly',
        _ViralPeriod.monthly => 'monthly',
      };

  /// The next window out, or null at the widest one.
  _ViralPeriod? _widerThan(_ViralPeriod period) => switch (period) {
        _ViralPeriod.daily => _ViralPeriod.weekly,
        _ViralPeriod.weekly => _ViralPeriod.monthly,
        _ViralPeriod.monthly => null,
      };

  Future<List<FeedPost>?> _fetchViral(_ViralPeriod period) async {
    final param = _paramFor(period);
    try {
      final res = await http.get(
        _scope == _ViralScope.myCity
            ? viralPostsEndpoint(city: _homeCity, period: param)
            : viralPostsEndpoint(excludeCity: _homeCity, period: param),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode != 200) return null;
      return (await compute(_parseFeedPosts, res.body)).posts;
    } catch (_) {
      return null;
    }
  }

  /// Loads the charts, widening the window until something comes back.
  ///
  /// A quiet city has no posts today and an empty "daily" chart is a dead end,
  /// so daily falls back to weekly and weekly to monthly rather than showing
  /// nothing. Only the widening is automatic — an explicit pick from the menu
  /// clears [_periodAutoWidened] and is honoured as the starting point.
  Future<void> _loadViral({bool autoWiden = true}) async {
    if (mounted) setState(() => _loadingViral = true);
    // A previously auto-widened period must not stick: a refresh, or switching
    // scope, deserves a fresh look at today first.
    var period = _periodAutoWidened ? _ViralPeriod.daily : _period;
    var widened = false;
    while (true) {
      final posts = await _fetchViral(period);
      if (!mounted) return;
      if (posts == null) {
        // Request failed — leave the current period alone and stop.
        setState(() => _loadingViral = false);
        return;
      }
      // Only auto-widen on automatic loads (refresh/scope change), not when
      // the user explicitly picked a period from the menu.
      final wider = (autoWiden && posts.isEmpty) ? _widerThan(period) : null;
      if (wider == null) {
        setState(() {
          _period = period;
          _periodAutoWidened = widened;
          _viralPosts = posts;
          _loadingViral = false;
        });
        return;
      }
      period = wider;
      widened = true;
    }
  }

  void refresh() {
    if (_searchActive) _cancelSearch();
    _loadViral();
  }

  // ── Search activation ─────────────────────────────────────────────────────

  void _activateSearch() {
    setState(() => _searchActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _cancelSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchActive = false;
      _query = '';
      _didSearch = false;
      _users = [];
      _section = 0;
      _historyShown = 5;
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() { _query = ''; _users = []; _didSearch = false; });
    _searchFocus.requestFocus();
  }

  Color _mc(int rank) => rank == 1
      ? const Color(0xffffb700)
      : rank == 2
          ? const Color(0xffb8bec8)
          : const Color(0xffcd7f32);

  String _periodLabel(_ViralPeriod p) {
    switch (p) {
      case _ViralPeriod.daily:   return 'Ημερήσιο';
      case _ViralPeriod.weekly:  return 'Εβδομαδιαίο';
      case _ViralPeriod.monthly: return 'Μηνιαίο';
    }
  }

  String _scopeLabel(BuildContext context) => _scope == _ViralScope.myCity
      ? _homeCity
      : AppLocalizations.of(context).viralOtherCities;

  PopupMenuItem<_ViralScope> _scopeMenuItem(String label, _ViralScope scope, bool isLight) {
    final sel = _scope == scope;
    return PopupMenuItem<_ViralScope>(
      value: scope,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (sel) const Icon(Icons.check_rounded, size: 18, color: Color(0xff1d9bf0)),
        ],
      ),
    );
  }

  PopupMenuItem<_ViralPeriod> _periodMenuItem(String label, _ViralPeriod period, bool isLight) {
    final sel = _period == period;
    return PopupMenuItem<_ViralPeriod>(
      value: period,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: sel
                    ? const Color(0xff1d9bf0)
                    : (isLight ? Colors.black : Colors.white),
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                fontSize: 15,
              ),
            ),
          ),
          if (sel)
            const Icon(Icons.check_rounded, size: 18, color: Color(0xff1d9bf0)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : const Color(0xff000000);
    final dividerColor = isLight ? const Color(0xffe8eaed) : const Color(0xff2a2a2a);
    final muted = isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        Container(
          color: bg,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search bar + Cancel button
              Row(
                children: [
                  Expanded(child: _buildSearchBar(isLight, muted)),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: _searchActive
                        ? Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: GestureDetector(
                              onTap: _cancelSearch,
                              child: Text(
                                AppLocalizations.of(context).cancel,
                                style: const TextStyle(
                                  color: Color(0xff1d9bf0),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              // Viral subtitle row — city pill + period picker (hides while searching)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _searchActive
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            PopupMenuButton<_ViralScope>(
                              onSelected: (scope) {
                                if (_scope == scope) return;
                                setState(() => _scope = scope);
                                _loadViral();
                              },
                              offset: const Offset(0, 32),
                              color: isLight ? Colors.white : const Color(0xff141414),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              itemBuilder: (_) => [
                                _scopeMenuItem(_homeCity, _ViralScope.myCity, isLight),
                                _scopeMenuItem(
                                  AppLocalizations.of(context).viralOtherCities,
                                  _ViralScope.otherCities,
                                  isLight,
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isLight ? const Color(0xfff0f2f5) : const Color(0xff141414),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isLight ? const Color(0xffe0e3e8) : const Color(0xff3a3a3a)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.local_fire_department_rounded, size: 13, color: Color(0xffff6b35)),
                                    const SizedBox(width: 4),
                                    Text(_scopeLabel(context), style: TextStyle(color: isLight ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 3),
                                    Icon(Icons.expand_more_rounded, size: 15, color: muted),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            PopupMenuButton<_ViralPeriod>(
                              onSelected: (p) {
                                if (_period == p) return;
                                setState(() {
                                  _period = p;
                                  _periodAutoWidened = false;
                                });
                                _loadViral(autoWiden: false);
                              },
                              offset: const Offset(0, 32),
                              color: isLight ? Colors.white : const Color(0xff141414),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              itemBuilder: (_) => [
                                _periodMenuItem('Ημερήσιο', _ViralPeriod.daily, isLight),
                                _periodMenuItem('Εβδομαδιαίο', _ViralPeriod.weekly, isLight),
                                _periodMenuItem('Μηνιαίο', _ViralPeriod.monthly, isLight),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isLight ? const Color(0xfff0f2f5) : const Color(0xff141414),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isLight ? const Color(0xffe0e3e8) : const Color(0xff3a3a3a)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_periodLabel(_period), style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 3),
                                    Icon(Icons.expand_more_rounded, size: 15, color: muted),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
        // ── Body ──────────────────────────────────────────────────────────────
        Expanded(
          child: _searchActive ? _buildSearchBody(isLight) : _buildViralBody(isLight),
        ),
      ],
    );
  }

  Widget _buildSearchBar(bool isLight, Color muted) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isLight ? const Color(0xfff4f6f8) : const Color(0xff141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLight ? const Color(0xffe8eaed) : const Color(0xff2a2a2a)),
      ),
      child: _searchActive
          ? TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onChanged,
              onSubmitted: (_) => _submitSearch(),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              style: TextStyle(color: isLight ? Colors.black : Colors.white, fontSize: 15),
              cursorColor: const Color(0xff1d9bf0),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, color: muted, size: 19),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: _clearSearch,
                        child: Icon(Icons.close_rounded, size: 17, color: muted),
                      )
                    : null,
                hintText: AppLocalizations.of(context).searchPeopleAndPosts,
                hintStyle: TextStyle(color: muted, fontSize: 15),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              ),
            )
          : GestureDetector(
              onTap: _activateSearch,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search_rounded, color: muted, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).searchPeopleAndPosts, style: TextStyle(color: muted, fontSize: 15)),
                ],
              ),
            ),
    );
  }

  // ── Viral body ─────────────────────────────────────────────────────────────

  Widget _buildViralBody(bool isLight) {
    if (_loadingViral) return const NeatLoader();
    if (_viralPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department_rounded, size: 48, color: isLight ? const Color(0xffb8c0cc) : const Color(0xff4a5568)),
            const SizedBox(height: 12),
            Text(_scope == _ViralScope.myCity ? AppLocalizations.of(context).noPostsInCity(_homeCity) : AppLocalizations.of(context).noPostsOtherCities, style: TextStyle(color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280), fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    final sortedPosts = [..._viralPosts]..sort((a, b) {
        final diff = _score(b).compareTo(_score(a));
        if (diff != 0) return diff;
        return a.minutesAgo.compareTo(b.minutesAgo);
      });
    return RefreshIndicator(
      onRefresh: _loadViral,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 40),
        itemCount: sortedPosts.length,
        itemBuilder: (_, i) {
          final post = sortedPosts[i];
          final rank = i + 1;
          final isTop3 = rank <= 3;
          final mc = isTop3 ? _mc(rank) : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isTop3)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  decoration: BoxDecoration(
                    color: mc!.withValues(alpha: 0.07),
                    border: Border(left: BorderSide(color: mc, width: 3.5)),
                  ),
                  child: Row(
                    children: [
                      Text('#$rank', style: TextStyle(color: mc, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Row(
                    children: [
                      Text('#$rank', style: TextStyle(color: isLight ? const Color(0xffb8c0cc) : const Color(0xff4a5568), fontSize: 13, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              if (isTop3)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: mc!.withValues(alpha: 0.03),
                    border: Border(left: BorderSide(color: mc.withValues(alpha: 0.25), width: 3.5)),
                  ),
                  child: widget.buildPostCard(post, interactive: _scope == _ViralScope.myCity),
                )
              else
                widget.buildPostCard(post, interactive: _scope == _ViralScope.myCity),
              Divider(height: 1, color: isLight ? const Color(0xffe8eaed) : const Color(0xff141414)),
            ],
          );
        },
      ),
    );
  }

  // ── Search body ─────────────────────────────────────────────────────────────

  void _onChanged(String value) {
    final trimmed = value.trim();
    setState(() => _query = trimmed);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (trimmed.isEmpty) {
        if (mounted) setState(() { _users = []; _didSearch = false; });
      } else {
        _doSearch(trimmed);
      }
    });
  }

  Future<void> _submitSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    await _addToHistory(query);
    await _doSearch(query);
  }

  Future<void> _doSearch(String query) async {
    if (query.isEmpty) return;
    if (mounted) setState(() { _searchLoading = true; _didSearch = true; });
    try {
      final res = await http.get(searchUsersEndpoint(query), headers: authGetHeaders(widget.token));
      if (!mounted) return;
      if (res.statusCode != 200) { setState(() => _searchLoading = false); return; }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(UserProfile.fromJson).toList();
      setState(() { _users = users; _searchLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  List<FeedPost> _searchPosts(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _cityPosts;
    return _cityPosts.where((p) => p.text.toLowerCase().contains(q) || p.author.toLowerCase().contains(q) || p.city.toLowerCase().contains(q)).toList();
  }

  void _openProfile(UserProfile user) {
    _historyUsers[user.username] = user;
    unawaited(_addToHistory(user.username));
    widget.onOpenUserProfile(user.username);
  }

  Future<void> _toggleFollow(UserProfile user) async {
    final was = _followingAuthors.contains(user.username);
    setState(() { if (was) { _followingAuthors.remove(user.username); } else { _followingAuthors.add(user.username); } });
    try {
      final res = await http.post(followEndpoint(user.username), headers: authJsonHeaders(widget.token), body: jsonEncode({'follow': !was}));
      if (res.statusCode >= 400 && mounted) setState(() { if (was) { _followingAuthors.add(user.username); } else { _followingAuthors.remove(user.username); } });
    } catch (_) {
      if (mounted) setState(() { if (was) { _followingAuthors.add(user.username); } else { _followingAuthors.remove(user.username); } });
    }
  }

  Future<void> _loadSuggestions() async {
    if (mounted) setState(() => _loadingSuggestions = true);
    try {
      final uri = suggestionsEndpoint.replace(
        queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final res = await http.get(uri, headers: authGetHeaders(widget.token));
      if (!mounted) return;
      if (res.statusCode != 200) { setState(() => _loadingSuggestions = false); return; }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(UserProfile.fromJson).toList()..shuffle(Random());
      setState(() { _suggestedUsers = users; _loadingSuggestions = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  Future<void> _loadTopUsers() async {
    try {
      final res = await http.get(searchUsersEndpoint(''), headers: authGetHeaders(widget.token));
      if (!mounted) return;
      if (res.statusCode != 200) { setState(() => _loadingTop = false); return; }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(UserProfile.fromJson).toList();
      setState(() { _topUsers = users; _loadingTop = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingTop = false);
    }
  }

  Future<void> _loadCityPosts() async {
    try {
      final res = await http.get(postsEndpoint(city: widget.currentUser.city), headers: authGetHeaders(widget.token));
      if (!mounted || res.statusCode != 200) return;
      final page = await compute(_parseFeedPosts, res.body);
      if (mounted) setState(() => _cityPosts = page.posts);
    } catch (_) {}
  }

  Future<void> _loadRecentQueries() async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getStringList(_historyPrefsKey) ?? [];
    if (local.isNotEmpty) {
      if (mounted) setState(() { _recentQueries..clear()..addAll(local); });
      return;
    }
    try {
      final res = await http.get(searchHistoryEndpoint(), headers: authGetHeaders(widget.token));
      if (!mounted || res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (decoded['queries'] as List<dynamic>? ?? const []).whereType<String>().toList();
      await prefs.setStringList(_historyPrefsKey, items);
      if (mounted) setState(() { _recentQueries..clear()..addAll(items); });
    } catch (_) {}
  }

  Future<void> _loadFollowingAuthors() async {
    try {
      final res = await http.get(followingEndpoint(widget.currentUser.username), headers: authGetHeaders(widget.token));
      if (!mounted || res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final usernames = (decoded['users'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map((u) => u['username']?.toString() ?? '').where((u) => u.isNotEmpty).toSet();
      setState(() => _followingAuthors..clear()..addAll(usernames));
    } catch (_) {}
  }

  Future<void> _addToHistory(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _recentQueries.remove(query);
      _recentQueries.insert(0, query);
      if (_recentQueries.length > 20) _recentQueries.removeLast();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyPrefsKey, _recentQueries.toList());
    try { await http.post(searchHistoryEndpoint(), headers: authJsonHeaders(widget.token), body: jsonEncode({'query': query})); } catch (_) {}
  }

  Future<void> _deleteHistoryItem(String q) async {
    setState(() => _recentQueries.remove(q));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyPrefsKey, _recentQueries.toList());
    try { await http.delete(searchHistoryItemEndpoint(q), headers: authGetHeaders(widget.token)); } catch (_) {}
  }

  Future<void> _clearHistory() async {
    setState(() { _recentQueries.clear(); _historyShown = 5; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyPrefsKey);
    try { await http.delete(searchHistoryEndpoint(), headers: authGetHeaders(widget.token)); } catch (_) {}
  }

  Widget _buildSearchBody(bool isLight) {
    return _didSearch ? _buildResults(isLight, _query) : _buildDefault(isLight);
  }

  Widget _buildDefault(bool isLight) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (_recentQueries.isNotEmpty) ...[
          ..._recentQueries
              .take(_historyShown)
              .map((q) => _buildHistoryRow(q, isLight)),
          if (_recentQueries.length > _historyShown)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _historyShown += 5),
                child: Text(
                  AppLocalizations.of(context).seeMore,
                  style: TextStyle(
                    color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Center(
              child: TextButton(
                onPressed: _clearHistory,
                child: Text(
                  AppLocalizations.of(context).clearAll,
                  style: TextStyle(
                    color: isLight ? const Color(0xff6b7280) : const Color(0xff9ca3af),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          Divider(height: 1, color: isLight ? const Color(0xffe8eaed) : const Color(0xff2a2a2a)),
        ],
        // Who to follow
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).whoToFollow,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.refresh_rounded,
                  color: isLight ? const Color(0xff6b7280) : const Color(0xff9ca3af),
                  size: 22,
                ),
                onPressed: _loadSuggestions,
                tooltip: AppLocalizations.of(context).refresh,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        if (_loadingSuggestions)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_suggestedUsers.isNotEmpty)
          SizedBox(
            height: 172,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestedUsers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _buildSuggestionCard(_suggestedUsers[i], isLight),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildHistoryRow(String q, bool isLight) {
    final user = _historyUsers[q];
    if (user != null) {
      // ── User profile entry ─────────────────────────────────────────────
      final avatar = avatarProvider(user.username, user.avatarUrl);
      final displayName =
          user.fullName.isNotEmpty ? user.fullName : user.username;
      return InkWell(
        onTap: () => widget.onOpenUserProfile(user.username),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                foregroundImage: avatar,
                child: avatar == null
                    ? Text(
                        initialFor(user.username),
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '@${user.username}',
                      style: TextStyle(
                        color: isLight
                            ? const Color(0xff536471)
                            : const Color(0xff71767b),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  _deleteHistoryItem(q);
                  setState(() => _historyUsers.remove(q));
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: isLight
                        ? const Color(0xff9ca3af)
                        : const Color(0xff6b7280),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Text search entry ────────────────────────────────────────────────
    return InkWell(
      onTap: () {
        _searchCtrl.text = q;
        _searchCtrl.selection = TextSelection.collapsed(offset: q.length);
        _submitSearch();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.history_rounded,
              size: 20,
              color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                q,
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _deleteHistoryItem(q),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: isLight
                      ? const Color(0xff9ca3af)
                      : const Color(0xff6b7280),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(bool isLight, String query) {
    final l10n = AppLocalizations.of(context);
    final tabs = [l10n.searchPeople, l10n.searchPosts];
    final divider = isLight ? const Color(0xffe7e7e7) : const Color(0xff2f3336);
    final textColor = isLight ? Colors.black : Colors.white;
    final muted = isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280);
    return Column(
      children: [
        // ── Tab bar ──────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xff000000),
            border: Border(bottom: BorderSide(color: divider)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 6),
              ...List.generate(tabs.length, (i) {
                final sel = _section == i;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _section = i),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: sel ? const Color(0xff1d9bf0) : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        color: sel ? textColor : muted,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        // ── Results ───────────────────────────────────────────────────────
        Expanded(
          child: _searchLoading
              ? const NeatLoader()
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_section),
                    child: _buildResultsList(isLight, query),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildResultsList(bool isLight, String query) {
    final divider = isLight ? const Color(0xffe7e7e7) : const Color(0xff2f3336);
    // Posts tab
    if (_section == 1) {
      final posts = _searchPosts(query);
      if (posts.isEmpty) return _buildEmpty(query, isLight);
      return ListView.separated(
        itemCount: posts.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: divider),
        itemBuilder: (_, i) => _buildPostRow(posts[i], isLight),
      );
    }
    // People tab
    final people = _users.isEmpty ? _topUsers : _users;
    if (people.isEmpty) {
      return _loadingTop
          ? const NeatLoader()
          : _buildEmpty(query, isLight);
    }
    return ListView.separated(
      itemCount: people.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: divider),
      itemBuilder: (_, i) => _buildPersonRow(people[i], isLight),
    );
  }

  Widget _buildEmpty(String query, bool isLight) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              query.isNotEmpty ? AppLocalizations.of(context).noResultsFor(query) : AppLocalizations.of(context).nothingHereYet,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).tryDifferentSearch,
                style: TextStyle(
                  color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPostRow(FeedPost post, bool isLight) {
    final avatar = avatarProvider(post.author, post.avatarUrl);
    final muted = isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280);
    return InkWell(
      onTap: () => widget.onOpenUserProfile(post.author),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              foregroundImage: avatar,
              child: avatar == null
                  ? Text(
                      initialFor(post.author),
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '@${post.author}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (post.city.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '· ${post.city}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isLight ? const Color(0xff1c1c1e) : const Color(0xffe5e5ea),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonRow(UserProfile user, bool isLight) {
    final avatar = avatarProvider(user.username, user.avatarUrl);
    final displayName = user.fullName.isNotEmpty ? user.fullName : user.username;
    return InkWell(
      onTap: () => _openProfile(user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              foregroundImage: avatar,
              child: avatar == null
                  ? Text(
                      initialFor(user.username),
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '@${user.username}',
                    style: TextStyle(
                      color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => _toggleFollow(user),
              style: OutlinedButton.styleFrom(
                foregroundColor: _followingAuthors.contains(user.username)
                    ? (isLight ? const Color(0xff536471) : const Color(0xff71767b))
                    : (isLight ? Colors.black : Colors.white),
                side: BorderSide(
                  color: _followingAuthors.contains(user.username)
                      ? (isLight ? const Color(0xffb8c0cc) : const Color(0xff3a3a3a))
                      : (isLight ? Colors.black : Colors.white),
                  width: 1.5,
                ),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _followingAuthors.contains(user.username)
                    ? AppLocalizations.of(context).following
                    : widget.followerAuthors.contains(user.username)
                        ? AppLocalizations.of(context).followBack
                        : AppLocalizations.of(context).follow,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(UserProfile user, bool isLight) {
    final avatar = avatarProvider(user.username, user.avatarUrl);
    final displayName = user.fullName.isNotEmpty ? user.fullName : user.username;
    return GestureDetector(
      onTap: () => widget.onOpenUserProfile(user.username),
      child: Container(
        width: 136,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 11),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xff000000),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLight ? const Color(0xffe8eaed) : const Color(0xff242424),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              foregroundImage: avatar,
              child: avatar == null
                  ? Text(
                      initialFor(user.username),
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '@${user.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _toggleFollow(user),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isLight ? Colors.black : Colors.white,
                  side: BorderSide(
                    color: _followingAuthors.contains(user.username)
                        ? (isLight ? const Color(0xffb8c0cc) : const Color(0xff3a3a3a))
                        : (isLight ? Colors.black : Colors.white),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: Text(
                  _followingAuthors.contains(user.username)
                      ? 'Following'
                      : widget.followerAuthors.contains(user.username)
                          ? 'Follow Back'
                          : 'Follow',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeAction extends StatelessWidget {
  const _ComposeAction({required this.icon, required this.onTap, this.iconSize = 19, this.active = false});
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: isLight ? Colors.white : const Color(0xff000000),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.all((41.0 - iconSize) / 2),
            child: Icon(
              icon,
              color: active ? const Color(0xff3897f0) : (isLight ? Colors.black : Colors.white),
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Compose poll editor ──────────────────────────────────────────────────────

class _ComposePollEditor extends StatelessWidget {
  const _ComposePollEditor({
    required this.controllers,
    required this.isLight,
    required this.onAddOption,
    required this.onRemoveOption,
    required this.onCancel,
  });
  final List<TextEditingController> controllers;
  final bool isLight;
  final VoidCallback onAddOption;
  final void Function(int) onRemoveOption;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final border = isLight ? const Color(0xffd9dee6) : const Color(0xff2c2c2c);
    final hint = isLight ? const Color(0xff616161) : const Color(0xff8f8f8f);
    final fg = isLight ? Colors.black : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.poll_outlined, size: 16, color: hint),
            const SizedBox(width: 5),
            Text(
              'Poll',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: hint),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onCancel,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Icon(Icons.close_rounded, size: 18, color: hint),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: controllers[i],
                      style: TextStyle(color: fg, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).pollOptionHint(i + 1),
                        hintStyle: TextStyle(color: hint),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ),
                if (controllers.length > 2)
                  GestureDetector(
                    onTap: () => onRemoveOption(i),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.close_rounded, size: 18, color: hint),
                    ),
                  ),
              ],
            ),
          ),
        if (controllers.length < 4)
          GestureDetector(
            onTap: onAddOption,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                '+ Add option',
                style: TextStyle(
                  color: const Color(0xff3897f0),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Compose media item ───────────────────────────────────────────────────────

class _ComposeMedia {
  _ComposeMedia.localImage({required this.imageBytes})
      : type = 'image',
        videoPath = null,
        externalUrl = null;
  _ComposeMedia.localVideo({required this.videoPath})
      : type = 'video',
        imageBytes = null,
        externalUrl = null;
  _ComposeMedia.external({required this.externalUrl, required String mediaType})
      : type = mediaType,
        imageBytes = null,
        videoPath = null;

  final String type;
  final Uint8List? imageBytes; // local image bytes: used for preview and upload
  final String? videoPath;     // local video file path: streamed for upload
  final String? externalUrl;   // Giphy / remote URL: sent as-is

  /// True while the phone is re-encoding this video.
  ///
  /// Nothing is on the network yet during that stretch, so the upload ring has
  /// nothing to show — without saying so the sheet looks like it has stalled.
  bool preparing = false;

  /// The file that is uploaded, once preparing has decided what that is.
  ///
  /// Kept apart from [videoPath] because the preview must not flicker when
  /// compression finishes and swaps the file underneath it: the sheet keeps
  /// showing the original the whole time, and only the upload uses this.
  String? uploadPath;

  /// The staged upload this became, once it has finished going up.
  ///
  /// Media starts uploading the moment it is picked, while the caption is
  /// still being written — so by the time Post is pressed the bytes are
  /// usually already on the server and the post itself is a few hundred bytes.
  /// Null means staging has not finished (or failed), and the file is attached
  /// to the post request the old way instead.
  String? uploadId;

  /// The in-flight staging request, awaited if Post is pressed early.
  Future<String?>? staging;

  bool get isVideo => type == 'video';
}

// ── Notifications sheet ─────────────────────────────────────────────────────

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet({
    required this.fetchNotifications,
    required this.followingAuthors,
    required this.followerAuthors,
    required this.token,
    required this.onFollow,
    required this.onUnfollow,
    required this.onTapItem,
    required this.onOpenUserProfile,
  });
  final Future<List<NotificationItem>> Function() fetchNotifications;
  final Set<String> followingAuthors;
  final Set<String> followerAuthors;
  final String token;
  final Future<void> Function(String username) onFollow;
  final Future<void> Function(String username) onUnfollow;
  final Future<void> Function(NotificationItem, String? eventType) onTapItem;
  final ValueChanged<String> onOpenUserProfile;

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  late Future<List<NotificationItem>> _future;
  late Set<String> _following;
  final Map<String, String> _eventImages = {};
  final Map<String, String> _eventTypes = {};

  @override
  void initState() {
    super.initState();
    _following = Set.of(widget.followingAuthors);
    _future = widget.fetchNotifications().then((items) {
      _loadEventData(items);
      return items;
    });
  }

  Future<void> _loadEventData(List<NotificationItem> items) async {
    final eventNotifs = items
        .where((n) => n.targetType == "event" && n.targetId.isNotEmpty);
    for (final n in eventNotifs) {
      final id = int.tryParse(n.targetId);
      if (id == null) continue;
      try {
        final res = await http.get(
          eventDetailEndpoint(id),
          headers: authGetHeaders(widget.token),
        );
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body) as Map<String, dynamic>;
          final url = decoded['imageUrl']?.toString() ?? '';
          final type = decoded['eventType']?.toString() ?? '';
          if (mounted) {
            setState(() {
              if (url.isNotEmpty) _eventImages[n.targetId] = url;
              if (type.isNotEmpty) _eventTypes[n.targetId] = type;
            });
          }
        }
      } catch (_) {}
    }
  }

  void _toggleFollow(String username) {
    if (_following.contains(username)) {
      setState(() => _following.remove(username));
      widget.onUnfollow(username);
    } else {
      setState(() => _following.add(username));
      widget.onFollow(username);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? Colors.black : Colors.white;
    const subColor = Color(0xff8e8e8e);

    return FutureBuilder<List<NotificationItem>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        final now = DateTime.now();
        final justNow = items
            .where((n) => now.difference(n.created).inMinutes <= 5)
            .toList();
        final today = items.where((n) {
          final diff = now.difference(n.created);
          return diff.inMinutes > 5 && diff.inHours < 24;
        }).toList();
        final last7 = items.where((n) {
          final d = now.difference(n.created).inDays;
          return d >= 1 && d <= 7;
        }).toList();
        final last30 = items.where((n) {
          final d = now.difference(n.created).inDays;
          return d > 7 && d <= 30;
        }).toList();
        final older = items
            .where((n) => now.difference(n.created).inDays > 30)
            .toList();

        Widget tileFor(NotificationItem n) => _NotifTile(
              item: n,
              isFollowing: _following.contains(n.actor),
              followsYou: widget.followerAuthors.contains(n.actor),
              onFollowToggle: () => _toggleFollow(n.actor),
              eventImageUrl: _eventImages[n.targetId] ?? "",
              onTap: () => widget.onTapItem(n, _eventTypes[n.targetId]),
              onOpenUserProfile: () => widget.onOpenUserProfile(n.actor),
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                AppLocalizations.of(context).notificationsTitle,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (items.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    AppLocalizations.of(context).noNotificationsYet,
                    style: TextStyle(color: subColor),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    if (justNow.isNotEmpty) ...[
                      _NotifSectionHeader(title: AppLocalizations.of(context).notifJustNow),
                      ...justNow.map(tileFor),
                    ],
                    if (today.isNotEmpty) ...[
                      _NotifSectionHeader(title: AppLocalizations.of(context).notifToday),
                      ...today.map(tileFor),
                    ],
                    if (last7.isNotEmpty) ...[
                      _NotifSectionHeader(title: AppLocalizations.of(context).notifLast7Days),
                      ...last7.map(tileFor),
                    ],
                    if (last30.isNotEmpty) ...[
                      _NotifSectionHeader(title: AppLocalizations.of(context).notifLast30Days),
                      ...last30.map(tileFor),
                    ],
                    if (older.isNotEmpty) ...[
                      _NotifSectionHeader(title: AppLocalizations.of(context).notifOlder),
                      ...older.map(tileFor),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NotifSectionHeader extends StatelessWidget {
  const _NotifSectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isLight ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}

class _NotifAvatar extends StatelessWidget {
  const _NotifAvatar({required this.url, required this.actor, required this.isLight});
  final String url;
  final String actor;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeAvatarUrl(url);
    final ImageProvider? base = bytes != null
        ? MemoryImage(bytes)
        : (url.startsWith('http')
            ? CachedNetworkImageProvider(url, cacheManager: imageCacheManager)
            : null);
    // Cap the notification-avatar decode — loss-free, tiny in memory.
    final ImageProvider? img = base == null ? null : ResizeImage(base, width: 288);
    return CircleAvatar(
      radius: 22,
      backgroundColor: isLight ? const Color(0xffe0e0e0) : const Color(0xff2a2a2a),
      foregroundImage: img,
      child: Text(
        initialFor(actor),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: isLight ? const Color(0xff333333) : Colors.white,
        ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({
    required this.item,
    required this.isFollowing,
    this.followsYou = false,
    required this.onFollowToggle,
    required this.eventImageUrl,
    required this.onTap,
    required this.onOpenUserProfile,
  });
  final NotificationItem item;
  final bool isFollowing;
  final bool followsYou;
  final VoidCallback onFollowToggle;
  final String eventImageUrl;
  final VoidCallback onTap;
  final VoidCallback onOpenUserProfile;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final unreadBg =
        isLight ? const Color(0xffeff8ff) : const Color(0xff1a2535);
    final bg = isLight ? Colors.white : const Color(0xff000000);
    final textColor = isLight ? Colors.black : Colors.white;
    const subColor = Color(0xff8e8e8e);
    final isFollowVerb = item.verb.contains("follow");
    final isEvent = item.targetType == "event";

    // Trailing widget logic:
    // - follow notification → Follow / Following button (wired up)
    // - event notification with image → show thumbnail
    // - event notification without image → nothing
    // - post notification → grey placeholder thumbnail
    Widget? trailing;
    if (isFollowVerb) {
      trailing = SizedBox(
        height: 34,
        child: OutlinedButton(
          onPressed: onFollowToggle,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            side: BorderSide(
              color: isLight
                  ? const Color(0xffdbdbdb)
                  : const Color(0xff363636),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            foregroundColor: textColor,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(
            isFollowing ? AppLocalizations.of(context).following : followsYou ? AppLocalizations.of(context).followBack : AppLocalizations.of(context).follow,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } else if (isEvent) {
      if (eventImageUrl.isNotEmpty) {
        trailing = ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 44,
            height: 44,
            child: CachedNetworkImage(
              imageUrl: eventImageUrl,
              cacheManager: imageCacheManager,
              fit: BoxFit.cover,
              memCacheWidth: 132, // 44 logical px × 3.0 max DPR
              fadeInDuration: Duration.zero,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        );
      }
      // no image → trailing stays null (nothing shown)
    } else {
      // post notification — show the real photo/video thumbnail; show
      // nothing at all for a text-only post (no blank placeholder box).
      final imgUrl = item.imageUrl;
      final videoUrl = item.videoUrl;
      final thumbBg = isLight ? const Color(0xffe8e8e8) : const Color(0xff2a2a2a);
      Widget? thumb;
      if (videoUrl.isNotEmpty) {
        thumb = _NotifVideoThumb(url: videoUrl, background: thumbBg);
      } else if (imgUrl.startsWith('data:')) {
        final comma = imgUrl.indexOf(',');
        Uint8List? bytes;
        if (comma > -1) {
          try { bytes = base64Decode(imgUrl.substring(comma + 1)); } catch (_) {}
        }
        if (bytes != null) {
          thumb = Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 132);
        }
      } else if (imgUrl.isNotEmpty) {
        thumb = CachedNetworkImage(
          imageUrl: imgUrl,
          cacheManager: imageCacheManager,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          memCacheWidth: 132, // 44 logical px × 3.0 max DPR
          fadeInDuration: Duration.zero,
          errorWidget: (_, _, _) => const SizedBox.shrink(),
        );
      }
      if (thumb != null) {
        trailing = ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: thumb,
        );
      }
      // else: text-only post → trailing stays null, nothing shown
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        color: item.isRead ? bg : unreadBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenUserProfile,
              child: _NotifAvatar(
                url: item.actorAvatarUrl,
                actor: item.actor,
                isLight: isLight,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style:
                      TextStyle(fontSize: 14, color: textColor, height: 1.4),
                  children: [
                    TextSpan(
                      text: item.actor,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: " ${_actionLabel(item.verb, AppLocalizations.of(context))}"),
                    if (item.targetText.isNotEmpty)
                      TextSpan(
                        text: ": ${item.targetText}",
                        style: const TextStyle(color: subColor),
                      ),
                    TextSpan(
                      text: "  ${_timeAgo(item.created, AppLocalizations.of(context))}",
                      style: const TextStyle(color: subColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

/// The strip at the top of the feed while a post is being delivered.
///
/// Posting no longer holds a screen open, so this is the only thing that says
/// the work is still happening — a line of text and a bar, out of the way of
/// whatever the user went back to doing. Instagram's is the same idea: the
/// upload is not a modal state, it is a background one.
class _PostingBanner extends StatelessWidget {
  const _PostingBanner({
    required this.label,
    required this.progress,
    required this.isLight,
  });

  final ValueListenable<String?> label;
  final ValueListenable<double?> progress;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: label,
      builder: (context, text, _) {
        // AnimatedSize rather than a hard show/hide: the feed below should
        // settle into place, not jump.
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: text == null
              ? const SizedBox(width: double.infinity)
              : ValueListenableBuilder<double?>(
                  valueListenable: progress,
                  builder: (context, value, _) {
                    final ink = isLight ? Colors.black : Colors.white;
                    final track = isLight
                        ? const Color(0xffe3e6ea)
                        : const Color(0xff2a2a2a);
                    final percent = value == null
                        ? null
                        : (value * 100).clamp(0, 100).round();
                    return Container(
                      width: double.infinity,
                      color: isLight ? Colors.white : const Color(0xff0a0a0a),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  percent == null ? text : '$text  $percent%',
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              minHeight: 2.5,
                              // Indeterminate until there are bytes to count —
                              // a bar frozen at 0% reads as stuck.
                              value: value,
                              backgroundColor: track,
                              valueColor: AlwaysStoppedAnimation<Color>(ink),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// A multipart request that reports how much of itself has gone out.
///
/// `http` gives no upload progress of its own, and the send is a single
/// awaited future — fine when a post was four photos, useless now that it can
/// be a minute of video. Wrapping the finalized byte stream is the whole
/// trick: the transform sees every chunk on its way to the socket.
class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(super.method, super.url, {required this.onProgress});

  /// Called with bytes sent and the total, on every chunk.
  final void Function(int sent, int total) onProgress;

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(
      byteStream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, sink) {
            sent += chunk.length;
            onProgress(sent, total);
            sink.add(chunk);
          },
        ),
      ),
    );
  }
}

/// First frame of a video that has been picked but not yet posted.
///
/// Compose used to draw a grey box with a camcorder glyph here, which told you
/// a video was attached but not *which* one — picking the wrong clip from the
/// gallery was invisible until after it was published. [video_player] can open
/// the local file and hold frame 0, so the preview is the real thing at no
/// cost beyond one decoder for as long as the sheet is open.
class _ComposeVideoPreview extends StatefulWidget {
  const _ComposeVideoPreview({required this.path, this.badgeSize = 36});
  final String path;
  final double badgeSize;

  @override
  State<_ComposeVideoPreview> createState() => _ComposeVideoPreviewState();
}

class _ComposeVideoPreviewState extends State<_ComposeVideoPreview> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ctrl = VideoPlayerController.file(File(widget.path));
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _ctrl = ctrl);
    } catch (_) {
      // An undecodable file still posts fine — the server transcodes it — so
      // fall back to the placeholder rather than blocking the compose sheet.
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final ready = ctrl != null && ctrl.value.isInitialized;
    return Container(
      color: const Color(0xff141414),
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: ctrl.value.size.width,
                height: ctrl.value.size.height,
                child: VideoPlayer(ctrl),
              ),
            ),
          // The play badge doubles as the "still loading" state: until the
          // first frame arrives it is all there is to see, which is exactly
          // what the old placeholder showed anyway.
          Center(
            child: Icon(
              ready ? Icons.play_circle_fill : Icons.videocam_rounded,
              color: ready ? Colors.white : Colors.white54,
              size: widget.badgeSize,
            ),
          ),
          if (ready)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _clock(ctrl.value.duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// Small paused/muted first-frame thumbnail for video-post notifications.
// No server-side thumbnail exists, so this decodes just enough of the
// video to grab frame 0 — acceptable for a single 44x44 icon per row.
class _NotifVideoThumb extends StatefulWidget {
  const _NotifVideoThumb({required this.url, required this.background});
  final String url;
  final Color background;

  @override
  State<_NotifVideoThumb> createState() => _NotifVideoThumbState();
}

class _NotifVideoThumbState extends State<_NotifVideoThumb> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cached = await getCachedVideoFile(widget.url);
      final ctrl = cached != null
          ? VideoPlayerController.file(cached)
          : VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _ctrl = ctrl);
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return Container(
      width: 44,
      height: 44,
      color: widget.background,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          if (ctrl != null && ctrl.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: ctrl.value.size.width,
                height: ctrl.value.size.height,
                child: VideoPlayer(ctrl),
              ),
            ),
          const Icon(Icons.play_circle_fill, color: Colors.white, size: 18),
        ],
      ),
    );
  }
}

String _actionLabel(String verb, AppLocalizations l10n) {
  return switch (verb) {
    'liked your post' => l10n.notifLikedPost,
    'commented on your post' => l10n.notifCommentedPost,
    'followed you' => l10n.notifStartedFollowing,
    'replied to your comment' => l10n.notifRepliedComment,
    'liked your comment' => l10n.notifLikedComment,
    'mentioned you in a comment' => l10n.notifMentionedComment,
    'mentioned you in a post' => l10n.notifMentionedPost,
    _ => verb,
  };
}

class _CommentSheet extends StatefulWidget {
  const _CommentSheet({
    required this.post,
    required this.session,
    required this.onRefresh,
    required this.onOpenUserProfile,
    this.likingEnabled = true,
    this.highlightActor,
    this.highlightCommentId,
    this.onHideNavBar,
    this.onShowNavBar,
  });
  final FeedPost post;
  final AuthSession session;
  final VoidCallback onRefresh;
  final ValueChanged<String> onOpenUserProfile;
  final bool likingEnabled;
  final String? highlightActor;
  // Exact comment/reply id to scroll to and flash-highlight; takes precedence
  // over [highlightActor] when set.
  final int? highlightCommentId;
  final VoidCallback? onHideNavBar;
  final VoidCallback? onShowNavBar;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  final _picker = ImagePicker();
  late List<FeedComment> _comments;
  final _liked = <int, bool>{};
  final _likes = <int, int>{};
  final _likedByOwner = <int, bool>{};
  final _commentKeys = <int, GlobalKey>{};
  int? _highlightedCommentId;
  int? _pressedCommentId;
  FeedComment? _replyingTo;
  // When replying to a reply, this holds the top-level comment's id so we
  // send the correct parentId to the backend (replies are one level deep).
  int? _effectiveParentId;
  String _imageUrl = '';
  /// The picked JPEG itself, so a comment image uploads as a file part.
  Uint8List? _imageBytes;
  String _gifUrl   = '';
  bool _sending = false;
  bool _picking = false;
  bool _hydratingComments = false;

  @override
  void initState() {
    super.initState();
    _comments = List.from(widget.post.comments);
    _seedMaps(_comments);
    // Lightweight payloads (the viral/charts list) ship the comment count but
    // not the threads, to keep that response small. If we were opened on such a
    // post, pull the real comments now from the post-detail endpoint.
    if (_comments.isEmpty && widget.post.commentCount > 0) {
      _hydrateComments();
    }
    if (_hasHighlightTarget) {
      // If comments are already loaded, scroll after they lay out; the empty
      // case is handled once _hydrateComments finishes.
      if (_comments.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _scrollToHighlightTarget();
        });
      }
    }
  }

  bool get _hasHighlightTarget =>
      widget.highlightCommentId != null || widget.highlightActor != null;

  Future<void> _hydrateComments() async {
    setState(() => _hydratingComments = true);
    try {
      final res = await http.get(
        postDetailEndpoint(widget.post.id),
        headers: authGetHeaders(widget.session.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _applyUpdatedPost(jsonDecode(res.body) as Map<String, dynamic>);
        // Comments just arrived — if we were opened to highlight one, do it now.
        if (mounted && _hasHighlightTarget && _comments.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted) _scrollToHighlightTarget();
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _hydratingComments = false);
    }
  }

  /// Finds the comment/reply to land on — by exact [highlightCommentId] when
  /// provided (the interaction's real target), otherwise the actor's most
  /// recent comment — then scrolls to it and flashes a highlight.
  Future<void> _scrollToHighlightTarget() async {
    FeedComment? target;
    final wantedId = widget.highlightCommentId;
    if (wantedId != null) {
      for (final c in _comments) {
        if (c.id == wantedId) { target = c; break; }
        for (final r in c.replies) {
          if (r.id == wantedId) { target = r; break; }
        }
        if (target != null) break;
      }
    }
    if (target == null && widget.highlightActor != null) {
      // Fallback: the actor's most recent comment/reply.
      for (final c in _comments) {
        if (c.author == widget.highlightActor) target = c;
        for (final r in c.replies) {
          if (r.author == widget.highlightActor) target = r;
        }
      }
    }
    if (target == null || !mounted) return;

    // Phase 1: scroll to bottom so the latest comment is built in the viewport
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // Phase 2: precise scroll to the comment
    final key = _commentKeys[target.id];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.3,
      );
    }
    if (!mounted) return;

    // Phase 3: flash highlight
    setState(() => _highlightedCommentId = target!.id);
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _highlightedCommentId = null);
  }

  void _seedMaps(List<FeedComment> list) {
    for (final c in list) {
      _liked[c.id] = c.liked;
      _likes[c.id] = c.likes;
      _likedByOwner[c.id] = c.likedByOwner;
      _seedMaps(c.replies);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _setReply(FeedComment c, {int? effectiveParentId}) {
    setState(() {
      _replyingTo = c;
      _effectiveParentId = effectiveParentId;
    });
    // Small delay so the reply banner renders before the keyboard appears.
    Future.microtask(() => _inputFocus.requestFocus());
  }

  Future<void> _pickImage() async {
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final mime = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      setState(() {
        _imageUrl = 'data:image/$mime;base64,${base64Encode(bytes)}';
        // Kept so the picture can go up as a file rather than as base64 in the
        // JSON body, which costs a third more bytes.
        _imageBytes = bytes;
        _gifUrl = '';
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickGif() async {
    final completer = Completer<String?>();
    final listener = _GifPickerListener(
      onSelect: (GiphyMedia media) {
        final url = media.images.fixedWidth?.gifUrl ?? media.images.original?.gifUrl ?? '';
        if (!completer.isCompleted) completer.complete(url.isNotEmpty ? url : null);
      },
      onDismissed: () { if (!completer.isCompleted) completer.complete(null); },
    );
    GiphyDialog.instance.addListener(listener);
    GiphyDialog.instance.configure(
      settings: GiphySettings(
        theme: GiphyTheme.automaticTheme,
        mediaTypeConfig: [GiphyContentType.gif, GiphyContentType.sticker],
        selectedContentType: GiphyContentType.gif,
        showSuggestionsBar: true,
        showConfirmationScreen: false,
      ),
    );
    GiphyDialog.instance.show();
    final url = await completer.future;
    GiphyDialog.instance.removeListener(listener);
    if (!mounted || url == null || url.isEmpty) return;
    setState(() { _gifUrl = url; _imageUrl = ''; _imageBytes = null; });
  }


  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _imageUrl.isEmpty && _gifUrl.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      final fields = <String, String>{
        'text': text,
        if (_gifUrl.isNotEmpty) 'imageUrl': _gifUrl,
        if (_replyingTo != null)
          'parentId': '${_effectiveParentId ?? _replyingTo!.id}',
        if (_effectiveParentId != null) 'replyToUsername': _replyingTo!.author,
      };
      final http.Response res;
      if (_imageBytes != null) {
        final request = http.MultipartRequest(
          'POST', postCommentsEndpoint(widget.post.id),
        )
          ..headers.addAll(authGetHeaders(widget.session.token))
          ..fields.addAll(fields)
          ..files.add(http.MultipartFile.fromBytes(
            'image', _imageBytes!, filename: 'comment.jpg',
          ));
        res = await http.Response.fromStream(await request.send());
      } else {
        res = await http.post(
          postCommentsEndpoint(widget.post.id),
          headers: authJsonHeaders(widget.session.token),
          body: jsonEncode({
            ...fields,
            if (_imageUrl.isNotEmpty) 'imageUrl': _imageUrl,
          }),
        );
      }
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        _applyUpdatedPost(decoded);
        setState(() {
          _replyingTo = null;
          _effectiveParentId = null;
          _imageUrl = ''; _imageBytes = null;
          _gifUrl   = '';
        });
        _controller.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _applyUpdatedPost(Map<String, dynamic> decoded) {
    final updated = FeedPost.fromJson(decoded);
    setState(() {
      _comments = updated.comments;
      _seedMaps(updated.comments);
    });
    widget.post.comments
      ..clear()
      ..addAll(updated.comments);
    widget.onRefresh();
  }

  Future<void> _deleteComment(FeedComment c) async {
    try {
      final res = await http.delete(
        postCommentsEndpoint(widget.post.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({'commentId': c.id}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _applyUpdatedPost(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _pinComment(FeedComment c) async {
    try {
      final res = await http.post(
        commentPinEndpoint(c.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({'pinned': !c.pinned}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _applyUpdatedPost(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  void _showCommentMenu(FeedComment c, bool isReply) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final currentUsername = widget.session.user.username;
    final isOwnComment = c.author == currentUsername;
    final isAdmin = widget.session.user.isAdmin;
    final isPostOwner = widget.post.author == currentUsername;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff000000),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((isPostOwner || isAdmin) && !isReply)
              ListTile(
                leading: Icon(c.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
                title: Text(c.pinned ? AppLocalizations.of(context).unpinComment : AppLocalizations.of(context).pinComment),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pinComment(c);
                },
              ),
            if (isOwnComment || isAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xfff66c6c)),
                title: Text(AppLocalizations.of(context).deleteComment),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _deleteComment(c);
                },
              ),
            if (!isOwnComment)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(AppLocalizations.of(context).reportComment),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  widget.onHideNavBar?.call();
                  showReportCommentSheet(
                    context,
                    endpoint: commentReportEndpoint(c.id),
                    token: widget.session.token,
                  ).whenComplete(() => widget.onShowNavBar?.call());
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(FeedComment comment) async {
    final was = _liked[comment.id] ?? comment.liked;
    final next = (_likes[comment.id] ?? comment.likes) + (was ? -1 : 1);
    final isOwner = widget.session.user.username == widget.post.author;
    setState(() {
      _liked[comment.id] = !was;
      _likes[comment.id] = next;
      if (isOwner) _likedByOwner[comment.id] = !was;
    });
    try {
      await http.post(
        commentLikeEndpoint(comment.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({'liked': !was}),
      );
      comment.liked = !was;
      comment.likes = next;
      if (isOwner) comment.likedByOwner = !was;
    } catch (_) {
      setState(() {
        _liked[comment.id] = was;
        _likes[comment.id] = (_likes[comment.id] ?? comment.likes) + (was ? 1 : -1);
        if (isOwner) _likedByOwner[comment.id] = was;
      });
    }
  }

  Widget _tile(BuildContext context, FeedComment c, bool isReply, bool isLight, {int? parentCommentId}) {
    final avatar = avatarProvider(c.author, c.avatarUrl);
    final isNetworkImg = c.imageUrl.startsWith('http');
    final imgBytes = (!isNetworkImg && c.imageUrl.isNotEmpty) ? decodeAvatarUrl(c.imageUrl) : null;
    final isLiked = _liked[c.id] ?? c.liked;
    final likeCount = _likes[c.id] ?? c.likes;
    final highlighted = c.id == _highlightedCommentId;
    final commentKey = _commentKeys.putIfAbsent(c.id, () => GlobalKey());
    DateTime? created;
    try { created = DateTime.parse(c.createdAt); } catch (_) {}
    final pressed = c.id == _pressedCommentId;
    return AnimatedContainer(
      key: commentKey,
      duration: const Duration(milliseconds: 150),
      color: highlighted
          ? (isLight ? const Color(0xfffff3cc) : const Color(0xff3a2e00))
          : pressed
              ? (isLight ? const Color(0xffeeeeee) : const Color(0xff2a2a2a))
              : Colors.transparent,
      child: Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 52 : 16, 10, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => widget.onOpenUserProfile(c.author),
            child: CircleAvatar(
              radius: isReply ? 14 : 18,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              foregroundImage: avatar,
              child: avatar == null
                  ? Text(
                      initialFor(c.author),
                      style: TextStyle(
                        color: isLight ? const Color(0xff444444) : Colors.white,
                        fontSize: isReply ? 9 : 11,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.likingEnabled
                  ? () => _setReply(c, effectiveParentId: isReply ? parentCommentId : null)
                  : null,
              onLongPressDown: (_) => setState(() => _pressedCommentId = c.id),
              onLongPressCancel: () => setState(() => _pressedCommentId = null),
              onLongPress: () {
                setState(() => _pressedCommentId = null);
                _showCommentMenu(c, isReply);
              },
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.pinned) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context).pinnedByAuthor,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: c.author,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: isReply ? 13.5 : 15,
                          height: 1.4,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => widget.onOpenUserProfile(c.author),
                      ),
                      if (c.replyToUsername != null) ...[
                        TextSpan(
                          text: '  ▶  ',
                          style: TextStyle(
                            color: isLight ? const Color(0xffa0a0a8) : const Color(0xff666672),
                            fontSize: isReply ? 11 : 12,
                            height: 1.4,
                          ),
                        ),
                        TextSpan(
                          text: c.replyToUsername,
                          style: TextStyle(
                            color: isLight ? const Color(0xff536471) : const Color(0xff8899a6),
                            fontWeight: FontWeight.w600,
                            fontSize: isReply ? 13.5 : 15,
                            height: 1.4,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => widget.onOpenUserProfile(c.replyToUsername!),
                        ),
                      ],
                      if (c.author == widget.post.author) ...[
                        TextSpan(
                          text: ' · ',
                          style: TextStyle(
                            color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                            fontWeight: FontWeight.w400,
                            fontSize: isReply ? 12 : 13,
                            height: 1.4,
                          ),
                        ),
                        TextSpan(
                          text: AppLocalizations.of(context).creator,
                          style: TextStyle(
                            color: const Color(0xff3897f0),
                            fontWeight: FontWeight.w700,
                            fontSize: isReply ? 12 : 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (c.text.isNotEmpty) ...[
                  RichText(
                    text: TextSpan(
                      children: buildMentionSpans(
                        c.text,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w400,
                          fontSize: isReply ? 13.5 : 15,
                          height: 1.5,
                        ),
                        mentionStyle: TextStyle(
                          color: const Color(0xff3897f0),
                          fontWeight: FontWeight.w600,
                          fontSize: isReply ? 13.5 : 15,
                          height: 1.5,
                        ),
                        onTapMention: widget.onOpenUserProfile,
                      ),
                    ),
                  ),
                  if (firstUrl(c.text) case final link?)
                    LinkPreviewCard(
                      url: link,
                      token: widget.session.token,
                      isLight: isLight,
                      compact: isReply,
                    ),
                ],
                if (imgBytes != null) ...[
                  const SizedBox(height: 8),
                  _CommentPhoto(bytes: imgBytes),
                ] else if (isNetworkImg) ...[
                  const SizedBox(height: 8),
                  _CommentPhoto(url: c.imageUrl),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (created != null)
                      Text(
                        _timeAgo(created, AppLocalizations.of(context)),
                        style: TextStyle(
                          fontSize: 12,
                          color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                        ),
                      ),
                    const SizedBox(width: 14),
                    if (widget.likingEnabled)
                      GestureDetector(
                        onTap: () => _setReply(c, effectiveParentId: isReply ? parentCommentId : null),
                        child: Text(
                          AppLocalizations.of(context).reply,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_likedByOwner[c.id] ?? c.likedByOwner) ...[
                  const SizedBox(height: 3),
                  Text(
                    AppLocalizations.of(context).likedByCreator,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                    ),
                  ),
                ],
              ],
            ), // Column
            ), // GestureDetector
          ),   // Expanded
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.likingEnabled ? () => _toggleLike(c) : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.likingEnabled)
                  Icon(
                    isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 18,
                    color: isLiked
                        ? const Color(0xfff66c6c)
                        : (isLight ? const Color(0xffa0a0a0) : const Color(0xff6a6a6a)),
                  )
                else
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.favorite_border_rounded,
                          size: 18,
                          color: isLight
                              ? const Color(0xffa0a0a0)
                              : const Color(0xff6a6a6a),
                        ),
                        CustomPaint(
                          size: const Size(18, 18),
                          painter: _SlashPainterSmall(
                            color: isLight
                                ? const Color(0xffa0a0a0)
                                : const Color(0xff6a6a6a),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (likeCount > 0)
                  Text(
                    '$likeCount',
                    style: TextStyle(
                      fontSize: 10,
                      color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showCommentMenu(c, isReply),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 0, 0),
              child: Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: isLight ? const Color(0xffa0a0a0) : const Color(0xff6a6a6a),
              ),
            ),
          ),
        ],
      ),
      ), // AnimatedContainer
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final userAvatar = avatarProvider(widget.session.user.username, widget.session.user.avatarUrl);
    final previewBytes = _imageUrl.isNotEmpty ? decodeAvatarUrl(_imageUrl) : null;
    final hasGif = _gifUrl.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                  child: Text(
                    AppLocalizations.of(context).commentsTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
              Expanded(
                child: _comments.isEmpty
                    ? Center(
                        child: _hydratingComments
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : Text(
                                widget.likingEnabled ? AppLocalizations.of(context).noCommentsBeFirst : AppLocalizations.of(context).noCommentsYet,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isLight ? const Color(0xff8b95a3) : const Color(0xffb3b3b3),
                                  height: 1.6,
                                ),
                              ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _comments.length,
                        itemBuilder: (context, i) {
                          final c = _comments[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _tile(context, c, false, isLight),
                              for (final r in c.replies)
                                _tile(context, r, true, isLight, parentCommentId: c.id),
                              const SizedBox(height: 4),
                            ],
                          );
                        },
                      ),
              ),
              if (widget.likingEnabled) ...[
              Divider(height: 1, color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
              if (previewBytes != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SizedBox(
                    height: 72,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(previewBytes, height: 72, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() { _imageUrl = ''; _imageBytes = null; }),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (hasGif)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SizedBox(
                    height: 72,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(_gifUrl, height: 72, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _gifUrl = ''),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_replyingTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.reply_rounded,
                        size: 16,
                        color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to @${_replyingTo!.author}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() { _replyingTo = null; _effectiveParentId = null; }),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                        ),
                      ),
                    ],
                  ),
                ),
              MentionSuggestions(
                controller: _controller,
                token: widget.session.token,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                      foregroundImage: userAvatar,
                      child: userAvatar == null
                          ? Text(
                              initialFor(widget.session.user.username),
                              style: TextStyle(
                                color: isLight ? const Color(0xff444444) : Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _picking ? null : _pickImage,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.photo_outlined,
                          size: 24,
                          color: _picking
                              ? (isLight ? const Color(0xffd0d0d0) : const Color(0xff444444))
                              : (isLight ? const Color(0xff536471) : const Color(0xff71767b)),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pickGif,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.gif,
                          size: 28,
                          color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) {
                          final canSend =
                              value.text.trim().isNotEmpty || _imageUrl.isNotEmpty || _gifUrl.isNotEmpty;
                          return TextField(
                            controller: _controller,
                            focusNode: _inputFocus,
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 14,
                            ),
                            cursorColor: isLight ? Colors.black : Colors.white,
                            decoration: InputDecoration(
                              hintText: _replyingTo != null
                                  ? AppLocalizations.of(context).replyToHint(_replyingTo!.author)
                                  : AppLocalizations.of(context).addCommentHint,
                              hintStyle: TextStyle(
                                color: isLight
                                    ? const Color(0xff8b95a3)
                                    : const Color(0xff9a9a9a),
                                fontSize: 14,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              filled: true,
                              fillColor: isLight
                                  ? const Color(0xfff0f2f5)
                                  : const Color(0xff141414),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: canSend
                                  ? _sending
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      : GestureDetector(
                                          onTap: _send,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Container(
                                              width: 34,
                                              height: 34,
                                              decoration: const BoxDecoration(
                                                color: Color(0xff3897f0),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                                            ),
                                          ),
                                        )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              ], // end if (widget.likingEnabled)
            ],
          ),
        ),
      ),
    );
  }
}

String _timeAgo(DateTime created, AppLocalizations l10n) {
  final diff = DateTime.now().difference(created);
  if (diff.inMinutes < 1) return l10n.justNow;
  if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
  return l10n.timeDaysAgo(diff.inDays);
}

// ── GIF picker listener ───────────────────────────────────────────────────────

class _GifPickerListener implements GiphyMediaSelectionListener {
  _GifPickerListener({required this.onSelect, required this.onDismissed});
  final void Function(GiphyMedia media) onSelect;
  final VoidCallback onDismissed;

  @override
  void onMediaSelect(GiphyMedia media) => onSelect(media);

  @override
  void onDismiss() => onDismissed();
}


class _SlashPainterSmall extends CustomPainter {
  const _SlashPainterSmall({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.72, size.height * 0.04),
      Offset(size.width * 0.28, size.height * 0.96),
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }
  @override
  bool shouldRepaint(_SlashPainterSmall old) => old.color != color;
}

/// The strip at the end of the feed that asks for the next page.
///
/// Uses the same VisibilityDetector the feed already relies on for video
/// autoplay, so "the reader has reached the bottom" is measured the same way
/// everywhere rather than by guessing at scroll offsets.
class _FeedPageLoader extends StatelessWidget {
  const _FeedPageLoader({required this.onVisible});
  final VoidCallback onVisible;

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: const Key('feed-page-loader'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0) onVisible();
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(child: NeatLoader(size: 34, color: Color(0xff8e8e8e))),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.isLight});
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isLight ? const Color(0xfff0f0f0) : const Color(0xff141414),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 13,
            color: isLight ? const Color(0xff888888) : const Color(0xff888888),
          ),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context).noInternet,
            style: TextStyle(
              color: isLight ? const Color(0xff666666) : const Color(0xff999999),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comment photo
// ─────────────────────────────────────────────────────────────────────────────

/// A photo attached to a comment, sized the way TikTok sizes them.
///
/// The thumbnail keeps its aspect ratio inside a fixed box rather than filling
/// the comment's width, so a portrait shot — which used to render at full
/// width and whatever height that implied — can't swallow the thread. Tapping
/// opens the full image.
class _CommentPhoto extends StatelessWidget {
  const _CommentPhoto({this.bytes, this.url});

  final Uint8List? bytes;
  final String? url;

  // Both caps apply, and RenderImage fits the picture inside them without
  // distorting it: a landscape photo ends up 168 wide, a portrait one 210 tall.
  static const double _maxWidth = 168;
  static const double _maxHeight = 210;

  @override
  Widget build(BuildContext context) {
    // Decoding a full-resolution photo just to draw it at thumbnail size is
    // what makes a comment thread with a few pictures expensive.
    final cacheWidth =
        (_maxWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final Widget? thumb = bytes != null
        ? Image.memory(bytes!, cacheWidth: cacheWidth, gaplessPlayback: true)
        : (url != null && url!.isNotEmpty
            ? Image.network(url!, cacheWidth: cacheWidth, gaplessPlayback: true)
            : null);
    if (thumb == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _openFullscreen(context),
      // Align both anchors the thumbnail left and — the part that matters —
      // hands the ConstrainedBox loose constraints. A parent that sizes its
      // children to a tight width (a ListView, a stretched Column) would
      // otherwise override maxWidth entirely and the cap would do nothing.
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _maxWidth,
            maxHeight: _maxHeight,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: thumb,
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    final full = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.contain)
        : Image.network(url!, fit: BoxFit.contain);
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: SizedBox(
                    width: MediaQuery.of(ctx).size.width,
                    height: MediaQuery.of(ctx).size.height,
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: full,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 12,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ));
  }
}
