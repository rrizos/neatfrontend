import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/http_client.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/legacy_nav_bar.dart';
import '../core/media_cache.dart';
import '../core/models.dart';
import '../core/post_card.dart';
import '../core/realtime_service.dart';
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
    this.bouncePost = false,
    this.autoOpenCommentActor,
    this.onPostTapWithHighlight,
    this.realtime,
  });
  final String username;
  final UserProfile currentUser;
  final String token;
  final List<FeedPost> posts;
  final ValueChanged<String> onOpenUserProfile;
  final void Function(String username, int postId)? onOpenProfileAtPost;
  final ValueChanged<FeedPost> onPostTap;
  final void Function(FeedPost post, String actor)? onPostTapWithHighlight;
  final Future<void> Function() onLogout;
  final ValueChanged<AuthSession> onSessionUpdated;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int? initialPostId;
  final bool bouncePost;
  final String? autoOpenCommentActor;
  final VoidCallback? onHideNavBar;
  final VoidCallback? onShowNavBar;
  final bool followEnabled;
  /// When set, this page renders its own bottom nav bar (mirroring
  /// HomePage's legacy bar) instead of relying on one from underneath —
  /// used when this page was pushed on top of HomePage's Scaffold, which
  /// would otherwise hide HomePage's bottomNavigationBar entirely.
  final ValueChanged<int>? onNavTap;
  final int activeNavIndex;
  // Native only — see realtime_service.dart. Null on web.
  final RealtimeService? realtime;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  UserProfile? _profile;
  bool? _followingOverride;
  bool _loading = true;
  bool _autoNavigating = false;
  int? _bouncePostId;
  final ImagePicker _imagePicker = ImagePicker();
  final Map<int, GlobalKey> _postKeys = {};
  late final TabController _tabController;
  final _nestedScrollKey = GlobalKey<NestedScrollViewState>();
  List<FeedPost>? _likedPosts;
  bool _likedLoading = false;
  List<FeedPost>? _savedPosts;
  bool _savedLoading = false;
  final Set<String> _followingAuthors = {};
  List<FeedPost>? _otherCityPosts;
  bool _otherCityPostsLoading = false;

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
      // For other-city profiles, fetch their posts from the API
      if (!widget.followEnabled) _loadOtherCityPosts();
      if (widget.initialPostId != null) {
        final bool doAuto = widget.bouncePost || widget.autoOpenCommentActor != null;
        if (doAuto) {
          setState(() => _autoNavigating = true);
          widget.onHideNavBar?.call();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          // With cacheExtent: 30000, all post widgets are pre-built with valid
          // RenderBoxes. Sum their actual rendered heights to get the exact offset.
          final innerCtrl = _nestedScrollKey.currentState?.innerController;
          if (innerCtrl != null && innerCtrl.hasClients) {
            final profileUsername = _profile?.username ?? '';
            final userPosts = widget.posts
                .where((p) => p.author == profileUsername)
                .toList();
            final postIdx =
                userPosts.indexWhere((p) => p.id == widget.initialPostId);
            if (postIdx > 0) {
              double targetOffset = 0;
              for (int i = 0; i < postIdx; i++) {
                final box = _postKeys[userPosts[i].id]
                    ?.currentContext
                    ?.findRenderObject() as RenderBox?;
                targetOffset += box?.size.height ?? 480.0;
              }
              // Center the post on screen
              final targetBox = _postKeys[userPosts[postIdx].id]
                  ?.currentContext
                  ?.findRenderObject() as RenderBox?;
              final targetHeight = targetBox?.size.height ?? 480.0;
              final viewportHeight = innerCtrl.position.viewportDimension;
              targetOffset = targetOffset - viewportHeight / 2 + targetHeight / 2;
              await innerCtrl.animateTo(
                targetOffset.clamp(0.0, innerCtrl.position.maxScrollExtent),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOut,
              );
              if (!mounted) return;
            }
          }

          if (widget.bouncePost) {
            setState(() => _bouncePostId = widget.initialPostId);
            await Future.delayed(const Duration(milliseconds: 900));
            if (!mounted) return;
            setState(() { _bouncePostId = null; _autoNavigating = false; });
            widget.onShowNavBar?.call();
          }

          if (widget.autoOpenCommentActor != null) {
            await Future.delayed(const Duration(milliseconds: 500));
            if (!mounted) return;
            FeedPost? post;
            for (final p in widget.posts) {
              if (p.id == widget.initialPostId) { post = p; break; }
            }
            if (post != null) {
              widget.onPostTapWithHighlight?.call(post, widget.autoOpenCommentActor!);
            }
            if (mounted) setState(() => _autoNavigating = false);
            widget.onShowNavBar?.call();
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
      useRootNavigator: true,
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
          realtime: widget.realtime,
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

  Future<bool> _voteOnPoll(FeedPost post, int optionId) async {
    try {
      final res = await http.post(
        postPollVoteEndpoint(post.id),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'option_id': optionId}),
      );
      if (res.statusCode == 401) { await widget.onLogout(); return false; }
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  void _openMoreSheet(FeedPost post) {
    widget.onHideNavBar?.call();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
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
                widget.onHideNavBar?.call();
                showReportPostSheet(
                  context,
                  postId: post.id,
                  token: widget.token,
                ).whenComplete(() => widget.onShowNavBar?.call());
              },
            ),
          ],
        ),
      ),
    ).whenComplete(() => widget.onShowNavBar?.call());
  }

  Widget _buildPostCard(FeedPost post, {Key? key}) {
    final interactive = widget.followEnabled;
    return FeedPostCard(
      key: key,
      post: post,
      token: widget.token,
      currentUser: widget.currentUser,
      followingAuthors: _followingAuthors,
      onFollowUser: interactive ? _followUser : null,
      onUnfollowUser: interactive ? _unfollowUser : null,
      likingEnabled: interactive,
      onLike: interactive ? () => _likePost(post) : () async => false,
      onSave: interactive ? () => _savePost(post) : () async => false,
      onShare: () async {
        bool shared = false;
        widget.onHideNavBar?.call();
        await showShareSheet(
          context: context,
          post: post,
          token: widget.token,
          currentUser: widget.currentUser,
          onLogout: widget.onLogout,
          onShared: () { shared = true; },
        );
        widget.onShowNavBar?.call();
        return shared;
      },
      onVote: interactive ? (optionId) => _voteOnPoll(post, optionId) : null,
      onMore: () => _openMoreSheet(post),
      onComment: () => widget.onPostTap(post),
      onProfileTap: () => widget.onOpenUserProfile(post.author),
      onOpenUserProfile: widget.onOpenUserProfile,
      onHideNavBar: widget.onHideNavBar,
      onShowNavBar: widget.onShowNavBar,
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

  Future<void> _loadOtherCityPosts() async {
    final profile = _profile;
    if (profile == null || _otherCityPostsLoading) return;
    if (mounted) setState(() => _otherCityPostsLoading = true);
    try {
      final res = await http.get(
        postsEndpoint(city: profile.city),
        headers: authGetHeaders(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final all = (decoded['posts'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FeedPost.fromJson)
            .toList();
        setState(() {
          _otherCityPosts = all.where((p) => p.author == profile.username).toList();
          _otherCityPostsLoading = false;
        });
      } else {
        setState(() { _otherCityPosts = []; _otherCityPostsLoading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _otherCityPosts ??= []; _otherCityPostsLoading = false; });
    }
  }

  void _openAvatarFullscreen(UserProfile profile) {
    if (profile.avatarUrl.isEmpty) return;
    final isSelf = profile.username == widget.currentUser.username;
    widget.onHideNavBar?.call();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, a1, a2) => _AvatarFullscreenPage(
          avatarUrl: profile.avatarUrl,
          username: profile.username,
          isSelf: isSelf,
          initialFollowing: _followingOverride ?? profile.isFollowing,
          onToggleFollow: isSelf ? null : _toggleFollow,
        ),
        transitionsBuilder: (_, anim, a2, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    ).then((_) => widget.onShowNavBar?.call());
  }

  Future<void> _openEditProfile() async {
    final profile = _profile;
    if (profile == null) return;

    widget.onHideNavBar?.call();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
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

  Future<void> _openUserList({int initialTab = 0}) async {
    final profile = _profile;
    if (profile == null || !mounted) return;
    widget.onHideNavBar?.call();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _UserListPage(
          profileUsername: profile.username,
          followerCount: profile.followers,
          followingCount: profile.following,
          currentUser: widget.currentUser,
          token: widget.token,
          themeMode: widget.themeMode,
          onSessionUpdated: widget.onSessionUpdated,
          onProfileRefresh: _load,
          onOpenProfile: widget.onOpenUserProfile,
          isOwn: profile.username == widget.currentUser.username,
          initialTab: initialTab,
          followEnabled: widget.followEnabled,
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
    final feedPosts = widget.posts.where((p) => p.author == profile.username).toList();
    final fetched = _otherCityPosts;
    final userPosts = widget.followEnabled
        ? feedPosts
        : ((fetched != null && fetched.isNotEmpty) ? fetched : feedPosts);
    return AbsorbPointer(
      absorbing: _autoNavigating,
      child: Scaffold(
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
        centerTitle: false,
        titleSpacing: 12,
        title: Text(
          profile.username,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isLight ? Colors.black : Colors.white,
          ),
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
        key: _nestedScrollKey,
        headerSliverBuilder: (_, _) => [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: (profile.avatarZoomable && profile.avatarUrl.isNotEmpty)
                            ? () => _openAvatarFullscreen(profile)
                            : null,
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                          foregroundImage: _dataUrlBytes(profile.avatarUrl) != null
                              ? ResizeImage(MemoryImage(_dataUrlBytes(profile.avatarUrl)!), width: 288)
                              : null,
                          child: _dataUrlBytes(profile.avatarUrl) == null
                              ? Text(
                                  initialFor(profile.username),
                                  style: TextStyle(color: isLight ? Colors.black : Colors.white, fontSize: 20),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  profile.fullName.isEmpty ? profile.username : profile.fullName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.black : Colors.white,
                                  ),
                                ),
                                if (profile.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified_rounded, size: 14, color: Color(0xff0095f6)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _Metric(label: 'posts', value: '${userPosts.length}', onTap: null),
                                _Metric(
                                  label: 'followers',
                                  value: '${profile.followers}',
                                  onTap: () => _openUserList(initialTab: 0),
                                ),
                                _Metric(
                                  label: 'following',
                                  value: '${profile.following}',
                                  onTap: () => _openUserList(initialTab: 1),
                                ),
                              ],
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
                      if (profile.bio.isNotEmpty) ...[
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
                                    if (widget.followEnabled) ...[
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
                                        child: PostShareIcon(color: isLight ? Colors.black : Colors.white, size: 18),
                                      ),
                                    ),
                                    ],
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
            (!widget.followEnabled && _otherCityPostsLoading)
                ? const Center(child: CircularProgressIndicator())
                : userPosts.isEmpty
                ? const CustomScrollView(slivers: [SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No posts yet.', style: TextStyle(color: Color(0xffb3b3b3)))))])
                : ListView.builder(
                    key: const PageStorageKey('posts'),
                    // ignore: deprecated_member_use
                    cacheExtent: _autoNavigating ? 30000.0 : null,
                    itemCount: userPosts.length,
                    itemBuilder: (_, i) {
                      final post = userPosts[i];
                      final key = _postKeys.putIfAbsent(post.id, () => GlobalKey());
                      Widget card = _buildPostCard(post, key: key);
                      if (post.id == _bouncePostId) {
                        card = _BounceHighlight(child: card);
                      }
                      return card;
                    },
                  ),
            // Tab 1: Liked
            _buildLikedTab(isOwn),
            // Tab 2: Saved
            _buildSavedTab(isOwn),
          ],
        ),
      ),
    )); // Scaffold + AbsorbPointer
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

// ── Instagram-style avatar fullscreen ────────────────────────────────────────

class _AvatarFullscreenPage extends StatefulWidget {
  const _AvatarFullscreenPage({
    required this.avatarUrl,
    required this.username,
    required this.isSelf,
    required this.initialFollowing,
    this.onToggleFollow,
  });
  final String avatarUrl;
  final String username;
  final bool isSelf;
  final bool initialFollowing;
  final Future<void> Function()? onToggleFollow;

  @override
  State<_AvatarFullscreenPage> createState() => _AvatarFullscreenPageState();
}

class _AvatarFullscreenPageState extends State<_AvatarFullscreenPage> {
  late bool _following = widget.initialFollowing;
  bool _toggling = false;

  ImageProvider _imageProvider() {
    final bytes = _dataUrlBytes(widget.avatarUrl);
    if (bytes != null) return MemoryImage(bytes);
    final url = widget.avatarUrl.startsWith('/')
        ? '$apiBaseUrl${widget.avatarUrl}'
        : widget.avatarUrl;
    return CachedNetworkImageProvider(url);
  }

  Future<void> _toggle() async {
    if (_toggling) return;
    setState(() { _toggling = true; _following = !_following; });
    try {
      await widget.onToggleFollow?.call();
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _imageProvider();
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Blur the underlying profile page (shows through via opaque: false route)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
            // Circle avatar + button
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Circle PFP
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(image: provider, fit: BoxFit.cover),
                    ),
                  ),
                  const Spacer(),
                  // Follow button (other users only)
                  if (!widget.isSelf)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      child: GestureDetector(
                        onTap: _toggle,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _following
                                ? Colors.transparent
                                : const Color(0xff3897f0),
                            borderRadius: BorderRadius.circular(14),
                            border: _following
                                ? Border.all(color: Colors.white70, width: 1.5)
                                : null,
                          ),
                          child: Center(
                            child: _toggling
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _following ? 'Following' : 'Follow',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BounceHighlight extends StatefulWidget {
  const _BounceHighlight({required this.child});
  final Widget child;
  @override
  State<_BounceHighlight> createState() => _BounceHighlightState();
}

class _BounceHighlightState extends State<_BounceHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 230),
  );
  late final Animation<double> _scale =
      Tween<double>(begin: 1.0, end: 1.025)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _ctrl.forward()
        .then((_) => _ctrl.reverse())
        .then((_) => _ctrl.forward())
        .then((_) => _ctrl.reverse());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      );
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
                          ? ResizeImage(MemoryImage(_dataUrlBytes(preview[i].avatarUrl)!), width: 288)
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
  const _AvatarPreview({required this.url, this.decodeWidth});

  final String url;

  /// Caps the decoded bitmap width (physical px). Sized to the display box so
  /// a full-res photo isn't decoded into a small thumbnail.
  final int? decodeWidth;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma > -1) {
        try {
          return Image.memory(
            base64Decode(url.substring(comma + 1)),
            fit: BoxFit.cover,
            cacheWidth: decodeWidth,
          );
        } catch (_) {}
      }
    }
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: imageCacheManager,
      fit: BoxFit.cover,
      memCacheWidth: decodeWidth,
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
                    foregroundImage: avatarBytes != null
                        ? ResizeImage(MemoryImage(avatarBytes), width: 288)
                        : null,
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
                                      child: _AvatarPreview(url: post.imageUrl, decodeWidth: 156),
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
    required this.profileUsername,
    required this.followerCount,
    required this.followingCount,
    required this.currentUser,
    required this.token,
    required this.themeMode,
    required this.onSessionUpdated,
    required this.onProfileRefresh,
    required this.onOpenProfile,
    required this.isOwn,
    this.initialTab = 0,
    this.followEnabled = true,
  });

  final String profileUsername;
  final int followerCount;
  final int followingCount;
  final UserProfile currentUser;
  final String token;
  final ThemeMode themeMode;
  final ValueChanged<AuthSession> onSessionUpdated;
  final Future<void> Function() onProfileRefresh;
  final ValueChanged<String> onOpenProfile;
  final bool isOwn;
  final int initialTab;
  final bool followEnabled;

  @override
  State<_UserListPage> createState() => _UserListPageState();
}

enum _SortMode { defaultOrder, newestFirst, oldestFirst }

class _UserListPageState extends State<_UserListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _followersSearch = TextEditingController();
  final _followingSearch = TextEditingController();
  String _followersQuery = '';
  String _followingQuery = '';
  _SortMode _sortMode = _SortMode.defaultOrder;

  List<UserProfile> _followers = [];
  List<UserProfile> _following = [];
  bool _followersLoading = true;
  bool _followingLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
    _loadFollowers();
    _loadFollowing();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _followersSearch.dispose();
    _followingSearch.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    final res = await http.get(
      followersEndpoint(widget.profileUsername),
      headers: authGetHeaders(widget.token),
    );
    if (!mounted || res.statusCode != 200) {
      if (mounted) setState(() => _followersLoading = false);
      return;
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final users = (decoded['users'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UserProfile.fromJson)
        .toList();
    setState(() {
      _followers = widget.isOwn
          ? users.map((u) => u.copyWith(followsYou: true)).toList()
          : users;
      _followersLoading = false;
    });
  }

  Future<void> _loadFollowing() async {
    final res = await http.get(
      followingEndpoint(widget.profileUsername),
      headers: authGetHeaders(widget.token),
    );
    if (!mounted || res.statusCode != 200) {
      if (mounted) setState(() => _followingLoading = false);
      return;
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    setState(() {
      _following = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList();
      _followingLoading = false;
    });
  }

  Future<void> _toggleFollow(UserProfile user) async {
    final res = await http.post(
      followEndpoint(user.username),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'follow': !user.isFollowing}),
    );
    if (res.statusCode != 200 || !mounted) return;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final updated =
        UserProfile.fromJson(decoded['user'] as Map<String, dynamic>);
    setState(() {
      final fi = _followers.indexWhere((u) => u.username == user.username);
      if (fi != -1) _followers[fi] = updated;
      final wi = _following.indexWhere((u) => u.username == user.username);
      if (wi != -1) _following[wi] = updated;
    });
    widget.onSessionUpdated(AuthSession(
      token: widget.token,
      user: UserProfile.fromJson(decoded['viewer'] as Map<String, dynamic>),
    ));
    await widget.onProfileRefresh();
  }

  List<UserProfile> _filterAndSort(List<UserProfile> list, String q) {
    var result = q.isEmpty
        ? List<UserProfile>.of(list)
        : list
            .where((u) =>
                u.username.toLowerCase().contains(q.toLowerCase()) ||
                u.fullName.toLowerCase().contains(q.toLowerCase()))
            .toList();
    switch (_sortMode) {
      case _SortMode.newestFirst:
        return result.reversed.toList();
      case _SortMode.oldestFirst:
        return result; // original API order = oldest first
      case _SortMode.defaultOrder:
        return result;
    }
  }

  void _showSortSheet(BuildContext context, bool isLight) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isLight ? Colors.white : const Color(0xff1e1e1e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isLight
                    ? const Color(0xffd0d0d0)
                    : const Color(0xff4a4a4a),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            for (final mode in _SortMode.values)
              ListTile(
                title: Text(
                  _sortLabel(mode),
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontWeight: _sortMode == mode
                        ? FontWeight.w700
                        : FontWeight.w400,
                    fontSize: 15,
                  ),
                ),
                trailing: _sortMode == mode
                    ? Icon(Icons.check,
                        color: isLight ? Colors.black : Colors.white, size: 20)
                    : null,
                onTap: () {
                  setState(() => _sortMode = mode);
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _sortLabel(_SortMode mode) => switch (mode) {
        _SortMode.defaultOrder => 'Default',
        _SortMode.newestFirst => 'Newest first',
        _SortMode.oldestFirst => 'Oldest first',
      };

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : const Color(0xff121212);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: isLight ? Colors.black : Colors.white),
        title: Text(
          widget.profileUsername,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: isLight ? Colors.black : Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: isLight ? Colors.black : Colors.white,
            unselectedLabelColor:
                isLight ? const Color(0xff8b95a3) : const Color(0xff666666),
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            indicator: UnderlineTabIndicator(
              borderSide: BorderSide(
                width: 2.0,
                color: isLight ? Colors.black : Colors.white,
              ),
              insets: EdgeInsets.zero,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: '${widget.followerCount} Followers'),
              Tab(text: '${widget.followingCount} Following'),
            ],
          ),
          Expanded(
            child: TabBarView(
        controller: _tabController,
        children: [
          _buildTab(
            loading: _followersLoading,
            users: _filterAndSort(_followers, _followersQuery),
            searchCtrl: _followersSearch,
            onSearch: (v) => setState(() => _followersQuery = v.trim()),
            query: _followersQuery,
            isLight: isLight,
          ),
          _buildTab(
            loading: _followingLoading,
            users: _filterAndSort(_following, _followingQuery),
            searchCtrl: _followingSearch,
            onSearch: (v) => setState(() => _followingQuery = v.trim()),
            query: _followingQuery,
            isLight: isLight,
          ),
        ],
            ),
          ), // Expanded
        ], // Column children
      ), // Column / body
    ); // Scaffold
  }

  Widget _buildTab({
    required bool loading,
    required List<UserProfile> users,
    required TextEditingController searchCtrl,
    required ValueChanged<String> onSearch,
    required String query,
    required bool isLight,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: TextField(
            controller: searchCtrl,
            onChanged: onSearch,
            style: TextStyle(
                color: isLight ? Colors.black : Colors.white, fontSize: 15),
            cursorColor: const Color(0xff3897f0),
            decoration: InputDecoration(
              filled: true,
              fillColor: isLight
                  ? const Color(0xffefefef)
                  : const Color(0xff1c1c1e),
              hintText: 'Search',
              hintStyle: TextStyle(
                  color: isLight
                      ? const Color(0xff737373)
                      : const Color(0xff8e8e8e),
                  fontSize: 15),
              prefixIcon: Icon(Icons.search_rounded,
                  color: isLight
                      ? const Color(0xff737373)
                      : const Color(0xff8e8e8e),
                  size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        // Sort row — Instagram style
        InkWell(
          onTap: () => _showSortSheet(context, isLight),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Row(
              children: [
                Text(
                  'Sort by ',
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  _sortLabel(_sortMode),
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(Icons.swap_vert_rounded,
                    size: 18,
                    color: isLight ? Colors.black : Colors.white),
              ],
            ),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : users.isEmpty
                  ? Center(
                      child: Text(
                        query.isEmpty ? 'No users yet.' : 'No results.',
                        style: TextStyle(
                            color: isLight
                                ? const Color(0xff8b95a3)
                                : const Color(0xff8f8f8f)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 4),
                      itemCount: users.length,
                      itemBuilder: (_, i) => _buildRow(users[i], isLight),
                    ),
        ),
      ],
    );
  }

  Widget _buildRow(UserProfile user, bool isLight) {
    final bytes = _dataUrlBytes(user.avatarUrl);
    final canToggle = user.username != widget.currentUser.username;
    final isFollowing = user.isFollowing;

    return GestureDetector(
      onTap: () => widget.onOpenProfile(user.username),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: isLight
                  ? const Color(0xffe6e9ef)
                  : const Color(0xff2a2a2a),
              foregroundImage: user.avatarUrl.isNotEmpty
                  ? ResizeImage(
                      bytes != null
                          ? MemoryImage(bytes) as ImageProvider
                          : CachedNetworkImageProvider(user.avatarUrl,
                              cacheManager: imageCacheManager),
                      width: 156) // 26px radius × 2 × 3.0 max DPR
                  : null,
              child: Text(initialFor(user.username),
                  style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.username,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (user.fullName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      user.fullName,
                      style: TextStyle(
                        color: isLight
                            ? const Color(0xff8b95a3)
                            : const Color(0xff8f8f8f),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (user.followsYou && !widget.isOwn) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Follows you',
                      style: TextStyle(
                        color: isLight
                            ? const Color(0xff8b95a3)
                            : const Color(0xff8f8f8f),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (canToggle && widget.followEnabled) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _toggleFollow(user),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isFollowing
                        ? (isLight
                            ? const Color(0xffefefef)
                            : const Color(0xff2a2a2a))
                        : (isLight ? Colors.black : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isFollowing
                        ? 'Following'
                        : (user.followsYou ? 'Follow Back' : 'Follow'),
                    style: TextStyle(
                      color: isFollowing
                          ? (isLight ? Colors.black : Colors.white)
                          : (isLight ? Colors.white : Colors.black),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
