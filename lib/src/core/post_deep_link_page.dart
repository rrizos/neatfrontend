import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'models.dart';

const _iosUrl = 'https://apps.apple.com/gr/app/neat-connect-with-your-city/id6748038152';
const _androidUrl = 'https://play.google.com/store/apps/details?id=gr.app.neat&hl=en';

Uint8List? _decodeDataUrl(String url) {
  if (!url.startsWith('data:')) return null;
  final i = url.indexOf(',');
  if (i < 0) return null;
  try { return base64Decode(url.substring(i + 1)); } catch (_) { return null; }
}

Future<void> _launch(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class PostDeepLinkPage extends StatefulWidget {
  const PostDeepLinkPage({super.key, required this.postId, required this.themeMode});
  final int postId;
  final ThemeMode themeMode;

  @override
  State<PostDeepLinkPage> createState() => _PostDeepLinkPageState();
}

class _PostDeepLinkPageState extends State<PostDeepLinkPage> {
  FeedPost? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(postDetailEndpoint(widget.postId));
      if (!mounted) return;
      if (res.statusCode == 404) {
        setState(() { _error = 'Post not found'; _loading = false; }); return;
      }
      if (res.statusCode != 200) {
        setState(() { _error = 'Could not load post'; _loading = false; }); return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() { _post = FeedPost.fromJson(json); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load post'; _loading = false; });
    }
  }

  void _openComments() {
    final post = _post;
    if (post == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(comments: post.comments),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0a0a0a),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: _TopBar(postId: widget.postId),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white54, fontSize: 15)))
                    : _PostContent(post: _post!, onCommentsTap: _openComments),
          ),
          _AppBanner(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.postId});
  final int postId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      color: const Color(0xff0a0a0a),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.asset('assets/neat_logo.png', width: 44, height: 44),
          ),
          const Spacer(),
          _OpenInAppBtn(postId: postId),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Open in app" button
// ─────────────────────────────────────────────────────────────────────────────

class _OpenInAppBtn extends StatelessWidget {
  const _OpenInAppBtn({required this.postId});
  final int postId;

  Future<void> _tap() async {
    // Try custom scheme first — works if app is installed and URL scheme registered
    final deepLink = 'neat://post/$postId';
    final uri = Uri.parse(deepLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    // Fallback: open web app root (user is already on web, so just go home)
    await launchUrl(Uri.base.replace(path: '/'), mode: LaunchMode.platformDefault);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xff1479ff),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new_rounded, color: Colors.white, size: 14),
            SizedBox(width: 6),
            Text(
              'Open in app',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post content (media + overlays)
// ─────────────────────────────────────────────────────────────────────────────

class _PostContent extends StatelessWidget {
  const _PostContent({required this.post, required this.onCommentsTap});
  final FeedPost post;
  final VoidCallback onCommentsTap;

  @override
  Widget build(BuildContext context) {
    final firstMedia = post.media.isNotEmpty ? post.media.first : null;
    final avatarBytes = _decodeDataUrl(post.avatarUrl);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Media ──────────────────────────────────────────────────────────
        if (firstMedia != null)
          firstMedia.isVideo
              ? _VideoMedia(url: firstMedia.url)
              : _ImageMedia(url: firstMedia.url)
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                post.text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, height: 1.45),
              ),
            ),
          ),

        // ── Bottom gradient ─────────────────────────────────────────────────
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 240,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
        ),

        // ── Author + text (bottom-left) ─────────────────────────────────────
        Positioned(
          left: 16, right: 72, bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: Colors.white24,
                    foregroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                    child: avatarBytes == null
                        ? Text(
                            post.author.isNotEmpty ? post.author[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('@${post.author}',
                            style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                            )),
                        if (post.city.isNotEmpty)
                          Text(post.city,
                              style: const TextStyle(
                                color: Colors.white70, fontSize: 11,
                                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                              )),
                      ],
                    ),
                  ),
                ],
              ),
              if (post.text.isNotEmpty && firstMedia != null) ...[
                const SizedBox(height: 8),
                Text(
                  post.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.35,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Right-side action column ────────────────────────────────────────
        Positioned(
          right: 12, bottom: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AvatarCircle(avatarBytes: avatarBytes, author: post.author),
              const SizedBox(height: 22),
              _ActionBtn(icon: Icons.favorite_rounded, count: post.likes, onTap: null),
              const SizedBox(height: 18),
              _ActionBtn(
                icon: Icons.chat_bubble_rounded,
                count: post.comments.length,
                onTap: onCommentsTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Author avatar (right column, non-interactive)
// ─────────────────────────────────────────────────────────────────────────────

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.avatarBytes, required this.author});
  final Uint8List? avatarBytes;
  final String author;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipOval(
        child: avatarBytes != null
            ? Image.memory(avatarBytes!, fit: BoxFit.cover)
            : ColoredBox(
                color: const Color(0xff2a2a2a),
                child: Center(
                  child: Text(
                    author.isNotEmpty ? author[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action button (right column)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.count, required this.onTap});
  final IconData icon;
  final int count;
  final VoidCallback? onTap;

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.2),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 5),
          Text(
            _fmt(count),
            style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comments bottom sheet (read-only)
// ─────────────────────────────────────────────────────────────────────────────

class _CommentsSheet extends StatelessWidget {
  const _CommentsSheet({required this.comments});
  final List<FeedComment> comments;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xff111111);
    const divider = Color(0xff222222);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 14),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: const Color(0xff3f3f46), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  Text(
                    '${comments.length} ${comments.length == 1 ? 'comment' : 'comments'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: divider),
            // Comments list
            Expanded(
              child: comments.isEmpty
                  ? const Center(child: Text('No comments yet', style: TextStyle(color: Colors.white38, fontSize: 14)))
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: comments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 20),
                      itemBuilder: (_, i) => _CommentItem(comment: comments[i], isReply: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentItem extends StatelessWidget {
  const _CommentItem({required this.comment, required this.isReply});
  final FeedComment comment;
  final bool isReply;

  @override
  Widget build(BuildContext context) {
    final avatarBytes = _decodeDataUrl(comment.avatarUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: isReply ? 14 : 17,
              backgroundColor: const Color(0xff2a2a2a),
              foregroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
              child: avatarBytes == null
                  ? Text(
                      comment.author.isNotEmpty ? comment.author[0].toUpperCase() : '?',
                      style: TextStyle(color: Colors.white, fontSize: isReply ? 10 : 12, fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${comment.author}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(comment.text,
                      style: const TextStyle(color: Color(0xffe0e0e0), fontSize: 14, height: 1.35)),
                  if (comment.likes > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.favorite_rounded, size: 12, color: Colors.white38),
                        const SizedBox(width: 3),
                        Text('${comment.likes}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // Replies
        if (comment.replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 44, top: 12),
            child: Column(
              children: comment.replies
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CommentItem(comment: r, isReply: true),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom app banner
// ─────────────────────────────────────────────────────────────────────────────

class _AppBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xff1a1a1a),
        border: Border(top: BorderSide(color: Color(0xff2a2a2a))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _StoreBtn(
                label: 'App Store',
                icon: Icons.apple,
                onTap: () => _launch(_iosUrl),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StoreBtn(
                label: 'Google Play',
                icon: Icons.android_rounded,
                onTap: () => _launch(_androidUrl),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreBtn extends StatelessWidget {
  const _StoreBtn({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xff1479ff),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Media widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ImageMedia extends StatelessWidget {
  const _ImageMedia({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUrl(url);
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.contain, width: double.infinity, height: double.infinity);
    }
    return Image.network(url, fit: BoxFit.contain, width: double.infinity, height: double.infinity);
  }
}

class _VideoMedia extends StatefulWidget {
  const _VideoMedia({required this.url});
  final String url;

  @override
  State<_VideoMedia> createState() => _VideoMediaState();
}

class _VideoMediaState extends State<_VideoMedia> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await ctrl.initialize();
      ctrl.setLooping(true);
      ctrl.setVolume(0);
      ctrl.play();
      ctrl.addListener(_update);
      if (!mounted) { ctrl.dispose(); return; }
      setState(() { _ctrl = ctrl; _ready = true; });
    } catch (_) {}
  }

  void _update() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _ctrl?.removeListener(_update);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _ctrl == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
      );
    }
    final ctrl = _ctrl!;
    final duration = ctrl.value.duration;
    final position = ctrl.value.position;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () { ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(); setState(() {}); },
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: ctrl.value.size.width,
              height: ctrl.value.size.height,
              child: VideoPlayer(ctrl),
            ),
          ),
          if (!ctrl.value.isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
              ),
            ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 2,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
              ),
              child: Slider(
                value: progress,
                onChanged: (v) => ctrl.seekTo(
                  Duration(milliseconds: (v * duration.inMilliseconds).round()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
