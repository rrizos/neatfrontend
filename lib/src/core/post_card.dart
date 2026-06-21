import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'icons.dart';
import 'models.dart';

// ── Shared helpers ────────────────────────────────────────────────────────────

final _avatarCache = <String, Uint8List?>{};

Uint8List? decodeAvatarUrl(String value) {
  if (!value.startsWith('data:')) return null;
  if (_avatarCache.containsKey(value)) return _avatarCache[value];
  final comma = value.indexOf(',');
  Uint8List? result;
  if (comma >= 0) {
    try {
      result = base64Decode(value.substring(comma + 1));
    } catch (_) {}
  }
  _avatarCache[value] = result;
  return result;
}

String postAge(int minutesAgo) {
  if (minutesAgo < 1) return 'just now';
  if (minutesAgo < 60) return '${minutesAgo}m';
  if (minutesAgo < 1440) return '${minutesAgo ~/ 60}h';
  if (minutesAgo < 10080) return '${minutesAgo ~/ 1440}d';
  if (minutesAgo < 43200) return '${minutesAgo ~/ 10080}w';
  if (minutesAgo < 525600) return '${minutesAgo ~/ 43200}mo';
  return '${minutesAgo ~/ 525600}y';
}

// ── PostShareIcon ─────────────────────────────────────────────────────────────

class PostShareIcon extends StatelessWidget {
  const PostShareIcon({super.key, required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _PostSharePainter(color)));
}

class _PostSharePainter extends CustomPainter {
  const _PostSharePainter(this.color);
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
    final s = (w - 2 * pad) / 24.0;
    Offset p(double x, double y) => Offset(pad + x * s, pad + y * s);
    final rearMid   = p(6,    12);
    final upperRear = p(3.27,  3.13);
    final nose      = p(21.5, 12);
    final lowerRear = p(3.27, 20.88);
    final foldEnd   = p(13.5, 12);
    canvas.drawPath(
      Path()
        ..moveTo(rearMid.dx, rearMid.dy)
        ..lineTo(upperRear.dx, upperRear.dy)
        ..lineTo(nose.dx, nose.dy)
        ..lineTo(lowerRear.dx, lowerRear.dy)
        ..close(),
      paint,
    );
    canvas.drawLine(rearMid, foldEnd, paint);
  }

  @override
  bool shouldRepaint(_PostSharePainter old) => old.color != color;
}

// ── PostAvatar ────────────────────────────────────────────────────────────────

class PostAvatar extends StatelessWidget {
  const PostAvatar({super.key, required this.username, required this.avatarUrl});
  final String username;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bytes = decodeAvatarUrl(avatarUrl);
    return CircleAvatar(
      backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
      foregroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Text(
              initialFor(username),
              style: TextStyle(color: isLight ? const Color(0xff444444) : Colors.white),
            )
          : null,
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _FeedMedia extends StatelessWidget {
  const _FeedMedia({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma > -1) {
        try {
          return Image.memory(base64Decode(url.substring(comma + 1)), fit: BoxFit.cover);
        } catch (_) {}
      }
    }
    return Image.network(url, fit: BoxFit.cover);
  }
}

class _FullscreenMediaViewer extends StatelessWidget {
  const _FullscreenMediaViewer({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: _FeedMedia(url: url),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LikersSheet extends StatefulWidget {
  const _LikersSheet({
    required this.postId,
    required this.token,
    required this.onOpenUserProfile,
  });
  final int postId;
  final String token;
  final ValueChanged<String> onOpenUserProfile;

  @override
  State<_LikersSheet> createState() => _LikersSheetState();
}

class _LikersSheetState extends State<_LikersSheet> {
  List<UserProfile>? _users;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        postLikersEndpoint(widget.postId),
        headers: authGetHeaders(widget.token),
      );
      debugPrint('[LikersSheet] status=${res.statusCode} body=${res.body}');
      if (!mounted) return;
      if (res.statusCode != 200) { setState(() => _error = true); return; }
      final body = jsonDecode(res.body);
      List<dynamic> raw;
      if (body is List) {
        raw = body;
      } else if (body is Map<String, dynamic>) {
        raw = (body['users'] ?? body['likers'] ?? body['results'] ?? const []) as List<dynamic>;
      } else {
        raw = const [];
      }
      setState(() => _users = raw.whereType<Map<String, dynamic>>().map(UserProfile.fromJson).toList());
    } catch (e) {
      debugPrint('[LikersSheet] error: $e');
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final users = _users;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) {
        if (_error) return const Center(child: Text('Could not load likes.'));
        if (users == null) return const Center(child: CircularProgressIndicator());
        if (users.isEmpty) return const Center(child: Text('No likes yet.'));
        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: users.length,
          itemBuilder: (_, i) {
            final u = users[i];
            final bytes = decodeAvatarUrl(u.avatarUrl);
            return ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                foregroundImage: bytes != null ? MemoryImage(bytes) : null,
                child: bytes == null
                    ? Text(u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.w600))
                    : null,
              ),
              title: Text(u.fullName.isNotEmpty ? u.fullName : u.username,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: u.fullName.isNotEmpty
                  ? Text('@${u.username}', style: const TextStyle(color: Color(0xffb3b3b3)))
                  : null,
              onTap: () { Navigator.of(context).pop(); widget.onOpenUserProfile(u.username); },
            );
          },
        );
      },
    );
  }
}

// ── FeedPostCard ──────────────────────────────────────────────────────────────

class FeedPostCard extends StatefulWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.token,
    required this.currentUser,
    required this.onLike,
    required this.onSave,
    required this.onShare,
    required this.onMore,
    required this.onComment,
    required this.onProfileTap,
    required this.onOpenUserProfile,
    this.onFollow,
    this.isFollowing = false,
  });

  final FeedPost post;
  final String token;
  final UserProfile currentUser;
  final Future<bool> Function() onLike;
  final Future<bool> Function() onSave;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final VoidCallback onComment;
  final VoidCallback onProfileTap;
  final ValueChanged<String> onOpenUserProfile;
  final VoidCallback? onFollow;
  final bool isFollowing;

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> {
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
  void didUpdateWidget(FeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    setState(() { _saved = !_saved; widget.post.saved = _saved; });
    final ok = await widget.onSave();
    if (!ok && mounted) {
      setState(() { _saved = wasSaved; widget.post.saved = wasSaved; });
    }
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) => _FullscreenMediaViewer(url: widget.post.imageUrl),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _openLikers() {
    if (_likes == 0) return;
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff141414),
      builder: (_) => _LikersSheet(
        postId: widget.post.id,
        token: widget.token,
        onOpenUserProfile: widget.onOpenUserProfile,
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
                    child: PostAvatar(username: widget.post.author, avatarUrl: widget.post.avatarUrl),
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
                            postAge(widget.post.minutesAgo),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    icon: Icon(Icons.more_horiz_rounded,
                        color: isLight ? Colors.black : Colors.white, size: 22),
                  ),
                ],
              ),
            ),
            if (widget.post.text.isNotEmpty)
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
              GestureDetector(
                onTap: () => _openFullscreen(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 1.08,
                      child: _FeedMedia(url: widget.post.imageUrl),
                    ),
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
                      _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: _liked ? Colors.red : (isLight ? Colors.black : Colors.white),
                      size: 28,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onComment,
                    icon: CommentBubbleIcon(color: isLight ? Colors.black : Colors.white, size: 25),
                  ),
                  IconButton(
                    onPressed: widget.onShare,
                    icon: PostShareIcon(color: isLight ? Colors.black : Colors.white, size: 27),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _handleSave,
                    icon: Icon(
                      _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
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
                  GestureDetector(
                    onTap: _openLikers,
                    child: Text(
                      '$_likes likes',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: widget.onComment,
                    child: Text(
                      widget.post.comments.isEmpty
                          ? 'Add a comment...'
                          : 'View ${widget.post.comments.length} comments',
                      style: const TextStyle(color: Color(0xffb3b3b3), fontSize: 13),
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
