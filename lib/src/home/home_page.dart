import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/icons.dart';
import '../core/models.dart';
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
  final TextEditingController _compose = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<FeedPost> _posts = [];
  final List<NotificationItem> _notificationsList = [];
  final Set<String> _followingAuthors = {};
  final List<UserProfile> _followingProfiles = [];
  int _nav = 0;
  int _selectedTab = 0;
  final Set<int> _visitedTabs = <int>{0};
  bool _loading = true;
  String? _activeCity;
  String _composeImageUrl = '';
  bool _showInlineProfile = false;
  String _inlineProfileUsername = '';
  int? _inlinePostId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadNotifications(silent: true);
  }

  @override
  void dispose() {
    _compose.dispose();
    super.dispose();
  }

  Uint8List? _dataUrlBytes(String value) {
    if (!value.startsWith('data:')) return null;
    final comma = value.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Widget _mediaPreview(String value, {BoxFit fit = BoxFit.cover}) {
    final bytes = _dataUrlBytes(value);
    if (bytes != null) {
      return Image.memory(bytes, fit: fit);
    }
    if (value.isNotEmpty) {
      return Image.network(value, fit: fit);
    }
    return const SizedBox.shrink();
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
      await _loadFollowingAuthors();
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
              isRead: true,
              created: item.created,
            );
          }
        }
      }
    });
  }

  Future<void> _createPost() async {
    final text = _compose.text.trim();
    if (text.isEmpty) return;
    final res = await http.post(
      postsEndpoint(),
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({
        'text': text,
        if (_composeImageUrl.isNotEmpty) 'imageUrl': _composeImageUrl,
      }),
    );
    if (res.statusCode == 201) {
      _compose.clear();
      _composeImageUrl = '';
      await _load();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickComposeImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _composeImageUrl =
          'data:image/${picked.name.toLowerCase().endsWith(".png") ? "png" : "jpeg"};base64,${base64Encode(bytes)}';
    });
  }

  void _clearComposeImage() {
    setState(() => _composeImageUrl = '');
  }

  Future<bool> _likePost(FeedPost post) async {
    final res = await http.post(
      postLikeEndpoint(post.id),
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({'liked': post.liked}),
    );
    if (res.statusCode == 401) {
      await widget.onLogout();
      return false;
    }
    return res.statusCode == 200;
  }

  Future<bool> _savePost(FeedPost post) async {
    final res = await http.post(
      postSaveEndpoint(post.id),
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({'saved': post.saved}),
    );
    if (res.statusCode == 401) {
      await widget.onLogout();
      return false;
    }
    return res.statusCode == 200;
  }

  Future<void> _follow(String username) async {
    setState(() => _followingAuthors.add(username));
    final res = await http.post(
      followEndpoint(username),
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({'follow': true}),
    );
    if (res.statusCode == 401) {
      setState(() => _followingAuthors.remove(username));
      await widget.onLogout();
      return;
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      if (mounted) setState(() => _followingAuthors.remove(username));
    } else if (mounted) {
      await _loadFollowingAuthors();
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

  void _openProfile(String username) {
    setState(() {
      _inlineProfileUsername = username;
      _inlinePostId = null;
      _showInlineProfile = true;
      _nav = 0;
    });
  }

  void _openProfileAtPost(String username, int postId) {
    setState(() {
      _inlineProfileUsername = username;
      _inlinePostId = postId;
      _showInlineProfile = true;
      _nav = 0;
    });
  }

  Future<void> _openCityFeed(String city) async {
    setState(() {
      _activeCity = city.trim();
      _nav = 0;
      _loading = true;
    });
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

  Future<void> _openNotificationTarget(NotificationItem item) async {
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
    _openProfile(item.actor);
  }

  void _openNotifications() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: FutureBuilder<List<NotificationItem>>(
              future: _fetchNotifications(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final items = snapshot.data ?? const [];
                final unread = items.where((item) => !item.isRead).toList();
                final today = items
                    .where(
                      (item) => _notificationBucket(item.created) == 'Today',
                    )
                    .toList();
                final thisWeek = items
                    .where(
                      (item) =>
                          _notificationBucket(item.created) == 'This week',
                    )
                    .toList();
                final earlier = items
                    .where(
                      (item) => _notificationBucket(item.created) == 'Earlier',
                    )
                    .toList();

                return StatefulBuilder(
                  builder: (context, setSheetState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Notifications',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                            const Spacer(),
                            if (unread.isNotEmpty)
                              TextButton.icon(
                                onPressed: () async {
                                  await _markNotificationsRead(unread);
                                  if (!mounted) return;
                                  setSheetState(() {});
                                },
                                icon: Icon(
                                  Icons.done_all,
                                  size: 18,
                                  color: isLight ? Colors.black : const Color(0xffededed),
                                ),
                                label: const Text('Mark all read'),
                                style: TextButton.styleFrom(
                                  foregroundColor: isLight ? Colors.black : const Color(0xffededed),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Activity',
                          style: TextStyle(
                            color: isLight ? const Color(0xff616161) : const Color(0xffb7b7b7),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (items.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'No notifications yet.',
                                style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xffb7b7b7)),
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                _NotificationGroup(
                                  title: 'Today',
                                  items: today,
                                  onTapItem: (item) async {
                                    Navigator.of(sheetContext).pop();
                                    await _markNotificationsRead([item]);
                                    if (!mounted) return;
                                    await _openNotificationTarget(item);
                                  },
                                ),
                                _NotificationGroup(
                                  title: 'This week',
                                  items: thisWeek,
                                  onTapItem: (item) async {
                                    Navigator.of(sheetContext).pop();
                                    await _markNotificationsRead([item]);
                                    if (!mounted) return;
                                    await _openNotificationTarget(item);
                                  },
                                ),
                                _NotificationGroup(
                                  title: 'Earlier',
                                  items: earlier,
                                  onTapItem: (item) async {
                                    Navigator.of(sheetContext).pop();
                                    await _markNotificationsRead([item]);
                                    if (!mounted) return;
                                    await _openNotificationTarget(item);
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _notificationBucket(DateTime created) {
    final diff = DateTime.now().difference(created);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays <= 7) return 'This week';
    return 'Earlier';
  }

  void _openComments(FeedPost post) {
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
      ),
    );
  }

  void _openCreatePost() {
    _compose.clear();
    _composeImageUrl = '';
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: isLight ? const Color(0xfff3f4f6) : const Color(0xff111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xffa0a0a0),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        Text(
                          'New post',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                        const Spacer(),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _compose,
                          builder: (context, value, _) {
                            final canPost = value.text.trim().isNotEmpty;
                            return FilledButton(
                              onPressed: canPost ? _createPost : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: isLight ? Colors.black : Colors.white,
                                foregroundColor: isLight ? Colors.white : Colors.black,
                                disabledBackgroundColor:
                                    isLight ? const Color(0xffd9dee6) : const Color(0xff2f2f2f),
                                disabledForegroundColor:
                                    isLight ? const Color(0xff8a8a8a) : const Color(0xff8a8a8a),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: const Text('Post'),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                          child: Text(
                            initialFor(widget.session.user.username),
                            style: TextStyle(color: isLight ? Colors.black : Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _compose,
                            minLines: 5,
                            maxLines: 10,
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 17,
                              height: 1.4,
                            ),
                            cursorColor: isLight ? Colors.black : Colors.white,
                            decoration: InputDecoration(
                              hintText: 'What’s happening?',
                              hintStyle: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xff8f8f8f)),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_composeImageUrl.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 1.15,
                              child: _mediaPreview(
                                _composeImageUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: GestureDetector(
                                onTap: _clearComposeImage,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isLight ? Colors.black.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.65),
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: isLight ? Colors.black : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Divider(height: 1, color: isLight ? const Color(0xffd9dee6) : const Color(0xff242424)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _ComposeAction(
                          icon: Icons.image_outlined,
                          onTap: () async {
                            await _pickComposeImage();
                            setSheetState(() {});
                          },
                        ),
                        _ComposeAction(
                          icon: Icons.gif_box_outlined,
                          onTap: () {},
                        ),
                        _ComposeAction(
                          icon: Icons.poll_outlined,
                          onTap: () {},
                        ),
                        const Spacer(),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _compose,
                          builder: (context, value, _) {
                            final count = value.text.length;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: count > 240
                                    ? const Color(0xff301818)
                                    : (isLight ? const Color(0xffeef1f5) : const Color(0xff1a1a1a)),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: count > 240
                                      ? const Color(0xff7a2f2f)
                                      : (isLight ? const Color(0xffd9dee6) : const Color(0xff2c2c2c)),
                                ),
                              ),
                              child: Text(
                                '$count/280',
                                style: TextStyle(
                                  color: count > 240
                                      ? const Color(0xffff9a9a)
                                      : (isLight ? const Color(0xff616161) : const Color(0xff9a9a9a)),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openSheet({required String title, required Widget child}) {
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
    );
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
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              notifications: _notificationsList
                  .where((item) => !item.isRead)
                  .length,
              userAvatarUrl: widget.session.user.avatarUrl,
              onProfileTap: () => _openProfile(widget.session.user.username),
              onNotificationsTap: _openNotifications,
              onMessagesTap: () => Navigator.of(context).push(
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
                  ),
                ),
              ),
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
                            key: PageStorageKey<String>('feed_$_selectedTab'),
                            slivers: [
                              const SliverToBoxAdapter(child: SizedBox.shrink()),
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: _TabsHeader(
                                  selectedTab: _selectedTab,
                                  onTabChanged: (value) {
                                    setState(() => _selectedTab = value);
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
                                    return _FeedPostCard(
                                      key: ValueKey(post.id),
                                      post: post,
                                      session: widget.session,
                                      onLike: () => _likePost(post),
                                      onSave: () => _savePost(post),
                                      onShare: () => showShareSheet(
                                        context: context,
                                        post: post,
                                        token: widget.session.token,
                                        currentUser: widget.session.user,
                                        onLogout: widget.onLogout,
                                      ),
                                      onMore: () => _openSheet(
                                        title: post.author,
                                        child: Column(
                                          children: [
                                            if (post.author == widget.session.user.username)
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
                                            const ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(
                                                Icons.visibility_off_outlined,
                                              ),
                                              title: Text('Hide post'),
                                            ),
                                            const ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(Icons.flag_outlined),
                                              title: Text('Report post'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      onProfileTap: () => _openProfile(post.author),
                                      onFollow: post.author != widget.session.user.username
                                          ? () => _follow(post.author)
                                          : null,
                                      isFollowing: _followingAuthors.contains(post.author),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                        // 1: Search — mounted lazily on first visit
                        _visitedTabs.contains(1)
                            ? _SearchView(
                                token: widget.session.token,
                                currentUser: widget.session.user,
                                onOpenUserProfile: _openProfile,
                                onOpenPost: _openProfileAtPost,
                              )
                            : const SizedBox.shrink(),
                        // 2: Create (intercepted by bottom nav, never shown)
                        const SizedBox.shrink(),
                        // 3: Map — mounted lazily on first visit
                        _visitedTabs.contains(3)
                            ? CityMapView(
                                token: widget.session.token,
                                onOpenUserProfile: _openProfile,
                                onCitySelected: _openCityFeed,
                              )
                            : const SizedBox.shrink(),
                        // 4: Events — mounted lazily on first visit
                        _visitedTabs.contains(4)
                            ? EventsPage(
                                token: widget.session.token,
                                city: widget.session.user.city,
                                currentUser: widget.session.user,
                                onOpenUserProfile: _openProfile,
                              )
                            : const SizedBox.shrink(),
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
                        onOpenUserProfile: _openProfile,
                        onOpenProfileAtPost: _openProfileAtPost,
                        onLogout: widget.onLogout,
                        onSessionUpdated: widget.onSessionChanged,
                        onPostTap: _openComments,
                        initialPostId: _inlinePostId,
                        themeMode: widget.themeMode,
                        onThemeModeChanged: widget.onThemeModeChanged,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BottomNavigationBar(
            currentIndex: _nav,
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            selectedItemColor: isLight ? Colors.black : Colors.white,
            unselectedItemColor:
                isLight ? const Color(0xff6d6d6d) : const Color(0xff8c8c8c),
            elevation: 0,
            backgroundColor: isLight ? Colors.white : const Color(0xff151515),
            iconSize: 26,
            selectedFontSize: 0,
            unselectedFontSize: 0,
            onTap: (i) {
              if (i == 2) {
                _openCreatePost();
                return;
              }
              if (i == 0) {
                _goHome();
                return;
              }
              setState(() {
                _nav = i;
                _visitedTabs.add(i);
                _showInlineProfile = false;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search_outlined),
                activeIcon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.add_circle_outline_rounded),
                activeIcon: Icon(Icons.add_circle_rounded),
                label: 'Create',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map_rounded),
                label: 'Map',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.event_note_outlined),
                activeIcon: Icon(Icons.event_note_rounded),
                label: 'Events',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.notifications,
    required this.userAvatarUrl,
    required this.onProfileTap,
    required this.onNotificationsTap,
    required this.onMessagesTap,
  });
  final int notifications;
  final String userAvatarUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onMessagesTap;
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
            GestureDetector(
              onTap: onProfileTap,
              child: _TopBarAvatar(url: userAvatarUrl),
            ),
            const SizedBox(width: 8),
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
                  child: _SharePlaneIcon(
                    color: isLight ? Colors.black : Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader({required this.selectedTab, required this.onTabChanged});
  final int selectedTab;
  final ValueChanged<int> onTabChanged;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _TabsHeaderContent(selectedTab: selectedTab, onTabChanged: onTabChanged);
  }
  @override
  double get maxExtent => 52;
  @override
  double get minExtent => 52;
  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.selectedTab != selectedTab;
}

class _TabsHeaderContent extends StatelessWidget {
  const _TabsHeaderContent({required this.selectedTab, required this.onTabChanged});
  final int selectedTab;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    const indicatorW = 40.0;
    final tabW = MediaQuery.sizeOf(context).width / 2;
    final targetLeft = selectedTab * tabW + (tabW - indicatorW) / 2;
    return Container(
      color: isLight ? const Color(0xfff3f4f6) : const Color(0xff121212),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onTabChanged(0),
                  child: SizedBox(
                    height: 52,
                    child: Center(
                      child: Text(
                        'For you',
                        style: TextStyle(
                          color: selectedTab == 0
                              ? (isLight ? Colors.black : Colors.white)
                              : (isLight ? const Color(0xff616161) : Colors.white38),
                          fontSize: 17,
                          fontWeight: selectedTab == 0 ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => onTabChanged(1),
                  child: SizedBox(
                    height: 52,
                    child: Center(
                      child: Text(
                        'Following',
                        style: TextStyle(
                          color: selectedTab == 1
                              ? (isLight ? Colors.black : Colors.white)
                              : (isLight ? const Color(0xff616161) : Colors.white38),
                          fontSize: 17,
                          fontWeight: selectedTab == 1 ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: targetLeft),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            builder: (context, left, _) => Positioned(
              left: left,
              bottom: 0,
              child: Container(
                width: indicatorW,
                height: 2,
                decoration: BoxDecoration(
                  color: isLight ? Colors.black : Colors.white,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedPostCard extends StatefulWidget {
  const _FeedPostCard({
    super.key,
    required this.post,
    required this.session,
    required this.onLike,
    required this.onSave,
    required this.onShare,
    required this.onMore,
    required this.onProfileTap,
    this.onFollow,
    this.isFollowing = false,
  });

  final FeedPost post;
  final AuthSession session;
  final Future<bool> Function() onLike;
  final Future<bool> Function() onSave;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final VoidCallback onProfileTap;
  final VoidCallback? onFollow;
  final bool isFollowing;

  @override
  State<_FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<_FeedPostCard> {
  late bool _liked;
  late bool _saved;
  late int _likes;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _saved = widget.post.saved;
    _likes = widget.post.likes;
  }

  @override
  void didUpdateWidget(_FeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync state when the feed reloads with fresh post objects from the server.
    if (!identical(oldWidget.post, widget.post)) {
      _liked = widget.post.liked;
      _saved = widget.post.saved;
      _likes = widget.post.likes;
    }
  }

  Future<void> _handleLike() async {
    final wasLiked = _liked;
    final wasLikes = _likes;
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
      widget.post.liked = _liked;
      widget.post.likes = _likes;
    });
    final ok = await widget.onLike();
    if (!ok && mounted) {
      setState(() {
        _liked = wasLiked;
        _likes = wasLikes;
        widget.post.liked = wasLiked;
        widget.post.likes = wasLikes;
      });
    }
  }

  Future<void> _handleSave() async {
    final wasSaved = _saved;
    setState(() {
      _saved = !_saved;
      widget.post.saved = _saved;
    });
    final ok = await widget.onSave();
    if (!ok && mounted) {
      setState(() {
        _saved = wasSaved;
        widget.post.saved = wasSaved;
      });
    }
  }

  void _openComments() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      builder: (_) => _CommentSheet(
        post: widget.post,
        session: widget.session,
        onRefresh: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xff131313),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isLight ? const Color(0xffd9dee6) : const Color(0xff242424)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
              child: Row(
                children: [
                  InkWell(
                    onTap: widget.onProfileTap,
                    child: _PostAvatar(
                      username: widget.post.author,
                      avatarUrl: widget.post.avatarUrl,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: widget.onProfileTap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.post.author,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),
                          Text(
                            _postAge(widget.post.minutesAgo),
                            style: TextStyle(
                              fontSize: 12,
                              color: isLight ? const Color(0xff616161) : const Color(0xffb3b3b3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.onFollow != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: widget.isFollowing ? null : widget.onFollow,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: widget.isFollowing
                              ? (isLight ? const Color(0xffb0b0b0) : const Color(0xff555555))
                              : (isLight ? Colors.black : Colors.white),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        widget.isFollowing ? 'Following' : 'Follow',
                        style: TextStyle(
                          color: widget.isFollowing
                              ? (isLight ? const Color(0xffb0b0b0) : const Color(0xff555555))
                              : (isLight ? Colors.black : Colors.white),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  IconButton(
                    onPressed: widget.onMore,
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: isLight ? Colors.black : Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                widget.post.text,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.45,
                  color: isLight ? Colors.black : Colors.white,
                ),
              ),
            ),
            if (widget.post.imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 1.08,
                    child: _FeedMedia(url: widget.post.imageUrl),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _handleLike,
                    icon: Icon(
                      _liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: _liked ? Colors.red : (isLight ? Colors.black : Colors.white),
                      size: 28,
                    ),
                  ),
                  IconButton(
                    onPressed: _openComments,
                    icon: CommentBubbleIcon(
                      color: isLight ? Colors.black : Colors.white,
                      size: 25,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onShare,
                    icon: _SharePlaneIcon(
                      color: isLight ? Colors.black : Colors.white,
                      size: 27,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _handleSave,
                    icon: Icon(
                      _saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: _saved
                          ? const Color(0xffFFB800)
                          : (isLight ? Colors.black : Colors.white),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text(
                    '$_likes likes',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _openComments,
                    child: Text(
                      widget.post.comments.isEmpty
                          ? 'Add a comment...'
                          : 'View ${widget.post.comments.length} comments',
                      style: const TextStyle(
                        color: Color(0xffb3b3b3),
                        fontSize: 13,
                      ),
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

class _TopBarAvatar extends StatelessWidget {
  const _TopBarAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    Uint8List? bytes;
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma > -1) {
        try {
          bytes = base64Decode(url.substring(comma + 1));
        } catch (_) {}
      }
    }
    return CircleAvatar(
      radius: 15,
      backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
      foregroundImage: bytes != null ? MemoryImage(bytes) : null,
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView({
    required this.token,
    required this.currentUser,
    required this.onOpenUserProfile,
    required this.onOpenPost,
  });

  final String token;
  final UserProfile currentUser;
  final ValueChanged<String> onOpenUserProfile;
  final void Function(String username, int postId) onOpenPost;

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

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    _loadTopUsers();
    _loadCityPosts();
    _load('');
    _loadRecentQueries();
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
      color: isLight ? Colors.white : const Color(0xff000000),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        onSubmitted: (_) => _onSearchSubmitted(),
        style: TextStyle(
          color: isLight ? Colors.black : Colors.white,
          fontSize: 16,
        ),
        cursorColor: const Color(0xff1d9bf0),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
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
                    color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                  ),
                )
              : null,
          hintText: 'Search',
          hintStyle: TextStyle(
            color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
            fontSize: 16,
          ),
          filled: true,
          fillColor: isLight ? const Color(0xffeff3f4) : const Color(0xff202327),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent searches',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearHistory,
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._recentQueries.map(
            (q) => InkWell(
              onTap: () {
                _controller.text = q;
                _controller.selection = TextSelection.collapsed(offset: q.length);
                _onChanged(q);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                      size: 20,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        q,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
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
                        size: 16,
                        color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: isLight ? const Color(0xffe7e7e7) : const Color(0xff2f3336),
          ),
        ],
        if (trends.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              'Trends for you',
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ...trends.map((post) => _buildTrendingRow(post, isLight)),
          Divider(
            height: 1,
            color: isLight ? const Color(0xffe7e7e7) : const Color(0xff2f3336),
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              'Who to follow',
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ...suggestions.map((user) => _buildPersonRow(user, isLight, showBio: true)),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildResults(bool isLight, String query) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xff000000),
            border: Border(
              bottom: BorderSide(
                color: isLight ? const Color(0xffe7e7e7) : const Color(0xff2f3336),
              ),
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
    final bytes = _decodeDataUrl(user.avatarUrl);
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
                'Follow',
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

  Widget _buildTrendingRow(FeedPost post, bool isLight) {
    final text = post.text;
    final snippet = text.length > 70 ? '${text.substring(0, 70)}…' : text;
    final city = post.city.trim().isEmpty ? 'Trending' : post.city;
    return InkWell(
      onTap: () => widget.onOpenPost(post.author, post.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$city · Trending',
                    style: TextStyle(
                      color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                      fontSize: 13,
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
                      color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.more_horiz_rounded,
              color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
              size: 20,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? (isLight ? Colors.black : Colors.white)
                    : (isLight ? const Color(0xff536471) : const Color(0xff71767b)),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                fontSize: 15,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 3,
            width: selected ? 32.0 : 0,
            decoration: BoxDecoration(
              color: isLight ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedMedia extends StatelessWidget {
  const _FeedMedia({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma > -1) {
        try {
          return Image.memory(
            base64Decode(url.substring(comma + 1)),
            fit: BoxFit.cover,
          );
        } catch (_) {}
      }
    }
    return Image.network(url, fit: BoxFit.cover);
  }
}

class _PostAvatar extends StatelessWidget {
  const _PostAvatar({
    required this.username,
    required this.avatarUrl,
  });

  final String username;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bytes = _decodeDataUrl(avatarUrl);
    return CircleAvatar(
      backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
      foregroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Text(
              initialFor(username),
              style: TextStyle(
                color: isLight ? const Color(0xff444444) : Colors.white,
              ),
            )
          : null,
    );
  }
}

final _dataUrlCache = <String, Uint8List?>{};

Uint8List? _decodeDataUrl(String value) {
  if (!value.startsWith('data:')) return null;
  if (_dataUrlCache.containsKey(value)) return _dataUrlCache[value];
  final comma = value.indexOf(',');
  Uint8List? result;
  if (comma >= 0) {
    try {
      result = base64Decode(value.substring(comma + 1));
    } catch (_) {}
  }
  _dataUrlCache[value] = result;
  return result;
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

class _NotificationGroup extends StatelessWidget {
  const _NotificationGroup({
    required this.title,
    required this.items,
    required this.onTapItem,
  });

  final String title;
  final List<NotificationItem> items;
  final Future<void> Function(NotificationItem item) onTapItem;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? Colors.black : Colors.white;
    final secondaryColor =
        isLight ? const Color(0xff555555) : const Color(0xffb7b7b7);
    final timeColor =
        isLight ? const Color(0xff888888) : const Color(0xff8f8f8f);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title,
              style: TextStyle(
                color: secondaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onTapItem(item),
                child: Container(
                  decoration: BoxDecoration(
                    color: isLight
                        ? (item.isRead
                            ? Colors.white
                            : const Color(0xfff0f4ff))
                        : (item.isRead
                            ? const Color(0xff161616)
                            : const Color(0xff1c1c1c)),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isLight
                          ? (item.isRead
                              ? const Color(0xffe0e3e8)
                              : const Color(0xffbdd0ff))
                          : (item.isRead
                              ? const Color(0xff262626)
                              : const Color(0xff3a3a3a)),
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: isLight
                            ? const Color(0xffe6e9ef)
                            : const Color(0xff2a2a2a),
                        child: Text(
                          initialFor(item.actor),
                          style: TextStyle(
                            color: isLight
                                ? const Color(0xff444444)
                                : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                                children: [
                                  TextSpan(
                                    text: item.actor,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(text: ' ${_actionLabel(item.verb)}'),
                                ],
                              ),
                            ),
                            if (item.targetText.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.targetText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              _timeAgo(item.created),
                              style: TextStyle(
                                color: timeColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!item.isRead)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isLight
                                  ? const Color(0xff1479ff)
                                  : Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
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
  });
  final FeedPost post;
  final AuthSession session;
  final VoidCallback onRefresh;

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
    final bytes = _decodeDataUrl(c.avatarUrl);
    final imgBytes = c.imageUrl.isNotEmpty ? _decodeDataUrl(c.imageUrl) : null;
    final isLiked = _liked[c.id] ?? c.liked;
    final likeCount = _likes[c.id] ?? c.likes;
    DateTime? created;
    try { created = DateTime.parse(c.createdAt); } catch (_) {}
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 52 : 16, 10, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
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
            onTap: () => _toggleLike(c),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 18,
                  color: isLiked
                      ? const Color(0xfff66c6c)
                      : (isLight ? const Color(0xffa0a0a0) : const Color(0xff6a6a6a)),
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
    final userBytes = _decodeDataUrl(widget.session.user.avatarUrl);
    final previewBytes = _imageUrl.isNotEmpty ? _decodeDataUrl(_imageUrl) : null;

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

String _postAge(int minutesAgo) {
  if (minutesAgo < 1) return 'just now';
  if (minutesAgo < 60) return '${minutesAgo}m';
  if (minutesAgo < 1440) return '${minutesAgo ~/ 60}h';
  if (minutesAgo < 10080) return '${minutesAgo ~/ 1440}d';
  if (minutesAgo < 43200) return '${minutesAgo ~/ 10080}w';
  if (minutesAgo < 525600) return '${minutesAgo ~/ 43200}mo';
  return '${minutesAgo ~/ 525600}y';
}

String _timeAgo(DateTime created) {
  final diff = DateTime.now().difference(created);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// Instagram-style paper-plane share icon drawn with CustomPaint.
class _SharePlaneIcon extends StatelessWidget {
  const _SharePlaneIcon({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SharePlanePainter(color)),
    );
  }
}

class _SharePlanePainter extends CustomPainter {
  const _SharePlanePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = size.width * 0.083;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final pad = sw / 2 + 0.5;

    // Scale the classic paper-plane shape from a 24×24 design grid.
    final s = (w - 2 * pad) / 24.0;
    Offset p(double x, double y) => Offset(pad + x * s, pad + y * s);

    // Key points (matching the well-known Heroicons paper-airplane icon).
    final rearMid   = p(6,    12);     // rear pinch point, vertical centre
    final upperRear = p(3.27,  3.13); // top of the rear
    final nose      = p(21.5, 12);    // nose — right, vertical centre
    final lowerRear = p(3.27, 20.88); // bottom of the rear
    final foldEnd   = p(13.5, 12);    // inner fold line end, same height as nose

    // Outer body: rear-mid → upper-rear → nose → lower-rear → close back to rear-mid.
    canvas.drawPath(
      Path()
        ..moveTo(rearMid.dx, rearMid.dy)
        ..lineTo(upperRear.dx, upperRear.dy)
        ..lineTo(nose.dx, nose.dy)
        ..lineTo(lowerRear.dx, lowerRear.dy)
        ..close(),
      paint,
    );

    // Single horizontal fold line across the body — what makes it a paper plane.
    canvas.drawLine(rearMid, foldEnd, paint);
  }

  @override
  bool shouldRepaint(_SharePlanePainter old) => old.color != color;
}
