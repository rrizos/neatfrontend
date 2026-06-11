import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import '../core/models.dart';

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
  });
  final String username;
  final UserProfile currentUser;
  final String token;
  final List<FeedPost> posts;
  final ValueChanged<String> onOpenUserProfile;
  final ValueChanged<FeedPost> onPostTap;
  final Future<void> Function() onLogout;
  final ValueChanged<AuthSession> onSessionUpdated;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null) return;
    final res = await http.post(
      followEndpoint(profile.username),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'follow': !profile.isFollowing}),
    );
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
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
      }
    }
  }

  Future<void> _openUserList({
    required String title,
    required Uri endpoint,
  }) async {
    final res = await http.get(endpoint, headers: authGetHeaders(widget.token));
    if (res.statusCode != 200) return;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final users = (decoded['users'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UserProfile.fromJson)
        .toList();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xff121212),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
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
                  if (users.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No users yet.',
                        style: TextStyle(color: Color(0xffb7b7b7)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: users.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xff262626)),
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final canToggle =
                              user.username != widget.currentUser.username;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xff2a2a2a),
                              child: Text(
                                initialFor(user.username),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              user.username,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              user.isFollowing
                                  ? 'Following you'
                                  : 'Not following yet',
                              style: const TextStyle(color: Color(0xffb7b7b7)),
                            ),
                            trailing: canToggle
                                ? TextButton(
                                    onPressed: () async {
                                      final res = await http.post(
                                        followEndpoint(user.username),
                                        headers: authJsonHeaders(widget.token),
                                        body: jsonEncode({
                                          'follow': !user.isFollowing,
                                        }),
                                      );
                                      if (res.statusCode != 200) return;
                                      if (!mounted) return;
                                      final decoded =
                                          jsonDecode(res.body)
                                              as Map<String, dynamic>;
                                      final updatedUser = UserProfile.fromJson(
                                        decoded['user'] as Map<String, dynamic>,
                                      );
                                      setSheetState(() {
                                        users[index] = updatedUser;
                                      });
                                      setState(() {
                                        _profile = UserProfile.fromJson(
                                          decoded['user']
                                              as Map<String, dynamic>,
                                        );
                                      });
                                      widget.onSessionUpdated(
                                        AuthSession(
                                          token: widget.token,
                                          user: UserProfile.fromJson(
                                            decoded['viewer']
                                                as Map<String, dynamic>,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      user.isFollowing ? 'Unfollow' : 'Follow',
                                    ),
                                  )
                                : null,
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onOpenUserProfile(user.username);
                            },
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (_loading || profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final userPosts = widget.posts
        .where((p) => p.author == profile.username)
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xff121212),
      appBar: AppBar(
        title: Text(profile.username),
        backgroundColor: const Color(0xff121212),
        actions: [
          IconButton(
            onPressed: () async {
              await widget.onLogout();
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: const Color(0xff2a2a2a),
                  child: Text(
                    initialFor(profile.username),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Metric(
                        label: 'posts',
                        value: '${userPosts.length}',
                        onTap: null,
                      ),
                      _Metric(
                        label: 'followers',
                        value: '${profile.followers}',
                        onTap: () => _openUserList(
                          title: 'Followers',
                          endpoint: followersEndpoint(profile.username),
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
                Text(
                  profile.fullName.isEmpty
                      ? profile.username
                      : profile.fullName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (profile.bio.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.bio,
                    style: const TextStyle(color: Color(0xffb3b3b3)),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: profile.username == widget.currentUser.username
                ? OutlinedButton(
                    onPressed: () {},
                    child: const Text('Edit profile'),
                  )
                : FilledButton(
                    onPressed: _toggleFollow,
                    child: Text(profile.isFollowing ? 'Following' : 'Follow'),
                  ),
          ),
          const Divider(height: 1, color: Color(0xff242424)),
          if (userPosts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No posts yet.',
                  style: TextStyle(color: Color(0xffb3b3b3)),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: userPosts.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xff242424)),
              itemBuilder: (context, index) {
                final post = userPosts[index];
                return InkWell(
                  onTap: () => widget.onPostTap(post),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xff2a2a2a),
                              child: Text(
                                initialFor(post.author),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    post.author,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${post.minutesAgo}m ago',
                                    style: const TextStyle(
                                      color: Color(0xff9c9c9c),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.more_horiz,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                        if (post.text.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            post.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.favorite_border,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 18),
                            const Icon(
                              Icons.mode_comment_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 18),
                            const Icon(
                              Icons.send_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.bookmark_border,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${post.likes} likes',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
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
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        Text(label, style: const TextStyle(color: Color(0xffb3b3b3))),
      ],
    );
    return onTap == null ? child : InkWell(onTap: onTap, child: child);
  }
}
