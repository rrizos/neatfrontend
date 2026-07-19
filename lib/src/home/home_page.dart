import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:video_player/video_player.dart';

import '../core/api.dart';
import '../core/media_cache.dart';
import '../core/mentions.dart';
import '../core/models.dart';
import '../core/post_card.dart';
import '../core/push_service.dart';
import '../core/report_post_sheet.dart';
import '../core/share_sheet.dart';
import '../events/events_page.dart';
import '../map/city_map_view.dart';
import '../map/greece_cities.dart';
import '../messages/messages_page.dart';
import '../profile/profile_page.dart';

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

class _HomePageState extends State<HomePage> {
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
  bool _composePollActive = false;
  final _composePollControllers = <TextEditingController>[];
  int _unreadMessages = 0;
  bool _hasOfficialEvents = false;
  bool _showInlineProfile = false;
  String _inlineProfileUsername = '';
  int? _inlinePostId;
  bool _isIOS26 = false;
  int _navBarHideCount = 0; // reference count; bar only shows when this reaches 0

  static bool _detectIOS26() {
    if (kIsWeb || !Platform.isIOS) return false;
    final major = int.tryParse(
        Platform.operatingSystemVersion.split('.').first) ?? 0;
    return major >= 26;
  }

  @override
  void initState() {
    super.initState();
    _isIOS26 = _detectIOS26();
    _setupNativeTabChannel();
    // Paint last-known posts instantly instead of a blank spinner while the
    // network round-trip for fresh ones is still in flight.
    unawaited(_loadCachedPosts());
    _load();
    _loadNotifications(silent: true);
    PushService.instance.onDmTap = _openConversationById;
    PushService.instance.onSoftTap = _openNotifications;
    PushService.instance.replayPending();
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
          // Native iOS 26 tab bar is live — switch Flutter layout to placeholder and show bar.
          if (mounted) {
            if (!_isIOS26) setState(() => _isIOS26 = true);
            _kTabChannel.invokeMethod('showTabBar');
          }
      }
    });
  }

  @override
  void dispose() {
    if (_isIOS26) _kTabChannel.invokeMethod('hideTabBar');
    _kTabChannel.setMethodCallHandler(null);
    if (identical(PushService.instance.onDmTap, _openConversationById)) {
      PushService.instance.onDmTap = null;
    }
    if (identical(PushService.instance.onSoftTap, _openNotifications)) {
      PushService.instance.onSoftTap = null;
    }
    _compose.dispose();
    for (final c in _composePollControllers) { c.dispose(); }
    _cityScroll.dispose();
    _followingScroll.dispose();
    super.dispose();
  }


  String get _postsCacheKey =>
      _activeCity == null ? 'cached_posts_home' : 'cached_posts_city_$_activeCity';

  Future<void> _saveCachedPosts(List<dynamic> raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_postsCacheKey, jsonEncode(raw));
    } catch (_) {}
  }

  Future<void> _loadCachedPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_postsCacheKey);
      if (raw == null || !mounted) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      final posts = decoded.whereType<Map<String, dynamic>>().map(FeedPost.fromJson).toList();
      if (mounted) {
        setState(() {
          _posts
            ..clear()
            ..addAll(posts);
          _loading = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        postsEndpoint(fresh: true, city: _activeCity),
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode == 401) return widget.onLogout();
      final decoded = jsonDecode(res.body) as List<dynamic>;
      final posts = decoded
          .whereType<Map<String, dynamic>>()
          .map(FeedPost.fromJson)
          .toList();
      unawaited(_saveCachedPosts(decoded));
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
        _loading = false;
        _isOffline = false;
      });
      await Future.wait([_loadFollowingAuthors(), _loadFollowerAuthors(), _loadUnreadMessages(), _loadOfficialEventsBadge()]);
    } catch (_) {
      await _loadCachedPosts();
      if (mounted) setState(() { _loading = false; _isOffline = true; });
    }
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
  }

  static const _kMaxImageBytes = 6 * 1024 * 1024; // 6 MB per image
  static const _kMaxVideoBytes = 20 * 1024 * 1024; // 20 MB per video

  Future<void> _createPost(StateSetter setPageState) async {
    final text = _compose.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    setPageState(() {});
    var popped = false;
    try {
      final request = http.MultipartRequest('POST', postsEndpoint())
        ..headers['Authorization'] = 'Token ${widget.session.token}';
      request.fields['text'] = text;

      final mediaInfo = <Map<String, dynamic>>[];
      int fileIndex = 0;
      for (final m in _composeMedia) {
        if (m.externalUrl != null) {
          mediaInfo.add({'type': m.type, 'url': m.externalUrl!, 'order': mediaInfo.length});
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

      if (_composePollActive && _composePollControllers.length >= 2) {
        final options = _composePollControllers
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        if (options.length >= 2) {
          request.fields['poll'] = jsonEncode({'options': options});
        }
      }

      final streamed = await http.sharedHttpClient.send(request).timeout(const Duration(seconds: 180));
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode == 201) {
        _compose.clear();
        setState(() {
          _composeMedia.clear();
          _composePollActive = false;
          for (final c in _composePollControllers) { c.dispose(); }
          _composePollControllers.clear();
        });
        popped = true;
        Navigator.of(context).pop();
        _load();
      } else if (res.statusCode == 413) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File too large. Try a shorter video or smaller photos.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyHttpError(res))),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('TimeoutException')
            ? 'Upload timed out. Please try again.'
            : 'Network error. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (!popped && mounted) {
        setState(() => _posting = false);
        setPageState(() {});
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
    setPageState(() {});
    if (skipped > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$skipped photo${skipped > 1 ? 's were' : ' was'} too large and skipped. Try selecting a different photo.',
          ),
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
        const SnackBar(content: Text('Photo is too large. Try again.')),
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
    setPageState(() {});
  }

  Future<void> _pickComposeVideo(StateSetter setPageState) async {
    final picked = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 30),
    );
    if (picked == null || !mounted) return;
    setState(() => _composeMediaLoading = true);
    setPageState(() {});
    final fileSize = await picked.length();
    if (!mounted) return;
    if (fileSize > _kMaxVideoBytes) {
      setState(() => _composeMediaLoading = false);
      setPageState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Video is too large (${(fileSize / 1024 / 1024).toStringAsFixed(0)} MB). Try a shorter clip under 30 seconds.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _composeMediaLoading = false;
      _composeMedia.clear();
      _composeMedia.add(_ComposeMedia.localVideo(videoPath: picked.path));
    });
    setPageState(() {});
  }

  void _removeComposeMedia(int index, StateSetter setPageState) {
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

  void _openProfileAtPost(String username, int postId) {
    setState(() {
      _inlineProfileUsername = username;
      _inlinePostId = postId;
      _showInlineProfile = true;
      _nav = 0;
    });
  }

  void _pushProfileRoute(String username, {int? postId, bool? followEnabled}) {
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
          initialPostId: postId,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onHideNavBar: _hideNativeBar,
          onShowNavBar: _showNativeBar,
          followEnabled: followEnabled ?? _activeCity == null,
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
    setState(() {
      _activeCity = null;
      _nav = 0;
      _showInlineProfile = false;
      _inlinePostId = null;
      _loading = true;
    });
    await _load();
  }

  Future<void> _openEvents({int initialTab = 0}) async {
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
        ),
      ),
    );
    _showNativeBar();
  }

  Future<void> _openNotificationTarget(NotificationItem item, {String? eventType}) async {
    if (item.targetType == 'event') {
      final tab = eventType == 'community' ? 1 : 0;
      await _openEvents(initialTab: tab);
      return;
    }
    if (item.targetType == 'post' && item.targetId.isNotEmpty) {
      final post = _posts
          .where((p) => p.id.toString() == item.targetId)
          .toList();
      if (post.isNotEmpty) {
        _openComments(post.first);
        return;
      }
      await _load();
      final refreshed = _posts
          .where((p) => p.id.toString() == item.targetId)
          .toList();
      if (refreshed.isNotEmpty) {
        _openComments(refreshed.first);
        return;
      }
    }
    _pushProfileRoute(item.actor);
  }

  void _openNotifications() {
    _hideNativeBar();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
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
            Navigator.of(sheetCtx).pop();
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
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConversationPage(
          token: widget.session.token,
          currentUsername: widget.session.user.username,
          conversationId: conv.id,
          otherUsername: conv.otherUser,
          otherFullName: conv.otherFullName,
          otherAvatarUrl: conv.otherAvatarUrl,
          otherLastActive: conv.otherLastActive,
          onLogout: widget.onLogout,
          onOpenPost: (author, postId) {
            Navigator.popUntil(context, (route) => route.isFirst);
            _openProfileAtPost(author, postId);
          },
          onOpenUserProfile: _pushProfileRoute,
        ),
      ));
      _showNativeBar();
      _loadUnreadMessages();
    } catch (_) {}
  }

  void _openComments(FeedPost post) {
    _hideNativeBar();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      builder: (_) => _CommentSheet(
        post: post,
        session: widget.session,
        onRefresh: () {},
        onOpenUserProfile: _pushProfileRoute,
        likingEnabled: _activeCity == null,
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
            Widget preview;
            if (item.isVideo) {
              preview = Container(
                color: const Color(0xff1a1a1a),
                child: const Center(
                  child: Icon(Icons.videocam_rounded,
                      color: Colors.white54, size: 36),
                ),
              );
            } else if (item.imageBytes != null) {
              preview = Image.memory(item.imageBytes!, fit: BoxFit.cover);
            } else if (item.externalUrl != null) {
              preview = CachedNetworkImage(
                imageUrl: item.externalUrl!,
                cacheManager: imageCacheManager,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
              );
            } else {
              preview = const ColoredBox(color: Color(0xff1a1a1a));
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
              Widget preview;
              if (item.isVideo) {
                preview = Container(
                  color: const Color(0xff1a1a1a),
                  child: const Center(
                    child: Icon(Icons.videocam_rounded,
                        color: Colors.white54, size: 48),
                  ),
                );
              } else if (item.imageBytes != null) {
                preview = Image.memory(item.imageBytes!, fit: BoxFit.cover);
              } else if (item.externalUrl != null) {
                preview = CachedNetworkImage(
                  imageUrl: item.externalUrl!,
                  cacheManager: imageCacheManager,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                );
              } else {
                preview = const ColoredBox(color: Color(0xff1a1a1a));
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(children: [
                  AspectRatio(aspectRatio: 1.15, child: preview),
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
                canPop: !_posting,
                child: Scaffold(
                backgroundColor:
                    isLight ? Colors.white : const Color(0xff111111),
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
                              onPressed: _posting
                                  ? null
                                  : () => Navigator.of(pageContext).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: isLight ? Colors.black : Colors.white,
                                disabledForegroundColor: const Color(0xff8a8a8a),
                                padding: EdgeInsets.zero,
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              child: const Text('Cancel'),
                            ),
                            const Spacer(),
                            Text(
                              'New post',
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
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              isLight ? Colors.white : Colors.black,
                                            ),
                                          ),
                                        )
                                      : const Text('Post'),
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
                                                return AnimatedContainer(
                                                  duration: const Duration(
                                                      milliseconds: 180),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: count > 240
                                                        ? const Color(
                                                            0xff301818)
                                                        : (isLight
                                                            ? const Color(
                                                                0xffeef1f5)
                                                            : const Color(
                                                                0xff1a1a1a)),
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(999),
                                                    border: Border.all(
                                                      color: count > 240
                                                          ? const Color(
                                                              0xff7a2f2f)
                                                          : (isLight
                                                              ? const Color(
                                                                  0xffd9dee6)
                                                              : const Color(
                                                                  0xff2c2c2c)),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '$count/280',
                                                    style: TextStyle(
                                                      color: count > 240
                                                          ? const Color(
                                                              0xffff9a9a)
                                                          : (isLight
                                                              ? const Color(
                                                                  0xff616161)
                                                              : const Color(
                                                                  0xff9a9a9a)),
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
      backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xff141414),
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
                  'No posts yet.',
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
                            title: const Text('Delete post'),
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _deletePost(post);
                            },
                          ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.flag_outlined),
                          title: const Text('Report post'),
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
        ],
      ),
    );
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
                title: const Text('Delete post'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _deletePost(post);
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report post'),
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
          backgroundColor: isLight ? Colors.white : const Color(0xff141414),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cityPosts = _posts;
    final followingPosts = _followingAuthors.isEmpty
        ? const <FeedPost>[]
        : _posts.where((p) => _followingAuthors.contains(p.author)).toList();

    final isLight = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLight ? const Color(0xfff3f4f6) : const Color(0xff121212),
      extendBody: _isIOS26,
      body: SafeArea(
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
                  MaterialPageRoute(
                    builder: (_) => MessagesPage(
                      token: widget.session.token,
                      currentUsername: widget.session.user.username,
                      suggestedUsers: _followingProfiles,
                      onLogout: widget.onLogout,
                      onOpenPost: (author, postId) {
                        Navigator.popUntil(context, (route) => route.isFirst);
                        _openProfileAtPost(author, postId);
                      },
                      onOpenUserProfile: _pushProfileRoute,
                    ),
                  ),
                );
                _showNativeBar();
                _loadUnreadMessages();
              },
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
      // iOS 26: native UITabBar is added as a subview in SceneDelegate.
      // A transparent SizedBox(49) tells Flutter's layout how much bottom
      // space to reserve so SafeArea pads content correctly.
      bottomNavigationBar: _isIOS26
          ? SizedBox(height: 49 + MediaQuery.of(context).viewPadding.bottom)
          : _buildLegacyNavBar(isLight),
    );
  }

  // ── iOS legacy nav bar ─────────────────────────────────────────────────────

  Widget _buildLegacyNavBar(bool isLight) {
    final avatarBytes   = decodeAvatarUrl(widget.session.user.avatarUrl);
    final activeColor   = isLight ? Colors.black : Colors.white;
    final imageProvider = avatarBytes != null ? MemoryImage(avatarBytes) : null;

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
          backgroundColor: isLight ? Colors.white : const Color(0xff151515),
          iconSize: 26,
          selectedFontSize: 0,
          unselectedFontSize: 0,
          onTap: _onNavTap,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline_rounded),
              activeIcon: Icon(Icons.add_circle_rounded),
              label: 'Create',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map_rounded),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: profileIcon(active: false),
              activeIcon: profileIcon(active: true),
              label: 'Profile',
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
                    color: isLight ? const Color(0xfff0f2f5) : const Color(0xff1e1e1e),
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
                            : 'Home',
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
              const SizedBox(width: 4),
              _iconWithDot(
                isLight: isLight,
                showDot: hasOfficialEvents,
                onTap: onEventsTap,
                icon: Icons.event_note_outlined,
              ),
            ],
            if (activeCity == null) ...[
              _iconWithDot(
                isLight: isLight,
                showDot: hasOfficialEvents,
                onTap: onEventsTap,
                icon: Icons.event_note_outlined,
              ),
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
    final bg = isLight ? const Color(0xfff3f4f6) : const Color(0xff121212);

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
                                'Following',
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
  _ViralView({
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

class _ViralViewState extends State<_ViralView> {
  // ── Viral ──────────────────────────────────────────────────────────────────
  String _city = '';
  List<FeedPost> _viralPosts = [];
  bool _loadingViral = true;
  _ViralPeriod _period = _ViralPeriod.weekly;

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
    _city = widget.currentUser.city;
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

  double _score(FeedPost p) => (p.likes * 0.45 + p.comments.length * 0.55) * 100;

  int _minutesSincePeriodStart() {
    final now = DateTime.now();
    final DateTime periodStart;
    switch (_period) {
      case _ViralPeriod.daily:
        periodStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
      case _ViralPeriod.weekly:
        periodStart = DateTime(now.year, now.month, now.day - (now.weekday - 1), 0, 0, 0);
      case _ViralPeriod.monthly:
        periodStart = DateTime(now.year, now.month, 1, 0, 0, 0);
    }
    return now.difference(periodStart).inMinutes;
  }

  Future<void> _loadViral() async {
    if (mounted) setState(() => _loadingViral = true);
    try {
      final res = await http.get(
        postsEndpoint(city: _city),
        headers: authGetHeaders(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => _loadingViral = false);
        return;
      }
      final decoded = jsonDecode(res.body) as List<dynamic>;
      final cutoff = _minutesSincePeriodStart();
      final posts = decoded
          .whereType<Map<String, dynamic>>()
          .map(FeedPost.fromJson)
          .where((p) => p.minutesAgo <= cutoff)
          .toList();
      posts.sort((a, b) {
        final diff = _score(b).compareTo(_score(a));
        if (diff != 0) return diff;
        return a.minutesAgo.compareTo(b.minutesAgo);
      });
      setState(() {
        _viralPosts = posts.take(10).toList();
        _loadingViral = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingViral = false);
    }
  }

  void refresh() {
    if (_searchActive) _cancelSearch();
    _loadViral();
  }

  Future<void> _selectCity(BuildContext context) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    widget.onHideNavBar();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (ctx, sc) => Column(
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isLight ? const Color(0xffd1d5db) : const Color(0xff3a3a3a),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Select City',
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Builder(builder: (ctx) {
              final userCity = widget.currentUser.city;
              final sorted = [
                ...greeceCities.where((c) => c.name == userCity),
                ...greeceCities.where((c) => c.name != userCity),
              ];
              return Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final city = sorted[i];
                  final selected = city.name == _city;
                  return ListTile(
                    title: Text(
                      city.name,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_rounded, color: Color(0xff1d9bf0))
                        : null,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      if (city.name != _city) {
                        setState(() => _city = city.name);
                        _loadViral();
                      }
                    },
                  );
                },
              ),
            );
            }),
          ],
        ),
      ),
    );
    widget.onShowNavBar();
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
    final bg = isLight ? Colors.white : const Color(0xff121212);
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
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
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
                            GestureDetector(
                              onTap: () => _selectCity(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isLight ? const Color(0xfff0f2f5) : const Color(0xff1e1e1e),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isLight ? const Color(0xffe0e3e8) : const Color(0xff3a3a3a)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.local_fire_department_rounded, size: 13, color: Color(0xffff6b35)),
                                    const SizedBox(width: 4),
                                    Text(_city, style: TextStyle(color: isLight ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
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
                                setState(() => _period = p);
                                _loadViral();
                              },
                              offset: const Offset(0, 32),
                              color: isLight ? Colors.white : const Color(0xff1e1e1e),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              itemBuilder: (_) => [
                                _periodMenuItem('Ημερήσιο', _ViralPeriod.daily, isLight),
                                _periodMenuItem('Εβδομαδιαίο', _ViralPeriod.weekly, isLight),
                                _periodMenuItem('Μηνιαίο', _ViralPeriod.monthly, isLight),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isLight ? const Color(0xfff0f2f5) : const Color(0xff1e1e1e),
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
        color: isLight ? const Color(0xfff4f6f8) : const Color(0xff1a1a1a),
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
                hintText: 'Search people and posts',
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
                  Text('Search people and posts', style: TextStyle(color: muted, fontSize: 15)),
                ],
              ),
            ),
    );
  }

  // ── Viral body ─────────────────────────────────────────────────────────────

  Widget _buildViralBody(bool isLight) {
    if (_loadingViral) return const Center(child: CircularProgressIndicator());
    if (_viralPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department_rounded, size: 48, color: isLight ? const Color(0xffb8c0cc) : const Color(0xff4a5568)),
            const SizedBox(height: 12),
            Text('No posts in $_city yet', style: TextStyle(color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280), fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadViral,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 40),
        itemCount: _viralPosts.length,
        itemBuilder: (_, i) {
          final post = _viralPosts[i];
          final rank = i + 1;
          final score = _score(post);
          final isTop3 = rank <= 3;
          final mc = isTop3 ? _mc(rank) : null;
          final scoreStr = '${score.toInt()} neat pts';
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
                      const Spacer(),
                      Opacity(opacity: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: mc.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)), child: Text(scoreStr, style: TextStyle(color: mc, fontSize: 12, fontWeight: FontWeight.w700)))),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Row(
                    children: [
                      Text('#$rank', style: TextStyle(color: isLight ? const Color(0xffb8c0cc) : const Color(0xff4a5568), fontSize: 13, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Opacity(opacity: 0, child: Text(scoreStr, style: TextStyle(color: isLight ? const Color(0xffb8c0cc) : const Color(0xff4a5568), fontSize: 12))),
                    ],
                  ),
                ),
              if (isTop3)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: mc!.withValues(alpha: 0.03),
                    border: Border(left: BorderSide(color: mc.withValues(alpha: 0.25), width: 3.5)),
                  ),
                  child: widget.buildPostCard(post, interactive: _city == widget.currentUser.city),
                )
              else
                widget.buildPostCard(post, interactive: _city == widget.currentUser.city),
              Divider(height: 1, color: isLight ? const Color(0xffe8eaed) : const Color(0xff1f1f1f)),
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
      final res = await http.get(suggestionsEndpoint, headers: authGetHeaders(widget.token));
      if (!mounted) return;
      if (res.statusCode != 200) { setState(() => _loadingSuggestions = false); return; }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(UserProfile.fromJson).toList();
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
      final decoded = jsonDecode(res.body) as List<dynamic>;
      if (mounted) setState(() => _cityPosts = decoded.whereType<Map<String, dynamic>>().map(FeedPost.fromJson).toList());
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
                  'See more',
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
                  'Clear all',
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
                  'Who to follow',
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
                tooltip: 'Refresh',
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
      final bytes = decodeAvatarUrl(user.avatarUrl);
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
                foregroundImage: bytes != null ? MemoryImage(bytes) : null,
                child: bytes == null
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
    const tabs = ['People', 'Posts'];
    final divider = isLight ? const Color(0xffe7e7e7) : const Color(0xff2f3336);
    final textColor = isLight ? Colors.black : Colors.white;
    final muted = isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280);
    return Column(
      children: [
        // ── Tab bar ──────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xff121212),
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
              ? const Center(child: CircularProgressIndicator())
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
          ? const Center(child: CircularProgressIndicator())
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
              query.isNotEmpty ? 'No results for\n"$query"' : 'Nothing here yet.',
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
                'Try a different search term.',
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
    final bytes = decodeAvatarUrl(post.avatarUrl);
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
              foregroundImage: bytes != null ? MemoryImage(bytes) : null,
              child: bytes == null
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
                      Text(
                        '@${post.author}',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (post.city.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· ${post.city}',
                          style: TextStyle(color: muted, fontSize: 13),
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
    final bytes = decodeAvatarUrl(user.avatarUrl);
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
              foregroundImage: bytes != null ? MemoryImage(bytes) : null,
              child: bytes == null
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
                    ? 'Following'
                    : widget.followerAuthors.contains(user.username)
                        ? 'Follow Back'
                        : 'Follow',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(UserProfile user, bool isLight) {
    final bytes = decodeAvatarUrl(user.avatarUrl);
    final displayName = user.fullName.isNotEmpty ? user.fullName : user.username;
    return GestureDetector(
      onTap: () => widget.onOpenUserProfile(user.username),
      child: Container(
        width: 136,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 11),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xff131313),
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
              foregroundImage: bytes != null ? MemoryImage(bytes) : null,
              child: bytes == null
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
        color: isLight ? Colors.white : const Color(0xff171717),
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
  });
  final List<TextEditingController> controllers;
  final bool isLight;
  final VoidCallback onAddOption;
  final void Function(int) onRemoveOption;

  @override
  Widget build(BuildContext context) {
    final border = isLight ? const Color(0xffd9dee6) : const Color(0xff2c2c2c);
    final hint = isLight ? const Color(0xff616161) : const Color(0xff8f8f8f);
    final fg = isLight ? Colors.black : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
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
                        hintText: 'Option ${i + 1}',
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
                "Notifications",
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
              const Expanded(
                child: Center(
                  child: Text(
                    "No notifications yet.",
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
                      const _NotifSectionHeader(title: "Just Now"),
                      ...justNow.map(tileFor),
                    ],
                    if (today.isNotEmpty) ...[
                      const _NotifSectionHeader(title: "Today"),
                      ...today.map(tileFor),
                    ],
                    if (last7.isNotEmpty) ...[
                      const _NotifSectionHeader(title: "Last 7 Days"),
                      ...last7.map(tileFor),
                    ],
                    if (last30.isNotEmpty) ...[
                      const _NotifSectionHeader(title: "Last 30 Days"),
                      ...last30.map(tileFor),
                    ],
                    if (older.isNotEmpty) ...[
                      const _NotifSectionHeader(title: "Older"),
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
    final ImageProvider? img = bytes != null
        ? MemoryImage(bytes)
        : (url.startsWith('http')
            ? CachedNetworkImageProvider(url, cacheManager: imageCacheManager)
            : null);
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
    final bg = isLight ? Colors.white : const Color(0xff141414);
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
            padding: const EdgeInsets.symmetric(horizontal: 14),
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
          child: Text(isFollowing ? "Following" : followsYou ? "Follow Back" : "Follow"),
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
          thumb = Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover);
        }
      } else if (imgUrl.isNotEmpty) {
        thumb = CachedNetworkImage(
          imageUrl: imgUrl,
          cacheManager: imageCacheManager,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
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
                    TextSpan(text: " ${_actionLabel(item.verb)}"),
                    if (item.targetText.isNotEmpty)
                      TextSpan(
                        text: ": ${item.targetText}",
                        style: const TextStyle(color: subColor),
                      ),
                    TextSpan(
                      text: "  ${_timeAgo(item.created)}",
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

String _actionLabel(String verb) {
  return switch (verb) {
    'liked your post' => 'liked your post',
    'commented on your post' => 'commented on your post',
    'followed you' => 'started following you',
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
    this.onHideNavBar,
    this.onShowNavBar,
  });
  final FeedPost post;
  final AuthSession session;
  final VoidCallback onRefresh;
  final ValueChanged<String> onOpenUserProfile;
  final bool likingEnabled;
  final VoidCallback? onHideNavBar;
  final VoidCallback? onShowNavBar;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  late List<FeedComment> _comments;
  final _liked = <int, bool>{};
  final _likes = <int, int>{};
  final _likedByOwner = <int, bool>{};
  FeedComment? _replyingTo;
  String _imageUrl = '';
  String _gifUrl   = '';
  bool _sending = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _comments = List.from(widget.post.comments);
    _seedMaps(_comments);
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
    super.dispose();
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
      setState(() { _imageUrl = 'data:image/$mime;base64,${base64Encode(bytes)}'; _gifUrl = ''; });
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
    setState(() { _gifUrl = url; _imageUrl = ''; });
  }


  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _imageUrl.isEmpty && _gifUrl.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await http.post(
        postCommentsEndpoint(widget.post.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({
          'text': text,
          if (_imageUrl.isNotEmpty) 'imageUrl': _imageUrl,
          if (_gifUrl.isNotEmpty) 'imageUrl': _gifUrl,
          if (_replyingTo != null) 'parentId': _replyingTo!.id,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        _applyUpdatedPost(decoded);
        setState(() {
          _replyingTo = null;
          _imageUrl = '';
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
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((isPostOwner || isAdmin) && !isReply)
              ListTile(
                leading: Icon(c.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
                title: Text(c.pinned ? 'Unpin comment' : 'Pin comment'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pinComment(c);
                },
              ),
            if (isOwnComment || isAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xfff66c6c)),
                title: const Text('Delete comment'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _deleteComment(c);
                },
              ),
            if (!isOwnComment)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report comment'),
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

  Widget _tile(BuildContext context, FeedComment c, bool isReply, bool isLight) {
    final bytes = decodeAvatarUrl(c.avatarUrl);
    final isNetworkImg = c.imageUrl.startsWith('http');
    final imgBytes = (!isNetworkImg && c.imageUrl.isNotEmpty) ? decodeAvatarUrl(c.imageUrl) : null;
    final isLiked = _liked[c.id] ?? c.liked;
    final likeCount = _likes[c.id] ?? c.likes;
    DateTime? created;
    try { created = DateTime.parse(c.createdAt); } catch (_) {}
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 52 : 16, 10, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => widget.onOpenUserProfile(c.author),
            child: CircleAvatar(
              radius: isReply ? 14 : 18,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              foregroundImage: bytes != null ? MemoryImage(bytes) : null,
              child: bytes == null
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
                        'Pinned by author',
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
                          text: 'Creator',
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
                if (c.text.isNotEmpty)
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
                if (imgBytes != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(imgBytes, width: double.infinity, fit: BoxFit.cover),
                  ),
                ] else if (isNetworkImg) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(c.imageUrl, width: double.infinity, fit: BoxFit.cover),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (created != null)
                      Text(
                        _timeAgo(created),
                        style: TextStyle(
                          fontSize: 12,
                          color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                        ),
                      ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: () => setState(() => _replyingTo = c),
                      child: Text(
                        'Reply',
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
                    'Liked by creator',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final userBytes = decodeAvatarUrl(widget.session.user.avatarUrl);
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
                    'Comments',
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
                        child: Text(
                          widget.likingEnabled ? 'No comments yet.\nBe the first!' : 'No comments yet.',
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
                                _tile(context, r, true, isLight),
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
                            onTap: () => setState(() => _imageUrl = ''),
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
                        onTap: () => setState(() => _replyingTo = null),
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
                      foregroundImage: userBytes != null ? MemoryImage(userBytes) : null,
                      child: userBytes == null
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
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 14,
                            ),
                            cursorColor: isLight ? Colors.black : Colors.white,
                            decoration: InputDecoration(
                              hintText: _replyingTo != null
                                  ? 'Reply to @${_replyingTo!.author}...'
                                  : 'Add a comment...',
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
                                  : const Color(0xff1e1e1e),
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

String _timeAgo(DateTime created) {
  final diff = DateTime.now().difference(created);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
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

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.isLight});
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isLight ? const Color(0xfff0f0f0) : const Color(0xff1e1e1e),
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
            'No internet connection',
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
