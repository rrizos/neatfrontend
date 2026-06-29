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
        setState(() { _error = 'Post not found'; _loading = false; });
        return;
      }
      if (res.statusCode != 200) {
        setState(() { _error = 'Could not load post'; _loading = false; });
        return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() { _post = FeedPost.fromJson(json); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load post'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0a0a0a),
      body: Column(
        children: [
          // Top bar
          SafeArea(
            bottom: false,
            child: _TopBar(),
          ),
          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.white54, fontSize: 15)),
                      )
                    : _PostContent(post: _post!),
          ),
          // App download banner
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
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: const Color(0xff0a0a0a),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Image.asset('assets/neat_logo.png', width: 32, height: 32),
          const SizedBox(width: 8),
          const Text(
            'neat',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main post content (media + overlays)
// ─────────────────────────────────────────────────────────────────────────────

class _PostContent extends StatelessWidget {
  const _PostContent({required this.post});
  final FeedPost post;

  static Uint8List? _bytes(String url) {
    if (!url.startsWith('data:')) return null;
    final i = url.indexOf(',');
    if (i < 0) return null;
    try { return base64Decode(url.substring(i + 1)); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final firstMedia = post.media.isNotEmpty ? post.media.first : null;
    final avatarBytes = _bytes(post.avatarUrl);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Media ──────────────────────────────────────────────────────────
        if (firstMedia != null)
          firstMedia.isVideo
              ? _VideoMedia(url: firstMedia.url)
              : _ImageMedia(url: firstMedia.url)
        else
          // Text-only post: dark card centred
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                post.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ),

        // ── Bottom gradient ─────────────────────────────────────────────────
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
        ),

        // ── Author + text (bottom-left) ─────────────────────────────────────
        Positioned(
          left: 16, right: 72, bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Author row
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    foregroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                    child: avatarBytes == null
                        ? Text(
                            post.author.isNotEmpty ? post.author[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${post.author}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                        ),
                      ),
                      if (post.city.isNotEmpty)
                        Text(
                          post.city,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                          ),
                        ),
                    ],
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
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.3,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Right-side action column ────────────────────────────────────────
        Positioned(
          right: 12, bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionBtn(
                icon: Icons.favorite_rounded,
                count: post.likes,
                color: Colors.white,
              ),
              const SizedBox(height: 20),
              _ActionBtn(
                icon: Icons.chat_bubble_rounded,
                count: post.comments.length,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action button (right column)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.count, required this.color});
  final IconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 4),
        Text(
          _fmt(count),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
        ),
      ],
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom app banner (TikTok style)
// ─────────────────────────────────────────────────────────────────────────────

class _AppBanner extends StatelessWidget {
  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -2))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Neat logo + text
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/neat_logo.png', width: 44, height: 44),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Neat',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black)),
                  Text('Connect with your city',
                      style: TextStyle(fontSize: 12, color: Color(0xff6b7280))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Store buttons
            _StoreBtn(
              label: 'App Store',
              icon: Icons.apple,
              onTap: () => _open(_iosUrl),
            ),
            const SizedBox(width: 8),
            _StoreBtn(
              label: 'Google Play',
              icon: Icons.android_rounded,
              onTap: () => _open(_androidUrl),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
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
    if (url.startsWith('data:')) {
      final i = url.indexOf(',');
      try {
        final bytes = base64Decode(url.substring(i + 1));
        return Image.memory(bytes, fit: BoxFit.contain, width: double.infinity, height: double.infinity);
      } catch (_) {}
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
  void initState() {
    super.initState();
    _init();
  }

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
      onTap: () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(),
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
          // Pause indicator
          if (!ctrl.value.isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
              ),
            ),
          // Seek bar at bottom
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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
