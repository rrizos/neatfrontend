import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/models.dart';
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
  bool _loading = true;
  String? _activeCity;
  String _composeImageUrl = '';
  bool _showInlineProfile = false;
  String _inlineProfileUsername = '';

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

  Future<void> _like(FeedPost post) async {
    final previousLiked = post.liked;
    final previousLikes = post.likes;
    setState(() {
      post.liked = !post.liked;
      post.likes += post.liked ? 1 : -1;
    });
    final res = await http.post(
      postLikeEndpoint(post.id),
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({'liked': post.liked}),
    );
    if (res.statusCode == 401) {
      await widget.onLogout();
      return;
    }
    if (res.statusCode != 200 && mounted) {
      setState(() {
        post.liked = previousLiked;
        post.likes = previousLikes;
      });
    }
  }

  Future<void> _comment(FeedPost post, String text) async {
    await http.post(
      postCommentsEndpoint(post.id),
      headers: authJsonHeaders(widget.session.token),
      body: jsonEncode({'text': text}),
    );
    await _load();
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
      });
      return;
    }
    setState(() {
      _activeCity = null;
      _nav = 0;
      _showInlineProfile = false;
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
    final isLight = widget.themeMode == ThemeMode.light;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: widget.themeMode == ThemeMode.light
          ? Colors.white
          : const Color(0xff141414),
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
    final controller = TextEditingController();
    final isLight = widget.themeMode == ThemeMode.light;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
              left: 16,
              right: 16,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.7,
              child: Column(
                children: [
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: post.comments.isEmpty
                        ? Center(
                            child: Text(
                              'No comments yet.',
                              style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xffb7b7b7)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: post.comments.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final comment = post.comments[index];
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _PostAvatar(
                                    username: comment.author,
                                    avatarUrl: comment.avatarUrl,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          comment.author,
                                          style: TextStyle(
                                            color: isLight ? Colors.black : Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          comment.text,
                                          style: TextStyle(
                                            color: isLight ? Colors.black : Colors.white,
                                            fontSize: 14,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                          ),
                          cursorColor: isLight ? Colors.black : Colors.white,
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: TextStyle(
                              color: isLight ? const Color(0xff616161) : const Color(0xff9a9a9a),
                            ),
                            filled: true,
                            fillColor: isLight
                                ? const Color(0xffeef1f5)
                                : const Color(0xff1e1e1e),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isLight
                                    ? const Color(0xffd9dee6)
                                    : const Color(0xff2a2a2a),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isLight
                                    ? const Color(0xffd9dee6)
                                    : const Color(0xff2a2a2a),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) return;
                          await _comment(post, text);
                          if (mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Post'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
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

    final bodyTheme = widget.themeMode == ThemeMode.light;

    return Scaffold(
      backgroundColor: bodyTheme ? const Color(0xfff3f4f6) : const Color(0xff121212),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              notifications: _notificationsList
                  .where((item) => !item.isRead)
                  .length,
              userAvatarUrl: widget.session.user.avatarUrl,
              themeMode: widget.themeMode,
              onProfileTap: () => _openProfile(widget.session.user.username),
              onNotificationsTap: _openNotifications,
              onMessagesTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MessagesPage(
                    token: widget.session.token,
                    currentUsername: widget.session.user.username,
                    suggestedUsers: _followingProfiles,
                    onLogout: widget.onLogout,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xff232323)),
            Expanded(
              child: _showInlineProfile
                  ? ProfilePage(
                      username: _inlineProfileUsername,
                      currentUser: widget.session.user,
                      token: widget.session.token,
                      posts: _posts,
                      onOpenUserProfile: _openProfile,
                      onLogout: widget.onLogout,
                      onSessionUpdated: widget.onSessionChanged,
                      onPostTap: _openComments,
                      themeMode: widget.themeMode,
                      onThemeModeChanged: widget.onThemeModeChanged,
                    )
                  : _nav == 0
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
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
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(
                                  'No posts yet.',
                                  style: TextStyle(color: Color(0xffe8e8e8)),
                                ),
                              ),
                            )
                          else
                            SliverList.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final post = filtered[index];
                                return _FeedPostCard(
                                  post: post,
                                  onLike: () => _like(post),
                                  onComment: () => _openComments(post),
                                  onShare: () => _openSheet(
                                    title: 'Share',
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: const [
                                        _ShareChip(
                                          icon: Icons.send,
                                          label: 'DM',
                                        ),
                                        _ShareChip(
                                          icon: Icons.link,
                                          label: 'Copy link',
                                        ),
                                        _ShareChip(
                                          icon: Icons.group_add,
                                          label: 'Group',
                                        ),
                                      ],
                                    ),
                                  ),
                                  onSave: () {},
                                  onMore: () => _openSheet(
                                    title: post.author,
                                    child: Column(
                                      children: [
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: const Icon(
                                            Icons.person_add_alt_1,
                                          ),
                                          title: Text('Follow ${post.author}'),
                                          onTap: () =>
                                              _openProfile(post.author),
                                        ),
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
                                );
                              },
                            ),
                        ],
                      ),
                    )
                  : _nav == 1
                  ? _SearchView(
                      token: widget.session.token,
                      currentUser: widget.session.user,
                      onOpenUserProfile: _openProfile,
                    )
                  : _nav == 2
                  ? const _ActivityView()
                  : _nav == 3
                  ? CityMapView(
                      token: widget.session.token,
                      onOpenUserProfile: _openProfile,
                      onCitySelected: _openCityFeed,
                    )
                  : EventsPage(
                      token: widget.session.token,
                      city: widget.session.user.city,
                      currentUser: widget.session.user,
                      onOpenUserProfile: _openProfile,
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
            selectedItemColor:
                widget.themeMode == ThemeMode.light ? Colors.black : Colors.white,
            unselectedItemColor: widget.themeMode == ThemeMode.light
                ? const Color(0xff6d6d6d)
                : const Color(0xff8c8c8c),
            elevation: 0,
            backgroundColor: widget.themeMode == ThemeMode.light
                ? Colors.white
                : const Color(0xff151515),
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
              setState(() => _nav = i);
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
    required this.themeMode,
    required this.onProfileTap,
    required this.onNotificationsTap,
    required this.onMessagesTap,
  });
  final int notifications;
  final String userAvatarUrl;
  final ThemeMode themeMode;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onMessagesTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            _LogoMark(themeMode: themeMode),
            const Spacer(),
            _TopBarPill(
              onTap: onProfileTap,
              child: _TopBarAvatar(url: userAvatarUrl),
            ),
            const SizedBox(width: 8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                _TopBarPill(
                  onTap: onNotificationsTap,
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: themeMode == ThemeMode.light ? Colors.black : Colors.white,
                    size: 22,
                  ),
                ),
                if (notifications > 0)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xfff66c6c),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xff0f0f10),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        notifications > 9 ? '9+' : '$notifications',
                        style: TextStyle(
                          color: themeMode == ThemeMode.light ? Colors.white : Colors.black,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            _TopBarPill(
              onTap: onMessagesTap,
              child: Icon(
                Icons.send_outlined,
                color: themeMode == ThemeMode.light ? Colors.black : Colors.white,
                size: 21,
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
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      color: isLight ? const Color(0xfff3f4f6) : const Color(0xff121212),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onTabChanged(0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'For you',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 17,
                      fontWeight: selectedTab == 0 ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 2,
                    width: selectedTab == 0 ? 72 : 0,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => onTabChanged(1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Following',
                    style: TextStyle(
                      color: isLight ? const Color(0xff616161) : Colors.white70,
                      fontSize: 17,
                      fontWeight: selectedTab == 1 ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 2,
                    width: selectedTab == 1 ? 84 : 0,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 52;
  @override
  double get minExtent => 52;
  @override
  bool shouldRebuild(covariant _TabsHeader oldDelegate) =>
      oldDelegate.selectedTab != selectedTab;
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onMore,
    required this.onProfileTap,
  });
  final FeedPost post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onMore;
  final VoidCallback onProfileTap;
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
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 4, 10, 0),
              leading: InkWell(
                onTap: onProfileTap,
                child: _PostAvatar(
                  username: post.author,
                  avatarUrl: post.avatarUrl,
                ),
              ),
              title: InkWell(
                onTap: onProfileTap,
                child: Text(
                  post.author,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
              ),
              subtitle: Text(
                '${post.minutesAgo}m',
                style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xffb3b3b3)),
              ),
              trailing: IconButton(
                onPressed: onMore,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: isLight ? Colors.black : Colors.white,
                  size: 22,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                post.text,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.45,
                  color: isLight ? Colors.black : Colors.white,
                ),
              ),
            ),
            if (post.imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 1.08,
                    child: _FeedMedia(url: post.imageUrl),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onLike,
                    icon: Icon(
                      post.liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: post.liked ? Colors.red : (isLight ? Colors.black : Colors.white),
                      size: 24,
                    ),
                  ),
                  IconButton(
                    onPressed: onComment,
                    icon: Icon(
                      Icons.mode_comment_outlined,
                      color: isLight ? Colors.black : Colors.white,
                      size: 23,
                    ),
                  ),
                  IconButton(
                    onPressed: onShare,
                    icon: Icon(
                      Icons.send_outlined,
                      color: isLight ? Colors.black : Colors.white,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onSave,
                    icon: Icon(
                      Icons.bookmark_border_rounded,
                      color: isLight ? Colors.black : Colors.white,
                      size: 24,
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
                    '${post.likes} likes',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onComment,
                    child: Text(
                      post.comments.isEmpty
                          ? 'Add a comment...'
                          : 'View ${post.comments.length} comments',
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
  const _LogoMark({required this.themeMode});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Image.asset(
        'assets/neat_logo.png',
        height: 52,
        fit: BoxFit.contain,
        color: themeMode == ThemeMode.light ? Colors.black : Colors.white,
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
    final bytes = _decodeDataUrl(url);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return CircleAvatar(
      radius: 11,
      backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
      foregroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Icon(Icons.person_outline_rounded, color: isLight ? Colors.black : Colors.white, size: 18)
          : null,
    );
  }
}

class _TopBarPill extends StatelessWidget {
  const _TopBarPill({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Material(
      color: isLight ? Colors.white : const Color(0xff171718),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isLight ? const Color(0xffd9dee6) : const Color(0xff262626),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView({
    required this.token,
    required this.currentUser,
    required this.onOpenUserProfile,
  });

  final String token;
  final UserProfile currentUser;
  final ValueChanged<String> onOpenUserProfile;

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

  String get _historyKey => 'search_history_${widget.currentUser.city}';

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
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_historyKey) ?? const [];
    if (!mounted) return;
    setState(() {
      _recentQueries
        ..clear()
        ..addAll(items);
    });
  }

  Future<void> _saveRecentQueries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _recentQueries);
  }

  Future<void> _clearHistory() async {
    setState(() => _recentQueries.clear());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
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
    if (query.isNotEmpty) {
      setState(() {
        _recentQueries.remove(query);
        _recentQueries.insert(0, query);
        if (_recentQueries.length > 5) {
          _recentQueries.removeLast();
        }
      });
      _saveRecentQueries();
    }
    widget.onOpenUserProfile(user.username);
  }

  Widget _buildUserTile(UserProfile user) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openProfileAndRemember(user),
        child: Container(
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xff171718),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isLight ? const Color(0xffd9dee6) : const Color(0xff262626)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _PostAvatar(username: user.username, avatarUrl: user.avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName.isNotEmpty ? user.fullName : user.username,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@${user.username} · ${user.city}',
                      style: TextStyle(
                        color: isLight ? const Color(0xff616161) : const Color(0xff9c9c9c),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: isLight ? Colors.black : Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  void _onSearchSubmitted() {
    final query = _controller.text.trim();
    if (query.isNotEmpty) {
      setState(() {
        _recentQueries.remove(query);
        _recentQueries.insert(0, query);
        if (_recentQueries.length > 8) {
          _recentQueries.removeLast();
        }
      });
      _saveRecentQueries();
    }
    _load(query);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          onSubmitted: (_) => _onSearchSubmitted(),
          style: TextStyle(color: isLight ? Colors.black : Colors.white),
          cursorColor: isLight ? Colors.black : Colors.white,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search, color: isLight ? const Color(0xff8b95a3) : const Color(0xffa6a6a6)),
            hintText: 'Search people',
            hintStyle: TextStyle(color: isLight ? const Color(0xff8b95a3) : const Color(0xff8f8f8f)),
            filled: true,
            fillColor: isLight ? Colors.white : const Color(0xff1a1a1b),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: isLight ? Colors.black : Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            _SearchSegment(
              label: 'Top',
              selected: _section == 0,
              onTap: () => setState(() => _section = 0),
            ),
            _SearchSegment(
              label: 'Accounts',
              selected: _section == 1,
              onTap: () => setState(() => _section = 1),
            ),
            _SearchSegment(
              label: 'Posts',
              selected: _section == 2,
              onTap: () => setState(() => _section = 2),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_controller.text.trim().isEmpty) ...[
          if (_loadingSuggestions || _loadingTop)
            const Padding(
              padding: EdgeInsets.only(top: 22),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_recentQueries.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent searches',
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearHistory,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentQueries
                  .map(
                      (query) => InputChip(
                        onPressed: () {
                          _controller.text = query;
                          _controller.selection = TextSelection.collapsed(
                            offset: query.length,
                          );
                          _load(query);
                          setState(() {});
                        },
                        backgroundColor: isLight ? Colors.white : const Color(0xff1a1a1b),
                        side: BorderSide(color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                        label: Text(
                          query,
                          style: TextStyle(color: isLight ? Colors.black : Colors.white),
                        ),
                        deleteIcon: const Icon(
                          Icons.close,
                          size: 16,
                          color: Color(0xffb3b3b3),
                        ),
                        onDeleted: () {
                          setState(() {
                            _recentQueries.remove(query);
                          });
                          _saveRecentQueries();
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (_suggestedUsers.isNotEmpty) ...[
              Text(
                'Suggested for you',
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ..._suggestedUsers.map(_buildUserTile),
              const SizedBox(height: 10),
            ],
            if (_section == 0) ...[
              if (_currentFeaturedPosts.isNotEmpty) ...[
                Text(
                  'Featured',
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                ..._currentFeaturedPosts.take(3).map(
                  (item) => item is UserProfile
                      ? _buildUserTile(item)
                      : _buildPostTile(item as FeedPost),
                ),
              ],
              if (_topUsers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Top results',
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                ..._topUsers.take(5).map(_buildUserTile),
              ],
            ],
            if (_section == 2 && _cityPosts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Popular posts',
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ..._popularPosts.take(3).map(_buildPostTile),
            ],
          ],
        ],
        if (_loading)
              Padding(
                padding: EdgeInsets.only(top: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              if (_section == 2)
                if (_searchPosts(_controller.text.trim()).isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 36),
                child: Center(
                  child: Text(
                    'No posts found in your city.',
                    style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xffb3b3b3)),
                  ),
                ),
              )
            else
              ..._searchPosts(_controller.text.trim()).map(_buildPostTile)
          else if (_users.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 36),
              child: Center(
                child: Text(
                  'No people found in your city.',
                  style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xffb3b3b3)),
                ),
              ),
            )
          else
            ..._users.map(_buildUserTile),
      ],
    );
  }

  List<FeedPost> get _popularPosts {
    final posts = _cityPosts.where((post) => post.likes >= 1).toList();
    posts.sort((a, b) => b.likes.compareTo(a.likes));
    return posts;
  }

  List<Object> get _currentFeaturedPosts {
    final minute = DateTime.now().minute;
    if (minute.isEven) {
      return _topUsers.isNotEmpty ? _topUsers : _popularPosts;
    }
    return _popularPosts.isNotEmpty ? _popularPosts : _topUsers;
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

  Widget _buildPostTile(FeedPost post) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => widget.onOpenUserProfile(post.author),
        child: Container(
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xff171718),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isLight ? const Color(0xffd9dee6) : const Color(0xff262626)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                child: Text(initialFor(post.author)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            post.author,
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${post.likes} likes',
                          style: TextStyle(
                            color: isLight ? const Color(0xff616161) : const Color(0xff9c9c9c),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      post.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${post.city}',
                      style: TextStyle(
                        color: isLight ? const Color(0xff616161) : const Color(0xff9c9c9c),
                        fontSize: 12,
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
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Colors.white,
      backgroundColor: const Color(0xff1a1a1b),
      side: const BorderSide(color: Color(0xff2a2a2a)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _ActivityView extends StatelessWidget {
  const _ActivityView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No activity yet.',
        style: TextStyle(color: Color(0xffb3b3b3)),
      ),
    );
  }
}

class _ShareChip extends StatelessWidget {
  const _ShareChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xff1e1e1e),
      side: const BorderSide(color: Color(0xff2a2a2a)),
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
    final bytes = _decodeDataUrl(avatarUrl);
    return CircleAvatar(
      backgroundColor: const Color(0xff2a2a2a),
      foregroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Text(
              initialFor(username),
              style: const TextStyle(color: Colors.white),
            )
          : null,
    );
  }
}

Uint8List? _decodeDataUrl(String value) {
  if (!value.startsWith('data:')) return null;
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(value.substring(comma + 1));
  } catch (_) {
    return null;
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
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xffb7b7b7),
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
                    color: item.isRead
                        ? const Color(0xff161616)
                        : const Color(0xff1c1c1c),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: item.isRead
                          ? const Color(0xff262626)
                          : const Color(0xff3a3a3a),
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xff2a2a2a),
                        child: Text(
                          initialFor(item.actor),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: Colors.white,
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
                                style: const TextStyle(
                                  color: Color(0xffb7b7b7),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              _timeAgo(item.created),
                              style: const TextStyle(
                                color: Color(0xff8f8f8f),
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
                            decoration: const BoxDecoration(
                              color: Colors.white,
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

String _timeAgo(DateTime created) {
  final diff = DateTime.now().difference(created);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
