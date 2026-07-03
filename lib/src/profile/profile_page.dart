import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/legacy_nav_bar.dart';
import '../core/media_cache.dart';
import '../core/models.dart';
import '../core/post_card.dart';
import '../admin/admin_panel_page.dart';
import '../core/report_post_sheet.dart';
import '../core/share_sheet.dart';
import '../messages/messages_page.dart';
import '../settings/settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.username,
    required this.currentUser,
    required this.token,
    required this.posts,
    required this.onOpenUserProfile,
    required this.onPostTap,
    required this.onLogout,
    required this.onSessionUpdated,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.initialPostId,
    this.onOpenProfileAtPost,
    this.onHideNavBar,
    this.onShowNavBar,
    this.followEnabled = true,
    this.onNavTap,
    this.activeNavIndex = 0,
  });
  final String username;
  final UserProfile currentUser;
  final String token;
  final List<FeedPost> posts;
  final ValueChanged<String> onOpenUserProfile;
  final void Function(String username, int postId)? onOpenProfileAtPost;
  final ValueChanged<FeedPost> onPostTap;
  final Future<void> Function() onLogout;
  final ValueChanged<AuthSession> onSessionUpdated;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int? initialPostId;
  final VoidCallback? onHideNavBar;
  final VoidCallback? onShowNavBar;
  final bool followEnabled;
  /// When set, this page renders its own bottom nav bar (mirroring
  /// HomePage's legacy bar) instead of relying on one from underneath —
  /// used when this page was pushed on top of HomePage's Scaffold, which
  /// would otherwise hide HomePage's bottomNavigationBar entirely.
  final ValueChanged<int>? onNavTap;
  final int activeNavIndex;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  UserProfile? _profile;
  bool? _followingOverride;
  bool _loading = true;
  final ImagePicker _imagePicker = ImagePicker();
  final Map<int, GlobalKey> _postKeys = {};
  late final TabController _tabController;
  List<FeedPost>? _likedPosts;
  bool _likedLoading = false;
  List<FeedPost>? _savedPosts;
  bool _savedLoading = false;
  final Set<String> _followingAuthors = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
    _loadFollowingAuthors();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final i = _tabController.index;
    if (i == 1) _loadLikedPosts(silent: _likedPosts != null);
    if (i == 2) _loadSavedPosts(silent: _savedPosts != null);
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        profileEndpoint(widget.username),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode == 401) {
        await widget.onLogout();
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _profile = UserProfile.fromJson(
          decoded['user'] as Map<String, dynamic>,
        );
        _loading = false;
        _likedPosts = null;
        _savedPosts = null;
      });
      // Refresh whichever tab is open; null above ensures a fresh fetch
      if (_tabController.index == 1) _loadLikedPosts();
      if (_tabController.index == 2) _loadSavedPosts();
      // If server didn't supply followsYou, check followers list as fallback
      if (!(_profile?.followsYou ?? false)) _checkFollowsYou();
      if (widget.initialPostId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final key = _postKeys[widget.initialPostId!];
          if (key?.currentContext != null) {
            Scrollable.ensureVisible(
              key!.currentContext!,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkFollowsYou() async {
    try {
      final res = await http.get(
        followersEndpoint(widget.currentUser.username),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode != 200 || !mounted) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((u) => u['username']?.toString() ?? '')
          .where((u) => u.isNotEmpty);
      if (users.contains(widget.username)) {
        setState(() {
          _profile = _profile?.copyWith(followsYou: true);
        });
      }
    } catch (_) {}
  }

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
        _followingAuthors
          ..clear()
          ..addAll(usernames);
      });
    } catch (_) {}
  }

  Future<void> _followUser(String username) async {
    setState(() => _followingAuthors.add(username));
    final res = await http.post(
      followEndpoint(username),
      headers: authJsonHeaders(widget.token),
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

  Future<void> _unfollowUser(String username) async {
    setState(() => _followingAuthors.remove(username));
    final res = await http.post(
      followEndpoint(username),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'follow': false}),
    );
    if (res.statusCode == 401) {
      setState(() => _followingAuthors.add(username));
      await widget.onLogout();
      return;
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      if (mounted) setState(() => _followingAuthors.add(username));
    } else if (mounted) {
      await _loadFollowingAuthors();
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null) return;
    final newFollowing = !profile.isFollowing;
    setState(() => _followingOverride = newFollowing);
    final res = await http.post(
      followEndpoint(profile.username),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'follow': newFollowing}),
    );
    if (res.statusCode < 400) {
      if (mounted) {
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(res.body) as Map<String, dynamic>;
            setState(() {
              _followingOverride = null;
              _profile = UserProfile.fromJson(
                decoded['user'] as Map<String, dynamic>,
              );
              widget.onSessionUpdated(
                AuthSession(
                  token: widget.token,
                  user: UserProfile.fromJson(
                    decoded['viewer'] as Map<String, dynamic>,
                  ),
                ),
              );
            });
          } catch (_) {
            setState(() {
              _followingOverride = null;
              _profile = _profile?.copyWith(isFollowing: newFollowing);
            });
          }
        } else {
          setState(() {
            _followingOverride = null;
            _profile = _profile?.copyWith(isFollowing: newFollowing);
          });
        }
      }
    } else if (mounted) {
      setState(() => _followingOverride = null);
    }
  }

  Future<void> _toggleBlock() async {
    final profile = _profile;
    if (profile == null) return;
    final res = await http.post(
      userBlockEndpoint(profile.username),
      headers: authJsonHeaders(widget.token),
    );
    if (res.statusCode == 401) {
      await widget.onLogout();
      return;
    }
    if (res.statusCode != 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong')),
      );
      return;
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final updated = UserProfile.fromJson(decoded['user'] as Map<String, dynamic>);
    if (!mounted) return;
    setState(() => _profile = updated);
    widget.onSessionUpdated(
      AuthSession(
        token: widget.token,
        user: UserProfile.fromJson(decoded['viewer'] as Map<String, dynamic>),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(updated.isBlocked ? 'User blocked' : 'User unblocked')),
    );
  }

  void _openProfileMoreSheet() {
    final profile = _profile;
    if (profile == null) return;
    widget.onHideNavBar?.call();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                profile.isBlocked ? Icons.check_circle_outline : Icons.block,
                color: profile.isBlocked ? (isLight ? Colors.black : Colors.white) : const Color(0xfff66c6c),
              ),
              title: Text(
                profile.isBlocked ? 'Unblock @${profile.username}' : 'Block @${profile.username}',
                style: TextStyle(
                  color: profile.isBlocked ? (isLight ? Colors.black : Colors.white) : const Color(0xfff66c6c),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                if (profile.isBlocked) {
                  await _toggleBlock();
                  return;
                }
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Block User'),
                    content: Text(
                      'Block @${profile.username}? They won\'t be able to '
                      'find your profile, see your posts, or message you.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Block', style: TextStyle(color: Color(0xfff66c6c))),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await _toggleBlock();
              },
            ),
          ],
        ),
      ),
    ).whenComplete(() => widget.onShowNavBar?.call());
  }

  Future<void> _startDirectMessage() async {
    final profile = _profile;
    if (profile == null || profile.username == widget.currentUser.username) return;
    final res = await http.post(
      startConversationEndpoint,
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'username': profile.username}),
    );
    if (res.statusCode == 401) {
      await widget.onLogout();
      return;
    }
    if (res.statusCode != 200 && res.statusCode != 201) return;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final conversation = ConversationSummary.fromJson(
      decoded['conversation'] as Map<String, dynamic>,
    );
    if (!mounted) return;
    widget.onHideNavBar?.call();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationPage(
          token: widget.token,
          currentUsername: widget.currentUser.username,
          conversationId: conversation.id,
          otherUsername: conversation.otherUser,
          otherFullName: conversation.otherFullName,
          otherAvatarUrl: conversation.otherAvatarUrl,
          onLogout: widget.onLogout,
          onOpenPost: widget.onOpenProfileAtPost != null
              ? (author, postId) {
                  Navigator.pop(context);
                  widget.onOpenProfileAtPost!(author, postId);
                }
              : null,
        ),
      ),
    );
    widget.onShowNavBar?.call();
  }

  Future<bool> _likePost(FeedPost post) async {
    try {
      final res = await http.post(
        postLikeEndpoint(post.id),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'liked': post.liked}),
      );
      if (res.statusCode == 401) { await widget.onLogout(); return false; }
      if (res.statusCode == 200) {
        if (_likedPosts != null && mounted) {
          setState(() {
            final rest = _likedPosts!.where((p) => p.id != post.id).toList();
            // Move to top on like, remove on unlike
            _likedPosts = post.liked ? [post, ...rest] : rest;
          });
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _savePost(FeedPost post) async {
    try {
      final res = await http.post(
        postSaveEndpoint(post.id),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'saved': post.saved}),
      );
      if (res.statusCode == 401) { await widget.onLogout(); return false; }
      if (res.statusCode == 200) {
        if (_savedPosts != null && mounted) {
          setState(() {
            final rest = _savedPosts!.where((p) => p.id != post.id).toList();
            // Move to top on save, remove on unsave
            _savedPosts = post.saved ? [post, ...rest] : rest;
          });
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _openMoreSheet(FeedPost post) {
    widget.onHideNavBar?.call();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (post.author == widget.currentUser.username || widget.currentUser.isAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xfff66c6c)),
                title: const Text('Delete post', style: TextStyle(color: Color(0xfff66c6c))),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _deletePost(post);
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report post'),
              onTap: () {
                Navigator.of(context).pop();
                showReportPostSheet(
                  context,
                  postId: post.id,
                  token: widget.token,
                );
              },
            ),
          ],
        ),
      ),
    ).whenComplete(() => widget.onShowNavBar?.call());
  }

  Widget _buildPostCard(FeedPost post, {Key? key}) {
    return FeedPostCard(
      key: key,
      post: post,
      token: widget.token,
      currentUser: widget.currentUser,
      followingAuthors: _followingAuthors,
      onFollowUser: _followUser,
      onUnfollowUser: _unfollowUser,
      onLike: () => _likePost(post),
      onSave: () => _savePost(post),
      onShare: () => showShareSheet(
        context: context,
        post: post,
        token: widget.token,
        currentUser: widget.currentUser,
        onLogout: widget.onLogout,
      ),
      onMore: () => _openMoreSheet(post),
      onComment: () => widget.onPostTap(post),
      onProfileTap: () => widget.onOpenUserProfile(post.author),
      onOpenUserProfile: widget.onOpenUserProfile,
    );
  }

  Future<void> _deletePost(FeedPost post) async {
    final res = await http.delete(
      postDeleteEndpoint(post.id),
      headers: authGetHeaders(widget.token),
    );
    if (res.statusCode == 200) {
      await _load();
    }
  }

  Future<void> _loadLikedPosts({bool silent = false}) async {
    if (_likedLoading) return;
    _likedLoading = true; // guard against concurrent fetches
    if (!silent && mounted) setState(() => _likedLoading = true);
    try {
      final res = await http.get(likedPostsEndpoint, headers: authGetHeaders(widget.token));
      if (res.statusCode == 401) { _likedLoading = false; await widget.onLogout(); return; }
      if (!mounted) { _likedLoading = false; return; }
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final posts = (decoded['posts'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FeedPost.fromJson)
            .toList();
        setState(() { _likedPosts = posts; _likedLoading = false; });
      } else {
        // Endpoint missing — fall back to posts seen in the feed
        setState(() {
          _likedPosts = widget.posts.where((p) => p.liked).toList();
          _likedLoading = false;
        });
      }
    } catch (_) {
      _likedLoading = false;
      if (mounted) setState(() { _likedPosts ??= []; _likedLoading = false; });
    }
  }

  Future<void> _loadSavedPosts({bool silent = false}) async {
    if (_savedLoading) return;
    _savedLoading = true; // guard against concurrent fetches
    if (!silent && mounted) setState(() => _savedLoading = true);
    try {
      final res = await http.get(
        savedPostsEndpoint,
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode == 401) { _savedLoading = false; await widget.onLogout(); return; }
      if (!mounted) { _savedLoading = false; return; }
      List<FeedPost> posts = const [];
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        posts = (decoded['posts'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FeedPost.fromJson)
            .toList();
      }
      if (mounted) setState(() { _savedPosts = posts; _savedLoading = false; });
    } catch (_) {
      _savedLoading = false;
      if (mounted) setState(() { _savedPosts ??= []; _savedLoading = false; });
    }
  }

  void _openAvatarFullscreen(UserProfile profile) {
    if (profile.avatarUrl.isEmpty) return;
    final bytes = _dataUrlBytes(profile.avatarUrl);
    final Widget image = bytes != null
        ? Image.memory(bytes, fit: BoxFit.contain)
        : CachedNetworkImage(
            imageUrl: profile.avatarUrl,
            cacheManager: imageCacheManager,
            fit: BoxFit.contain,
            fadeInDuration: Duration.zero,
          );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: image,
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEditProfile() async {
    final profile = _profile;
    if (profile == null) return;

    widget.onHideNavBar?.call();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditProfileSheet(
        token: widget.token,
        profile: profile,
        imagePicker: _imagePicker,
        onSaved: (updated) {
          if (!mounted) return;
          setState(() => _profile = updated);
          widget.onSessionUpdated(
            AuthSession(token: widget.token, user: updated),
          );
        },
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
    );
    widget.onShowNavBar?.call();
  }

  Future<void> _openUserList({
    required String title,
    required Uri endpoint,
    bool markFollowsYou = false,
  }) async {
    final res = await http.get(endpoint, headers: authGetHeaders(widget.token));
    if (res.statusCode != 200) return;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final rawUsers = (decoded['users'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UserProfile.fromJson)
        .toList();
    final users = markFollowsYou
        ? rawUsers.map((u) => u.copyWith(followsYou: true)).toList()
        : rawUsers;
    if (!mounted) return;
    widget.onHideNavBar?.call();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _UserListPage(
          title: title,
          users: users,
          currentUser: widget.currentUser,
          token: widget.token,
          themeMode: widget.themeMode,
          onSessionUpdated: widget.onSessionUpdated,
          onProfileRefresh: _load,
          onOpenProfile: widget.onOpenUserProfile,
        ),
      ),
    );
    widget.onShowNavBar?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final profile = _profile;
    if (_loading || profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isOwn = profile.username == widget.currentUser.username;
    final userPosts = widget.posts
        .where((p) => p.author == profile.username)
        .toList();
    return Scaffold(
      backgroundColor: isLight ? Colors.white : const Color(0xff121212),
      bottomNavigationBar: widget.onNavTap == null
          ? null
          : LegacyNavBar(
              isLight: isLight,
              currentIndex: widget.activeNavIndex,
              onTap: widget.onNavTap!,
              avatarUrl: widget.currentUser.avatarUrl,
            ),
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xff121212),
        titleSpacing: 12,
        title: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              foregroundImage:
                  _dataUrlBytes(profile.avatarUrl) != null
                      ? MemoryImage(_dataUrlBytes(profile.avatarUrl)!)
                      : null,
              child: _dataUrlBytes(profile.avatarUrl) == null
                  ? Text(
                      initialFor(profile.username),
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              profile.username,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isLight ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          if (profile.username == widget.currentUser.username && widget.currentUser.isAdmin)
            IconButton(
              tooltip: 'Admin Panel',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminPanelPage(token: widget.token),
                ),
              ),
              icon: Icon(Icons.admin_panel_settings_rounded, color: isLight ? Colors.black : Colors.white),
            ),
          if (profile.username == widget.currentUser.username)
            IconButton(
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    themeMode: widget.themeMode,
                    onLogout: widget.onLogout,
                    token: widget.token,
                  ),
                ),
              ),
              icon: Icon(Icons.settings_rounded, color: isLight ? Colors.black : Colors.white),
            ),
          if (!isOwn)
            IconButton(
              tooltip: 'More options',
              onPressed: _openProfileMoreSheet,
              icon: Icon(Icons.more_vert, color: isLight ? Colors.black : Colors.white),
            ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (_, _) => [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: (profile.avatarZoomable && profile.avatarUrl.isNotEmpty)
                            ? () => _openAvatarFullscreen(profile)
                            : null,
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                          foregroundImage: _dataUrlBytes(profile.avatarUrl) != null
                              ? MemoryImage(_dataUrlBytes(profile.avatarUrl)!)
                              : null,
                          child: _dataUrlBytes(profile.avatarUrl) == null
                              ? Text(
                                  initialFor(profile.username),
                                  style: TextStyle(color: isLight ? Colors.black : Colors.white),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _Metric(label: 'posts', value: '${userPosts.length}', onTap: null),
                            _Metric(
                              label: 'followers',
                              value: '${profile.followers}',
                              onTap: () => _openUserList(
                                title: 'Followers',
                                endpoint: followersEndpoint(profile.username),
                                markFollowsYou: profile.username == widget.currentUser.username,
                              ),
                            ),
                            _Metric(
                              label: 'following',
                              value: '${profile.following}',
                              onTap: () => _openUserList(
                                title: 'Following',
                                endpoint: followingEndpoint(profile.username),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            profile.fullName.isEmpty ? profile.username : profile.fullName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),
                          if (profile.isVerified) ...[
                            const SizedBox(width: 5),
                            const Icon(Icons.verified_rounded, size: 18, color: Color(0xff0095f6)),
                          ],
                        ],
                      ),
                      if (profile.bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile.bio,
                          style: TextStyle(
                            color: isLight ? const Color(0xff616161) : const Color(0xffb3b3b3),
                          ),
                        ),
                      ],
                      if (!isOwn && profile.mutualsCount > 0) ...[
                        const SizedBox(height: 8),
                        _MutualsRow(
                          mutuals: profile.mutuals,
                          mutualsCount: profile.mutualsCount,
                          isLight: isLight,
                          onTap: widget.onOpenUserProfile,
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: profile.username == widget.currentUser.username
                      ? OutlinedButton(onPressed: _openEditProfile, child: const Text('Edit profile'))
                      : profile.isBlocked
                          ? SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _toggleBlock,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xfff66c6c)),
                                  foregroundColor: const Color(0xfff66c6c),
                                ),
                                child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            )
                          : profile.hasBlockedYou
                              ? const SizedBox.shrink()
                              : Row(
                                  children: [
                                    Expanded(
                                      child: (_followingOverride ?? profile.isFollowing)
                                          ? OutlinedButton(
                                              onPressed: widget.followEnabled ? _toggleFollow : null,
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(color: isLight ? Colors.black : Colors.white),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                foregroundColor: isLight ? Colors.black : Colors.white,
                                              ),
                                              child: const Text('Following', style: TextStyle(fontWeight: FontWeight.w600)),
                                            )
                                          : FilledButton(onPressed: widget.followEnabled ? _toggleFollow : null, child: Text(profile.followsYou ? 'Follow Back' : 'Follow')),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      height: 42,
                                      width: 42,
                                      child: OutlinedButton(
                                        onPressed: _startDirectMessage,
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                        ),
                                        child: const Icon(Icons.send_outlined, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                ),
              ],
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _ProfileTabBarDelegate(
              TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicatorColor: isLight ? Colors.black : Colors.white,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: isLight ? Colors.black : Colors.white,
                unselectedLabelColor: isLight ? const Color(0xff9e9e9e) : const Color(0xff666666),
                tabs: const [
                  Tab(icon: Icon(Icons.grid_on_rounded, size: 22)),
                  Tab(icon: Icon(Icons.favorite_border_rounded, size: 22)),
                  Tab(icon: Icon(Icons.bookmark_border_rounded, size: 22)),
                ],
              ),
              isLight ? Colors.white : const Color(0xff121212),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 0: Posts
            userPosts.isEmpty
                ? const CustomScrollView(slivers: [SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No posts yet.', style: TextStyle(color: Color(0xffb3b3b3)))))])
                : ListView.builder(
                    key: const PageStorageKey('posts'),
                    itemCount: userPosts.length,
                    itemBuilder: (_, i) {
                      final post = userPosts[i];
                      final key = _postKeys.putIfAbsent(post.id, () => GlobalKey());
                      return _buildPostCard(post, key: key);
                    },
                  ),
            // Tab 1: Liked
            _buildLikedTab(isOwn),
            // Tab 2: Saved
            _buildSavedTab(isOwn),
          ],
        ),
      ),
    );
  }

  Widget _buildLikedTab(bool isOwn) {
    if (!isOwn) {
      return const Center(child: Icon(Icons.lock_outline, size: 48, color: Color(0xffb3b3b3)));
    }
    if (_likedLoading) return const Center(child: CircularProgressIndicator());
    final liked = _likedPosts;
    if (liked == null) return const SizedBox.shrink();
    if (liked.isEmpty) {
      return const Center(child: Text('No liked posts yet.', style: TextStyle(color: Color(0xffb3b3b3))));
    }
    return ListView.builder(
      key: const PageStorageKey('liked'),
      itemCount: liked.length,
      itemBuilder: (_, i) => _buildPostCard(liked[i], key: ValueKey(liked[i].id)),
    );
  }

  Widget _buildSavedTab(bool isOwn) {
    if (!isOwn) {
      return const Center(child: Icon(Icons.lock_outline, size: 48, color: Color(0xffb3b3b3)));
    }
    if (_savedLoading) return const Center(child: CircularProgressIndicator());
    final saved = _savedPosts;
    if (saved == null) return const SizedBox.shrink();
    if (saved.isEmpty) {
      return const Center(child: Text('No saved posts yet.', style: TextStyle(color: Color(0xffb3b3b3))));
    }
    return ListView.builder(
      key: const PageStorageKey('saved'),
      itemCount: saved.length,
      itemBuilder: (_, i) => _buildPostCard(saved[i], key: ValueKey(saved[i].id)),
    );
  }
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

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final child = Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.black
                : Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xff616161)
                : const Color(0xffb3b3b3),
          ),
        ),
      ],
    );
    return onTap == null ? child : InkWell(onTap: onTap, child: child);
  }
}

class _MutualsRow extends StatelessWidget {
  const _MutualsRow({
    required this.mutuals,
    required this.mutualsCount,
    required this.isLight,
    required this.onTap,
  });

  final List<MutualUser> mutuals;
  final int mutualsCount;
  final bool isLight;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final subClr = isLight ? const Color(0xff616161) : const Color(0xffb3b3b3);
    final boldClr = isLight ? Colors.black : Colors.white;

    // Build the label spans: "Followed by user1, user2 and 3 others"
    final preview = mutuals.take(3).toList();
    final extra = mutualsCount - preview.length;

    final spans = <InlineSpan>[
      TextSpan(text: 'Followed by ', style: TextStyle(color: subClr, fontSize: 13)),
    ];
    for (var i = 0; i < preview.length; i++) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => onTap(preview[i].username),
            child: Text(
              preview[i].username,
              style: TextStyle(
                color: boldClr,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
      if (i < preview.length - 1 || extra > 0) {
        final isLastPreview = i == preview.length - 1;
        final sep = isLastPreview ? ' and ' : ', ';
        spans.add(TextSpan(text: sep, style: TextStyle(color: subClr, fontSize: 13)));
      }
    }
    if (extra > 0) {
      spans.add(
        TextSpan(
          text: '$extra ${extra == 1 ? 'other' : 'others'}',
          style: TextStyle(color: boldClr, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Overlapping mini avatars
        SizedBox(
          width: preview.length * 16.0 + 8,
          height: 22,
          child: Stack(
            children: [
              for (var i = 0; i < preview.length; i++)
                Positioned(
                  left: i * 16.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isLight ? Colors.white : const Color(0xff121212),
                        width: 1.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 9,
                      backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                      foregroundImage: _dataUrlBytes(preview[i].avatarUrl) != null
                          ? MemoryImage(_dataUrlBytes(preview[i].avatarUrl)!)
                          : null,
                      child: _dataUrlBytes(preview[i].avatarUrl) == null
                          ? Text(
                              initialFor(preview[i].username),
                              style: TextStyle(
                                fontSize: 7,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text.rich(TextSpan(children: spans)),
        ),
      ],
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.maxLength,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final int? maxLength;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      readOnly: readOnly,
      style: TextStyle(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.black
            : Colors.white,
      ),
      cursorColor: Theme.of(context).brightness == Brightness.light
          ? Colors.black
          : Colors.white,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Theme.of(context).brightness == Brightness.light
              ? const Color(0xff6b7280)
              : const Color(0xff9c9c9c),
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : const Color(0xff171717),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xffd9dee6)
                : const Color(0xff2a2a2a),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.black
                : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.url});

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
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: imageCacheManager,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.token,
    required this.profile,
    required this.imagePicker,
    required this.onSaved,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final String token;
  final UserProfile profile;
  final ImagePicker imagePicker;
  final ValueChanged<UserProfile> onSaved;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _usernameController;
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _cityController;
  String _avatarUrl = '';
  bool _saving = false;
  late bool _avatarZoomable;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _nameController = TextEditingController(text: widget.profile.fullName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _cityController = TextEditingController(text: widget.profile.city);
    _avatarUrl = widget.profile.avatarUrl;
    _avatarZoomable = widget.profile.avatarZoomable;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensures the sheet repaints immediately when the theme toggles while open.
    setState(() {});
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await widget.imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1400,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final mime = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    setState(() {
      _avatarUrl = 'data:image/$mime;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final res = await http.patch(
        meEndpoint,
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({
          'username': _usernameController.text.trim(),
          'fullName': _nameController.text.trim(),
          'bio': _bioController.text.trim(),
          'city': _cityController.text.trim(),
          'avatarUrl': _avatarUrl,
          'avatarZoomable': _avatarZoomable,
        }),
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => _saving = false);
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final userJson = Map<String, dynamic>.from(
        decoded['user'] as Map<String, dynamic>,
      );
      userJson['avatarZoomable'] = _avatarZoomable;
      widget.onSaved(UserProfile.fromJson(userJson));
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final avatarBytes = _dataUrlBytes(_avatarUrl);
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xff111111),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
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
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                Text(
                  'Edit profile',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xffe6e9ef)
                        : const Color(0xff2a2a2a),
                    foregroundImage:
                        avatarBytes != null ? MemoryImage(avatarBytes) : null,
                    child: avatarBytes == null
                        ? Text(
                            initialFor(widget.profile.username),
                            style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.light
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _saving ? null : _pickAvatar,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          color: Colors.black,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _EditorField(
              controller: _usernameController,
              label: 'Username',
            ),
            const SizedBox(height: 12),
            _EditorField(
              controller: _nameController,
              label: 'Name',
            ),
            const SizedBox(height: 12),
            _EditorField(
              controller: _cityController,
              label: 'City',
              readOnly: true,
            ),
            const SizedBox(height: 12),
            _EditorField(
              controller: _bioController,
              label: 'Bio',
              maxLines: 4,
              maxLength: 150,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Allow profile picture zoom',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _avatarZoomable,
                  onChanged: (v) => setState(() => _avatarZoomable = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Light mode',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: Theme.of(context).brightness == Brightness.light,
                  onChanged: (value) {
                    widget.onThemeModeChanged(
                      value ? ThemeMode.light : ThemeMode.dark,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  }
}

class _SavedPostsPage extends StatefulWidget {
  const _SavedPostsPage({
    required this.posts,
    required this.themeMode,
    required this.onOpenPost,
  });

  final List<FeedPost> posts;
  final ThemeMode themeMode;
  final void Function(String author, int postId) onOpenPost;

  @override
  State<_SavedPostsPage> createState() => _SavedPostsPageState();
}

class _SavedPostsPageState extends State<_SavedPostsPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<FeedPost> get _filtered {
    if (_query.isEmpty) return widget.posts;
    final q = _query.toLowerCase();
    return widget.posts
        .where((p) =>
            p.author.toLowerCase().contains(q) ||
            p.text.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor:
          isLight ? Colors.white : const Color(0xff121212),
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xff121212),
        iconTheme: IconThemeData(color: isLight ? Colors.black : Colors.white),
        title: Text(
          'Saved',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isLight ? Colors.black : Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              style:
                  TextStyle(color: isLight ? Colors.black : Colors.white),
              cursorColor: isLight ? Colors.black : Colors.white,
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.search,
                  color: isLight
                      ? const Color(0xff8b95a3)
                      : const Color(0xffa6a6a6),
                ),
                hintText: 'Search saved posts',
                hintStyle: TextStyle(
                  color: isLight
                      ? const Color(0xff8b95a3)
                      : const Color(0xff8f8f8f),
                ),
                filled: true,
                fillColor:
                    isLight ? Colors.white : const Color(0xff1a1a1b),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isLight
                        ? const Color(0xffd9dee6)
                        : const Color(0xff2a2a2a),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isLight
                        ? const Color(0xffd9dee6)
                        : const Color(0xff2a2a2a),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      BorderSide(color: isLight ? Colors.black : Colors.white),
                ),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? 'No saved posts yet.' : 'No results.',
                      style: TextStyle(
                        color: isLight
                            ? const Color(0xff616161)
                            : const Color(0xffb7b7b7),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: isLight
                          ? const Color(0xffd9dee6)
                          : const Color(0xff242424),
                    ),
                    itemBuilder: (context, index) {
                      final post = _filtered[index];
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onOpenPost(post.author, post.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isLight
                                    ? const Color(0xffe6e9ef)
                                    : const Color(0xff2a2a2a),
                                child: Text(
                                  initialFor(post.author),
                                  style: TextStyle(
                                    color:
                                        isLight ? Colors.black : Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      post.author,
                                      style: TextStyle(
                                        color: isLight
                                            ? Colors.black
                                            : Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      post.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isLight
                                            ? const Color(0xff444444)
                                            : const Color(0xffb3b3b3),
                                        fontSize: 13.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (post.imageUrl.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: _AvatarPreview(url: post.imageUrl),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _UserListPage extends StatefulWidget {
  const _UserListPage({
    required this.title,
    required this.users,
    required this.currentUser,
    required this.token,
    required this.themeMode,
    required this.onSessionUpdated,
    required this.onProfileRefresh,
    required this.onOpenProfile,
  });

  final String title;
  final List<UserProfile> users;
  final UserProfile currentUser;
  final String token;
  final ThemeMode themeMode;
  final ValueChanged<AuthSession> onSessionUpdated;
  final Future<void> Function() onProfileRefresh;
  final ValueChanged<String> onOpenProfile;

  @override
  State<_UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<_UserListPage> {
  late final List<UserProfile> _users;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _users = List.of(widget.users);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<UserProfile> get _filtered {
    if (_query.isEmpty) return _users;
    final q = _query.toLowerCase();
    return _users
        .where((u) =>
            u.username.toLowerCase().contains(q) ||
            u.fullName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _toggleFollow(int index, UserProfile user) async {
    final res = await http.post(
      followEndpoint(user.username),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'follow': !user.isFollowing}),
    );
    if (res.statusCode != 200) return;
    if (!mounted) return;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    setState(() {
      _users[index] = UserProfile.fromJson(
        decoded['user'] as Map<String, dynamic>,
      );
    });
    widget.onSessionUpdated(
      AuthSession(
        token: widget.token,
        user: UserProfile.fromJson(
          decoded['viewer'] as Map<String, dynamic>,
        ),
      ),
    );
    await widget.onProfileRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final filtered = _filtered;
    return Scaffold(
      backgroundColor:
          isLight ? Colors.white : const Color(0xff121212),
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xff121212),
        iconTheme: IconThemeData(color: isLight ? Colors.black : Colors.white),
        title: Text(
          widget.title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isLight ? Colors.black : Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              style:
                  TextStyle(color: isLight ? Colors.black : Colors.white),
              cursorColor: isLight ? Colors.black : Colors.white,
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.search,
                  color: isLight
                      ? const Color(0xff8b95a3)
                      : const Color(0xffa6a6a6),
                ),
                hintText: 'Search',
                hintStyle: TextStyle(
                  color: isLight
                      ? const Color(0xff8b95a3)
                      : const Color(0xff8f8f8f),
                ),
                filled: true,
                fillColor:
                    isLight ? Colors.white : const Color(0xff1a1a1b),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isLight
                        ? const Color(0xffd9dee6)
                        : const Color(0xff2a2a2a),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isLight
                        ? const Color(0xffd9dee6)
                        : const Color(0xff2a2a2a),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      BorderSide(color: isLight ? Colors.black : Colors.white),
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? 'No users yet.' : 'No results.',
                      style: TextStyle(
                        color: isLight
                            ? const Color(0xff616161)
                            : const Color(0xffb7b7b7),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: isLight
                          ? const Color(0xffd9dee6)
                          : const Color(0xff262626),
                    ),
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      final globalIndex = _users.indexOf(user);
                      final canToggle =
                          user.username != widget.currentUser.username;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: isLight
                              ? const Color(0xffe6e9ef)
                              : const Color(0xff2a2a2a),
                          foregroundImage: user.avatarUrl.isNotEmpty
                              ? (_dataUrlBytes(user.avatarUrl) != null
                                  ? MemoryImage(_dataUrlBytes(user.avatarUrl)!)
                                  : CachedNetworkImageProvider(user.avatarUrl, cacheManager: imageCacheManager)
                                      as ImageProvider)
                              : null,
                          child: Text(
                            initialFor(user.username),
                            style: TextStyle(
                                color:
                                    isLight ? Colors.black : Colors.white),
                          ),
                        ),
                        title: Text(
                          user.username,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: user.fullName.isNotEmpty
                            ? Text(
                                user.fullName,
                                style: TextStyle(
                                  color: isLight
                                      ? const Color(0xff616161)
                                      : const Color(0xffb7b7b7),
                                ),
                              )
                            : null,
                        trailing: canToggle
                            ? (user.isFollowing
                                ? OutlinedButton(
                                    onPressed: () =>
                                        _toggleFollow(globalIndex, user),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      side: BorderSide(
                                        color: isLight
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      foregroundColor:
                                          isLight ? Colors.black : Colors.white,
                                    ),
                                    child: const Text(
                                      'Following',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  )
                                : FilledButton(
                                    onPressed: () =>
                                        _toggleFollow(globalIndex, user),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    child: Text(user.followsYou ? 'Follow Back' : 'Follow'),
                                  ))
                            : null,
                        onTap: () => widget.onOpenProfile(user.username),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _ProfileTabBarDelegate(this.tabBar, this.bg);
  final TabBar tabBar;
  final Color bg;

  @override
  Widget build(context, _, _) => ColoredBox(color: bg, child: tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(_ProfileTabBarDelegate old) =>
      old.tabBar != tabBar || old.bg != bg;
}
