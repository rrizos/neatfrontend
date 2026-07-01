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
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/media_cache.dart';
import '../core/models.dart';
import '../core/post_card.dart';
import '../core/report_post_sheet.dart';
import '../core/share_sheet.dart';
import '../events/events_page.dart';
import '../map/city_map_view.dart';
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
  final ScrollController _feedScroll = ScrollController();
  final Map<int, double> _tabScrollOffsets = {0: 0.0, 1: 0.0};
  int _nav = 0;
  int _selectedTab = 0;
  final Set<int> _visitedTabs = <int>{0};
  final _searchViewKey = GlobalKey<_SearchViewState>();
  bool _loading = true;
  String? _activeCity;
  final _composeMedia = <_ComposeMedia>[];
  bool _composeMediaLoading = false;
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
    _load();
    _loadNotifications(silent: true);
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
    _compose.dispose();
    _feedScroll.dispose();
    super.dispose();
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
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
        _loading = false;
      });
      await Future.wait([_loadFollowingAuthors(), _loadFollowerAuthors()]);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _loadNotifications({bool silent = false}) async {
    try {
      final res = await http.get(
        notificationsEndpoint,
        headers: authGetHeaders(widget.session.token),
      );
      if (res.statusCode == 401) return widget.onLogout();
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final notifications =
          (decoded['notifications'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(NotificationItem.fromJson)
              .toList();
      if (!mounted) return;
      setState(() {
        _notificationsList
          ..clear()
          ..addAll(notifications);
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<List<NotificationItem>> _fetchNotifications() async {
    final res = await http.get(
      notificationsEndpoint,
      headers: authGetHeaders(widget.session.token),
    );
    if (res.statusCode == 401) {
      await widget.onLogout();
      return const [];
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return (decoded['notifications'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NotificationItem.fromJson)
        .toList();
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
              verb: item.verb,
              targetType: item.targetType,
              targetId: item.targetId,
              targetText: item.targetText,
              imageUrl: item.imageUrl,
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

  Future<void> _createPost() async {
    final text = _compose.text.trim();
    if (text.isEmpty) return;
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

      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode == 201) {
        _compose.clear();
        setState(() => _composeMedia.clear());
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

  void _pushProfileRoute(String username, {int? postId}) {
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
          followEnabled: _activeCity == null,
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

  void _openComments(FeedPost post) {
    _hideNativeBar();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      builder: (_) => _CommentSheet(
        post: post,
        session: widget.session,
        onRefresh: () {},
        onOpenUserProfile: _pushProfileRoute,
        likingEnabled: _activeCity == null,
      ),
    ).whenComplete(_showNativeBar);
  }

  void _openCreatePost() {
    _compose.clear();
    _composeMedia.clear();
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

              return Scaffold(
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
                              onPressed: () => Navigator.of(pageContext).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: isLight ? Colors.black : Colors.white,
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
                                  onPressed: canPost ? _createPost : null,
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
                                  child: const Text('Post'),
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
                                            hintText: "What's happening?",
                                            hintStyle: TextStyle(
                                              color: isLight
                                                  ? const Color(0xff616161)
                                                  : const Color(0xff8f8f8f),
                                            ),
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                          ),
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
                                        // ── action row ───────────────────
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            // Photos (max 4, disabled if video present)
                                            if (!_composeMediaLoading &&
                                                !_composeMedia.any(
                                                (m) => m.isVideo) &&
                                                _composeMedia.length < 4)
                                              _ComposeAction(
                                                icon: Icons.image_outlined,
                                                onTap: () =>
                                                    _pickComposeImages(
                                                        setPageState),
                                              ),
                                            // Video (disabled if any media present)
                                            if (!_composeMediaLoading &&
                                                _composeMedia.isEmpty)
                                              _ComposeAction(
                                                icon: Icons
                                                    .videocam_outlined,
                                                onTap: () =>
                                                    _pickComposeVideo(
                                                        setPageState),
                                              ),
                                            // GIF (disabled if any media present)
                                            if (_composeMedia.isEmpty)
                                              _ComposeAction(
                                                icon: Icons
                                                    .gif_box_outlined,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filtered = _selectedTab == 1
        ? (_followingAuthors.isEmpty
            ? const <FeedPost>[]
            : _posts.where((post) => _followingAuthors.contains(post.author)).toList())
        : _posts;

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
              },
            ),
            Divider(
              height: 1,
              color: isLight ? const Color(0xffd6d9df) : const Color(0xff232323),
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
                        // 0: Feed — always mounted so scroll state survives tab switches
                        RefreshIndicator(
                          onRefresh: _load,
                          child: CustomScrollView(
                            controller: _feedScroll,
                            slivers: [
                              const SliverToBoxAdapter(child: SizedBox.shrink()),
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: _TabsHeader(
                                  selectedTab: _selectedTab,
                                  city: _activeCity ?? widget.session.user.city,
                                  showFollowing: _activeCity == null,
                                  scrollController: _feedScroll,
                                  onTabChanged: (value) {
                                    if (_feedScroll.hasClients) {
                                      _tabScrollOffsets[_selectedTab] = _feedScroll.offset;
                                    }
                                    setState(() => _selectedTab = value);
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (_feedScroll.hasClients) {
                                        _feedScroll.jumpTo(_tabScrollOffsets[value] ?? 0.0);
                                      }
                                    });
                                  },
                                ),
                              ),
                              if (filtered.isEmpty)
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
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final post = filtered[index];
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
                                      onShare: () {
                                        _hideNativeBar();
                                        showShareSheet(
                                          context: context,
                                          post: post,
                                          token: widget.session.token,
                                          currentUser: widget.session.user,
                                          onLogout: widget.onLogout,
                                        ).whenComplete(_showNativeBar);
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
                                                showReportPostSheet(
                                                  context,
                                                  postId: post.id,
                                                  token: widget.session.token,
                                                );
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
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                        // 1: Search — mounted lazily on first visit
                        _visitedTabs.contains(1)
                            ? _SearchView(
                                key: _searchViewKey,
                                token: widget.session.token,
                                currentUser: widget.session.user,
                                onOpenUserProfile: _pushProfileRoute,
                                onOpenPost: (u, id) => _pushProfileRoute(u, postId: id),
                                followerAuthors: _followerAuthors,
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
                        key: ValueKey('$_inlineProfileUsername:${_inlinePostId ?? ""}'),
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
    if (_activeCity != null && (i == 1 || i == 2 || i == 4)) return;
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
      setState(() {
        _nav = 0;
        _showInlineProfile = false;
        _inlinePostId = null;
      });
      if (_isIOS26) _kTabChannel.invokeMethod('syncTab', 0);
      return;
    }
    setState(() {
      _nav = i;
      _visitedTabs.add(i);
      _showInlineProfile = false;
    });
    if (i == 1) _searchViewKey.currentState?._refreshFollowState();
    if (_isIOS26) _kTabChannel.invokeMethod('syncTab', i);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.notifications,
    required this.onEventsTap,
    required this.onNotificationsTap,
    required this.onMessagesTap,
    this.activeCity,
    this.homeCity,
    this.onReturnHome,
  });
  final int notifications;
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
              GestureDetector(
                onTap: onEventsTap,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Icon(
                      Icons.event_note_outlined,
                      color: isLight ? Colors.black : Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
            if (activeCity == null) ...[
              GestureDetector(
                onTap: onEventsTap,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Icon(
                      Icons.event_note_outlined,
                      color: isLight ? Colors.black : Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: onNotificationsTap,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Icon(
                          Icons.favorite_border_rounded,
                          color: isLight ? Colors.black : Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  if (notifications > 0)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: const Color(0xfff66c6c),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isLight ? Colors.white : const Color(0xff121212),
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          notifications > 9 ? '9+' : '$notifications',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              GestureDetector(
                onTap: onMessagesTap,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: PostShareIcon(
                      color: isLight ? Colors.black : Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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

class _SearchView extends StatefulWidget {
  _SearchView({
    super.key,
    required this.token,
    required this.currentUser,
    required this.onOpenUserProfile,
    required this.onOpenPost,
    this.followerAuthors = const {},
  });

  final String token;
  final UserProfile currentUser;
  final ValueChanged<String> onOpenUserProfile;
  final void Function(String username, int postId) onOpenPost;
  final Set<String> followerAuthors;

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  final List<String> _recentQueries = [];
  List<UserProfile> _suggestedUsers = [];
  List<UserProfile> _users = [];
  List<UserProfile> _topUsers = [];
  List<FeedPost> _cityPosts = [];
  bool _loading = false;
  bool _loadingSuggestions = true;
  bool _loadingTop = true;
  int _section = 0;
  final Set<String> _followingAuthors = {};

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    _loadTopUsers();
    _loadCityPosts();
    _load('');
    _loadRecentQueries();
    _loadFollowingAuthors();
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _load(value);
      if (value.trim().isEmpty) {
        _loadTopUsers();
      }
    });
  }

  Future<void> _load(String query) async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        searchUsersEndpoint(query),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode == 401) return;
      if (res.statusCode != 200) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final res = await http.get(
        suggestionsEndpoint,
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode != 200) {
        if (mounted) setState(() => _loadingSuggestions = false);
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _suggestedUsers = users;
        _loadingSuggestions = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  Future<void> _loadRecentQueries() async {
    try {
      final res = await http.get(
        searchHistoryEndpoint,
        headers: authGetHeaders(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (decoded['queries'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList();
      setState(() {
        _recentQueries
          ..clear()
          ..addAll(items);
      });
    } catch (_) {}
  }

  Future<void> _addToHistory(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _recentQueries.remove(query);
      _recentQueries.insert(0, query);
      if (_recentQueries.length > 8) _recentQueries.removeLast();
    });
    try {
      await http.post(
        searchHistoryEndpoint,
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'query': query}),
      );
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    setState(() => _recentQueries.clear());
    try {
      await http.delete(
        searchHistoryEndpoint,
        headers: authGetHeaders(widget.token),
      );
    } catch (_) {}
  }

  void _refreshFollowState() => _loadFollowingAuthors();

  Future<void> _loadFollowingAuthors() async {
    try {
      final res = await http.get(
        followingEndpoint(widget.currentUser.username),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode != 200 || !mounted) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final usernames = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((u) => u['username']?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toSet();
      setState(() {
        _followingAuthors..clear()..addAll(usernames);
      });
    } catch (_) {}
  }

  Future<void> _toggleFollow(UserProfile user) async {
    final isFollowing = _followingAuthors.contains(user.username);
    setState(() {
      if (isFollowing) {
        _followingAuthors.remove(user.username);
      } else {
        _followingAuthors.add(user.username);
      }
    });
    try {
      final res = await http.post(
        followEndpoint(user.username),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'follow': !isFollowing}),
      );
      if (res.statusCode == 401 && mounted) {
        setState(() {
          if (isFollowing) {
            _followingAuthors.add(user.username);
          } else {
            _followingAuthors.remove(user.username);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isFollowing) {
            _followingAuthors.add(user.username);
          } else {
            _followingAuthors.remove(user.username);
          }
        });
      }
    }
  }

  Future<void> _loadTopUsers() async {
    if (_loadingTop) {
      // no-op; this keeps top users lazy but avoids duplicate network calls.
    }
    try {
      final query = _controller.text.trim();
      final res = await http.get(
        searchUsersEndpoint(query),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode != 200) {
        if (mounted) setState(() => _loadingTop = false);
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _topUsers = users;
        _loadingTop = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingTop = false);
    }
  }

  Future<void> _loadCityPosts() async {
    try {
      final res = await http.get(
        postsEndpoint(city: widget.currentUser.city),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode != 200) {
        return;
      }
      final decoded = jsonDecode(res.body) as List<dynamic>;
      final posts = decoded
          .whereType<Map<String, dynamic>>()
          .map(FeedPost.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _cityPosts = posts;
      });
    } catch (_) {}
  }

  void _openProfileAndRemember(UserProfile user) {
    final query = _controller.text.trim();
    if (query.isNotEmpty) _addToHistory(query);
    widget.onOpenUserProfile(user.username);
  }

  void _onSearchSubmitted() {
    final query = _controller.text.trim();
    if (query.isNotEmpty) _addToHistory(query);
    _load(query);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final query = value.text.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchBar(isLight, query),
            Expanded(
              child: query.isEmpty
                  ? _buildExplore(isLight)
                  : _buildResults(isLight, query),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar(bool isLight, String query) {
    return Container(
      decoration: BoxDecoration(
        color: isLight ? const Color(0xfff3f4f6) : const Color(0xff121212),
        border: Border(
          bottom: BorderSide(
            color: isLight ? const Color(0xffe8eaed) : const Color(0xff2a2a2a),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        onSubmitted: (_) => _onSearchSubmitted(),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        style: TextStyle(
          color: isLight ? Colors.black : Colors.white,
          fontSize: 16,
        ),
        cursorColor: const Color(0xff1d9bf0),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
            size: 20,
          ),
          suffixIcon: query.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _controller.clear();
                    _onChanged('');
                    setState(() {});
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
                  ),
                )
              : null,
          hintText: 'Search',
          hintStyle: TextStyle(
            color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
            fontSize: 16,
          ),
          filled: true,
          fillColor: isLight ? const Color(0xfff4f6f8) : const Color(0xff161616),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isLight ? const Color(0xffe8eaed) : const Color(0xff2a2a2a),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xff1d9bf0), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildExplore(bool isLight) {
    if (_loadingSuggestions && _loadingTop) {
      return const Center(child: CircularProgressIndicator());
    }
    final trends = _popularPosts.take(5).toList();
    final suggestions = _suggestedUsers.take(5).toList();
    return ListView(
      children: [
        if (_recentQueries.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent searches',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearHistory,
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      color: isLight ? const Color(0xff6b7280) : const Color(0xff9ca3af),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _recentQueries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _buildRecentChip(_recentQueries[i], isLight),
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: isLight ? const Color(0xffe8eaed) : const Color(0xff1f1f1f),
          ),
        ],
        if (trends.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              'Trends for you',
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          ...trends.asMap().entries.map(
            (e) => _buildTrendingRow(e.value, isLight, rank: e.key + 1),
          ),
          Divider(
            height: 1,
            color: isLight ? const Color(0xffe8eaed) : const Color(0xff1f1f1f),
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
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
          SizedBox(
            height: 169,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _buildSuggestionCard(suggestions[i], isLight),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildRecentChip(String q, bool isLight) {
    return GestureDetector(
      onTap: () {
        _controller.text = q;
        _controller.selection = TextSelection.collapsed(offset: q.length);
        _onChanged(q);
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
        decoration: BoxDecoration(
          color: isLight ? const Color(0xfff4f6f8) : const Color(0xff1a1a1a),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLight ? const Color(0xffe8eaed) : const Color(0xff2a2a2a),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 13,
              color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
            ),
            const SizedBox(width: 5),
            Text(
              q,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() => _recentQueries.remove(q));
                http.delete(
                  searchHistoryItemEndpoint(q),
                  headers: authGetHeaders(widget.token),
                );
              },
              child: Icon(
                Icons.close_rounded,
                size: 12,
                color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
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
      onTap: () => _openProfileAndRemember(user),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: Text(
                  _followingAuthors.contains(user.username) ? 'Following' : widget.followerAuthors.contains(user.username) ? 'Follow Back' : 'Follow',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(bool isLight, String query) {
    return Column(
      children: [
        Container(
          color: isLight ? const Color(0xfff3f4f6) : const Color(0xff121212),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Container(
            decoration: BoxDecoration(
              color: isLight ? const Color(0xffe8eaed) : const Color(0xff1e1e1e),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLight ? const Color(0xffe8eaed) : const Color(0xff2a2a2a),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: _SearchSegment(label: 'Top', selected: _section == 0, onTap: () => setState(() => _section = 0))),
                Expanded(child: _SearchSegment(label: 'People', selected: _section == 1, onTap: () => setState(() => _section = 1))),
                Expanded(child: _SearchSegment(label: 'Posts', selected: _section == 2, onTap: () => setState(() => _section = 2))),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildResultsList(isLight, query),
        ),
      ],
    );
  }

  Widget _buildResultsList(bool isLight, String query) {
    if (_section == 2) {
      final posts = _searchPosts(query);
      if (posts.isEmpty) return _buildEmptyResult(query, isLight);
      return ListView.separated(
        itemCount: posts.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: isLight ? const Color(0xffe7e7e7) : const Color(0xff2f3336),
        ),
        itemBuilder: (_, i) => _buildTrendingRow(posts[i], isLight),
      );
    }
    final people = _users.isEmpty ? _topUsers : _users;
    if (people.isEmpty) return _buildEmptyResult(query, isLight);
    return ListView.separated(
      itemCount: people.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: isLight ? const Color(0xffe7e7e7) : const Color(0xff2f3336),
      ),
      itemBuilder: (_, i) => _buildPersonRow(people[i], isLight),
    );
  }

  Widget _buildEmptyResult(String query, bool isLight) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No results for\n"$query"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
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
        ),
      ),
    );
  }

  Widget _buildPersonRow(UserProfile user, bool isLight, {bool showBio = false}) {
    final bytes = decodeAvatarUrl(user.avatarUrl);
    final displayName = user.fullName.isNotEmpty ? user.fullName : user.username;
    return InkWell(
      onTap: () => _openProfileAndRemember(user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
                  if (showBio && user.bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => _openProfileAndRemember(user),
              style: OutlinedButton.styleFrom(
                foregroundColor: isLight ? Colors.black : Colors.white,
                side: BorderSide(
                  color: isLight ? Colors.black : Colors.white,
                  width: 1.5,
                ),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                widget.followerAuthors.contains(user.username) ? 'Follow Back' : 'Follow',
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingRow(FeedPost post, bool isLight, {int? rank}) {
    final text = post.text;
    final snippet = text.length > 70 ? '${text.substring(0, 70)}…' : text;
    final city = post.city.trim().isEmpty ? 'Trending' : post.city;
    return InkWell(
      onTap: () => widget.onOpenPost(post.author, post.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rank != null) ...[
              SizedBox(
                width: 30,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: isLight ? const Color(0xffb8c0cc) : const Color(0xff3a4a5a),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$city · Trending',
                    style: TextStyle(
                      color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snippet,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    post.likes > 0 ? '${post.likes} posts' : 'Trending',
                    style: TextStyle(
                      color: isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280),
                      fontSize: 12,
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

  List<FeedPost> get _popularPosts {
    final posts = _cityPosts.where((post) => post.likes >= 1).toList();
    posts.sort((a, b) => b.likes.compareTo(a.likes));
    return posts;
  }

  List<FeedPost> _searchPosts(String query) {
    final q = query.trim().toLowerCase();
    final posts = _cityPosts.where((post) {
      if (q.isEmpty) return true;
      return post.text.toLowerCase().contains(q) ||
          post.author.toLowerCase().contains(q) ||
          post.city.toLowerCase().contains(q);
    }).toList();
    posts.sort((a, b) => b.likes.compareTo(a.likes));
    return posts;
  }
}

class _SearchSegment extends StatelessWidget {
  const _SearchSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? (isLight ? Colors.white : const Color(0xff2a2a2a))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isLight ? 0.07 : 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? (isLight ? Colors.black : Colors.white)
                  : (isLight ? const Color(0xff9ca3af) : const Color(0xff6b7280)),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposeAction extends StatelessWidget {
  const _ComposeAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

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
            padding: const EdgeInsets.all(11),
            child: Icon(icon, color: isLight ? Colors.black : Colors.white, size: 19),
          ),
        ),
      ),
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
      // post notification — show actual thumbnail or video placeholder
      final imgUrl = item.imageUrl;
      final thumbBg = isLight ? const Color(0xffe8e8e8) : const Color(0xff2a2a2a);
      Widget thumb;
      if (imgUrl.startsWith('data:')) {
        final comma = imgUrl.indexOf(',');
        Uint8List? bytes;
        if (comma > -1) {
          try { bytes = base64Decode(imgUrl.substring(comma + 1)); } catch (_) {}
        }
        thumb = bytes != null
            ? Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover)
            : Container(width: 44, height: 44, color: thumbBg);
      } else if (imgUrl.isNotEmpty) {
        thumb = CachedNetworkImage(
          imageUrl: imgUrl,
          cacheManager: imageCacheManager,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          errorWidget: (_, _, _) => Container(width: 44, height: 44, color: thumbBg),
        );
      } else {
        thumb = Container(width: 44, height: 44, color: thumbBg);
      }
      trailing = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: thumb,
      );
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
              child: CircleAvatar(
                radius: 22,
                backgroundColor: isLight
                    ? const Color(0xffe0e0e0)
                    : const Color(0xff2a2a2a),
                child: Text(
                  initialFor(item.actor),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isLight ? const Color(0xff333333) : Colors.white,
                  ),
                ),
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
  });
  final FeedPost post;
  final AuthSession session;
  final VoidCallback onRefresh;
  final ValueChanged<String> onOpenUserProfile;
  final bool likingEnabled;

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
  FeedComment? _replyingTo;
  String _imageUrl = '';
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
      setState(() => _imageUrl = 'data:image/$mime;base64,${base64Encode(bytes)}');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _imageUrl.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await http.post(
        postCommentsEndpoint(widget.post.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({
          'text': text,
          if (_imageUrl.isNotEmpty) 'imageUrl': _imageUrl,
          if (_replyingTo != null) 'parentId': _replyingTo!.id,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final updated = FeedPost.fromJson(decoded);
        setState(() {
          _comments = updated.comments;
          _seedMaps(updated.comments);
          _replyingTo = null;
          _imageUrl = '';
        });
        _controller.clear();
        widget.post.comments
          ..clear()
          ..addAll(updated.comments);
        widget.onRefresh();
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

  Future<void> _toggleLike(FeedComment comment) async {
    final was = _liked[comment.id] ?? comment.liked;
    final next = (_likes[comment.id] ?? comment.likes) + (was ? -1 : 1);
    setState(() {
      _liked[comment.id] = !was;
      _likes[comment.id] = next;
    });
    try {
      await http.post(
        commentLikeEndpoint(comment.id),
        headers: authJsonHeaders(widget.session.token),
        body: jsonEncode({'liked': !was}),
      );
      comment.liked = !was;
      comment.likes = next;
    } catch (_) {
      setState(() {
        _liked[comment.id] = was;
        _likes[comment.id] = (_likes[comment.id] ?? comment.likes) + (was ? 1 : -1);
      });
    }
  }

  Widget _tile(BuildContext context, FeedComment c, bool isReply, bool isLight) {
    final bytes = decodeAvatarUrl(c.avatarUrl);
    final imgBytes = c.imageUrl.isNotEmpty ? decodeAvatarUrl(c.imageUrl) : null;
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
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${c.author} ',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: isReply ? 13.5 : 15,
                          height: 1.5,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => widget.onOpenUserProfile(c.author),
                      ),
                      if (c.text.isNotEmpty)
                        TextSpan(
                          text: c.text,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w400,
                            fontSize: isReply ? 13.5 : 15,
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (imgBytes != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(imgBytes, width: double.infinity, fit: BoxFit.cover),
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
                            color: const Color(0xfff66c6c),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final userBytes = decodeAvatarUrl(widget.session.user.avatarUrl);
    final previewBytes = _imageUrl.isNotEmpty ? decodeAvatarUrl(_imageUrl) : null;

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
                          'No comments yet.\nBe the first!',
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
                    const SizedBox(width: 4),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) {
                          final canSend =
                              value.text.trim().isNotEmpty || _imageUrl.isNotEmpty;
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
                                      : IconButton(
                                          onPressed: _send,
                                          icon: const Icon(
                                            Icons.send_rounded,
                                            color: Color(0xff4f8cff),
                                            size: 20,
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
