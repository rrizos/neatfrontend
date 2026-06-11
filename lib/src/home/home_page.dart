import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import '../core/models.dart';
import '../map/city_map_view.dart';
import '../messages/messages_page.dart';
import '../profile/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.session,
    required this.onSessionChanged,
    required this.onLogout,
  });

  final AuthSession session;
  final ValueChanged<AuthSession> onSessionChanged;
  final Future<void> Function() onLogout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _compose = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final List<FeedPost> _posts = [];
  final List<NotificationItem> _notificationsList = [];
  final Set<String> _followingAuthors = {};
  int _nav = 0;
  int _selectedTab = 0;
  bool _loading = true;
  String _searchTerm = '';
  String? _activeCity;

  @override
  void initState() {
    super.initState();
    _load();
    _loadNotifications(silent: true);
  }

  @override
  void dispose() {
    _compose.dispose();
    _search.dispose();
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
      body: jsonEncode({'text': text}),
    );
    if (res.statusCode == 201) {
      _compose.clear();
      await _load();
      if (mounted) Navigator.of(context).pop();
    }
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

  void _openProfile(String username) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          username: username,
          currentUser: widget.session.user,
          token: widget.session.token,
          posts: _posts,
          onOpenUserProfile: _openProfile,
          onLogout: widget.onLogout,
          onSessionUpdated: widget.onSessionChanged,
          onPostTap: _openComments,
        ),
      ),
    );
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
      setState(() => _nav = 0);
      return;
    }
    setState(() {
      _activeCity = null;
      _nav = 0;
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
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xff141414),
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
                            const Text(
                              'Notifications',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
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
                                icon: const Icon(Icons.done_all, size: 18),
                                label: const Text('Mark all read'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xffededed),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Activity',
                          style: TextStyle(
                            color: Color(0xffb7b7b7),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'No notifications yet.',
                                style: TextStyle(color: Color(0xffb7b7b7)),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xff141414),
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
                  const Text(
                    'Comments',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: post.comments.isEmpty
                        ? const Center(
                            child: Text(
                              'No comments yet.',
                              style: TextStyle(color: Color(0xffb7b7b7)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: post.comments.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final comment = post.comments[index];
                              final sep = comment.indexOf(': ');
                              final author = sep > 0
                                  ? comment.substring(0, sep)
                                  : 'user';
                              final text = sep > 0
                                  ? comment.substring(sep + 2)
                                  : comment;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Avatar(name: author, radius: 15),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: '$author ',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          TextSpan(text: text),
                                        ],
                                      ),
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
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: const TextStyle(
                              color: Color(0xff9a9a9a),
                            ),
                            filled: true,
                            fillColor: const Color(0xff1e1e1e),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xff2a2a2a),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xff2a2a2a),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Colors.white),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: const Color(0xff141414),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xffb7b7b7),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    const Text(
                      'New post',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _createPost,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text('Post'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xff2a2a2a),
                      child: Text(
                        initialFor(widget.session.user.username),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _compose,
                        minLines: 6,
                        maxLines: 10,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.35,
                        ),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          hintText: 'What’s happening?',
                          hintStyle: TextStyle(color: Color(0xff8f8f8f)),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xff262626)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.image_outlined),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.gif_box_outlined),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.poll_outlined),
                    ),
                    const Spacer(),
                    Text(
                      '${_compose.text.length}/280',
                      style: const TextStyle(color: Color(0xff8f8f8f)),
                    ),
                  ],
                ),
              ],
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
      backgroundColor: const Color(0xff141414),
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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

    final filtered = _searchTerm.isEmpty
        ? (_selectedTab == 1
              ? (_followingAuthors.isEmpty
                    ? const <FeedPost>[]
                    : _posts
                        .where((post) => _followingAuthors.contains(post.author))
                        .toList())
              : _posts)
        : _posts
              .where(
                (post) =>
                    post.author.toLowerCase().contains(
                      _searchTerm.toLowerCase(),
                    ) ||
                    post.text.toLowerCase().contains(_searchTerm.toLowerCase()),
              )
              .toList();

    return Scaffold(
      backgroundColor: const Color(0xff121212),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              notifications: _notificationsList
                  .where((item) => !item.isRead)
                  .length,
              onProfileTap: () => _openProfile(widget.session.user.username),
              onNotificationsTap: _openNotifications,
              onMessagesTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MessagesPage(
                    token: widget.session.token,
                    currentUsername: widget.session.user.username,
                    onLogout: widget.onLogout,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xff232323)),
            Expanded(
              child: _nav == 0
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
                      controller: _search,
                      term: _searchTerm,
                      onChanged: (value) => setState(() => _searchTerm = value),
                    )
                  : _nav == 2
                  ? const _ActivityView()
                  : _nav == 3
                  ? CityMapView(
                      token: widget.session.token,
                      onOpenUserProfile: _openProfile,
                      onCitySelected: _openCityFeed,
                    )
                  : const _ActivityView(),
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
            selectedItemColor: Colors.white,
            unselectedItemColor: const Color(0xff8c8c8c),
            elevation: 0,
            backgroundColor: const Color(0xff151515),
            iconSize: 28,
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
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search_outlined),
                activeIcon: Icon(Icons.search),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.add_box_outlined),
                activeIcon: Icon(Icons.add_box),
                label: 'Create',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map),
                label: 'Map',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.favorite_border),
                activeIcon: Icon(Icons.favorite),
                label: 'Activity',
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
    required this.onProfileTap,
    required this.onNotificationsTap,
    required this.onMessagesTap,
  });
  final int notifications;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onMessagesTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const _LogoMark(),
            const Spacer(),
            _TopBarIcon(
              onTap: onProfileTap,
              child: const CircleAvatar(
                radius: 17,
                backgroundColor: Color(0xff232323),
                child: Icon(
                  Icons.person_outline,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ),
            Stack(
              children: [
                _TopBarIcon(
                  onTap: onNotificationsTap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.notifications_none,
                        color: Colors.white,
                        size: 24,
                      ),
                      if (notifications > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: const Color(0xfff66c6c),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              notifications > 9 ? '9+' : '$notifications',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            _TopBarIcon(
              onTap: onMessagesTap,
              child: const Icon(Icons.send_outlined, color: Colors.white, size: 22),
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
    return Container(
      color: const Color(0xff121212),
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
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: selectedTab == 0 ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 2,
                    width: selectedTab == 0 ? 72 : 0,
                    color: Colors.white,
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
                      color: Colors.white70,
                      fontSize: 17,
                      fontWeight: selectedTab == 1 ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 2,
                    width: selectedTab == 1 ? 84 : 0,
                    color: Colors.white,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xff131313),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xff242424)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 4, 10, 0),
              leading: InkWell(
                onTap: onProfileTap,
                child: CircleAvatar(
                  backgroundColor: const Color(0xff2a2a2a),
                  child: Text(initialFor(post.author)),
                ),
              ),
              title: InkWell(
                onTap: onProfileTap,
                child: Text(
                  post.author,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              subtitle: Text(
                '${post.minutesAgo}m',
                style: const TextStyle(color: Color(0xffb3b3b3)),
              ),
              trailing: IconButton(
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                post.text,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.45,
                  color: Colors.white,
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
                      post.liked ? Icons.favorite : Icons.favorite_border,
                      color: post.liked ? Colors.red : Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: onComment,
                    icon: const Icon(Icons.mode_comment_outlined, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: onShare,
                    icon: const Icon(Icons.send_outlined, color: Colors.white),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onSave,
                    icon: const Icon(Icons.bookmark_border, color: Colors.white),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Image.asset(
        'assets/neat_logo.png',
        height: 52,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  const _TopBarIcon({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: child,
    );
  }
}

class _SearchView extends StatelessWidget {
  const _SearchView({
    required this.controller,
    required this.term,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String term;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final topics = [
      'Vouliagmeni',
      'Kifisia',
      'Syntagma',
      'Plaka',
      'Food',
      'Events',
    ];
    final visible = topics
        .where((t) => t.toLowerCase().contains(term.toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Colors.white),
            hintText: 'Search',
            hintStyle: const TextStyle(color: Color(0xff8f8f8f)),
            filled: true,
            fillColor: const Color(0xff1e1e1e),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xff2a2a2a)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xff2a2a2a)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final topic in visible)
          ListTile(
            title: Text(topic, style: const TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Explore posts and people',
              style: TextStyle(color: Color(0xffb7b7b7)),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white),
          ),
      ],
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.radius});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xff2a2a2a),
      child: Text(
        initialFor(name),
        style: const TextStyle(color: Colors.white),
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
