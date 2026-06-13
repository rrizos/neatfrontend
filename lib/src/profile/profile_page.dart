import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../messages/messages_page.dart';

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
  });
  final String username;
  final UserProfile currentUser;
  final String token;
  final List<FeedPost> posts;
  final ValueChanged<String> onOpenUserProfile;
  final ValueChanged<FeedPost> onPostTap;
  final Future<void> Function() onLogout;
  final ValueChanged<AuthSession> onSessionUpdated;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserProfile? _profile;
  bool _loading = true;
  final ImagePicker _imagePicker = ImagePicker();

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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationPage(
          token: widget.token,
          currentUsername: widget.currentUser.username,
          conversationId: conversation.id,
          otherUsername: conversation.otherUser,
          otherFullName: conversation.otherFullName,
          onLogout: widget.onLogout,
        ),
      ),
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

  Future<void> _openEditProfile() async {
    final profile = _profile;
    if (profile == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: widget.themeMode == ThemeMode.light
          ? const Color(0xfff3f4f6)
          : const Color(0xff111111),
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
  }

  Future<void> _openUserList({
    required String title,
    required Uri endpoint,
  }) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
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
      backgroundColor: isLight ? const Color(0xfff3f4f6) : const Color(0xff121212),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (users.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No users yet.',
                        style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xffb7b7b7)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: users.length,
                            separatorBuilder: (_, _) =>
                            Divider(height: 1, color: isLight ? const Color(0xffd9dee6) : const Color(0xff262626)),
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final canToggle =
                              user.username != widget.currentUser.username;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                              child: Text(
                                initialFor(user.username),
                                style: TextStyle(color: isLight ? Colors.black : Colors.white),
                              ),
                            ),
                            title: Text(
                              user.username,
                              style: TextStyle(color: isLight ? Colors.black : Colors.white),
                            ),
                            subtitle: Text(
                              user.isFollowing
                                  ? 'Following you'
                                  : 'Not following yet',
                              style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xffb7b7b7)),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final profile = _profile;
    if (_loading || profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final userPosts = widget.posts
        .where((p) => p.author == profile.username)
        .toList();
    return Scaffold(
      backgroundColor: isLight ? const Color(0xfff3f4f6) : const Color(0xff121212),
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
          IconButton(
            onPressed: () async {
              await widget.onLogout();
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isLight ? Colors.black : Colors.white,
                  ),
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: profile.username == widget.currentUser.username
                ? OutlinedButton(
                    onPressed: _openEditProfile,
                    child: const Text('Edit profile'),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _toggleFollow,
                          child: Text(
                            profile.isFollowing ? 'Following' : 'Follow',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 42,
                        width: 42,
                        child: OutlinedButton(
                          onPressed: _startDirectMessage,
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Icon(Icons.send_outlined, size: 18),
                        ),
                      ),
                    ],
                  ),
          ),
          Divider(height: 1, color: isLight ? const Color(0xffd9dee6) : const Color(0xff242424)),
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
                  Divider(height: 1, color: isLight ? const Color(0xffd9dee6) : const Color(0xff242424)),
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
                              foregroundImage:
                                  post.author == profile.username &&
                                          _dataUrlBytes(profile.avatarUrl) !=
                                              null
                                      ? MemoryImage(
                                          _dataUrlBytes(profile.avatarUrl)!,
                                        )
                                      : null,
                              child:
                                  post.author == profile.username &&
                                          _dataUrlBytes(profile.avatarUrl) !=
                                              null
                                      ? null
                                      : Text(
                                          initialFor(post.author),
                                          style: TextStyle(
                                            color: isLight ? Colors.black : Colors.white,
                                          ),
                                        ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    post.author,
                                    style: TextStyle(
                                      color: isLight ? Colors.black : Colors.white,
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
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_horiz,
                                color: Colors.white,
                                size: 20,
                              ),
                              onSelected: (value) async {
                                if (value == 'delete') {
                                  await _deletePost(post);
                                }
                              },
                              itemBuilder: (context) => [
                                if (post.author == widget.currentUser.username)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Delete post',
                                      style: TextStyle(color: Color(0xfff66c6c)),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        if (post.text.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            post.text,
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontSize: 15.5,
                                height: 1.4,
                              ),
                          ),
                        ],
                        if (post.comments.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...post.comments.take(2).map(
                                (comment) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _CommentAvatar(
                                        username: comment.author,
                                        avatarUrl: comment.avatarUrl,
                                        radius: 13,
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
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              comment.text,
                                              style: TextStyle(
                                                color: isLight ? const Color(0xff444444) : Colors.white,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                        if (post.imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: AspectRatio(
                              aspectRatio: 1.08,
                              child: _AvatarPreview(url: post.imageUrl),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.favorite_border,
                              color: isLight ? Colors.black : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 18),
                            Icon(
                              Icons.mode_comment_outlined,
                              color: isLight ? Colors.black : Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 18),
                            Icon(
                              Icons.send_outlined,
                              color: isLight ? Colors.black : Colors.white,
                              size: 20,
                            ),
                            const Spacer(),
                            Icon(
                              Icons.bookmark_border,
                              color: isLight ? Colors.black : Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${post.likes} likes',
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
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

class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({
    required this.username,
    required this.avatarUrl,
    required this.radius,
  });

  final String username;
  final String avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bytes = _dataUrlBytes(avatarUrl);
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? const Color(0xffe6e9ef)
          : const Color(0xff2a2a2a),
      foregroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Text(
              initialFor(username),
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.light
                    ? Colors.black
                    : Colors.white,
              ),
            )
          : null,
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

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
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
    return Image.network(url, fit: BoxFit.cover);
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

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _nameController = TextEditingController(text: widget.profile.fullName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _cityController = TextEditingController(text: widget.profile.city);
    _avatarUrl = widget.profile.avatarUrl;
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
        }),
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() => _saving = false);
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final updated = UserProfile.fromJson(
        decoded['user'] as Map<String, dynamic>,
      );
      widget.onSaved(updated);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarBytes = _dataUrlBytes(_avatarUrl);
    return SafeArea(
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
            ),
            const SizedBox(height: 12),
            _EditorField(
              controller: _bioController,
              label: 'Bio',
              maxLines: 4,
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
                  value: widget.themeMode == ThemeMode.light,
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
    );
  }
}
