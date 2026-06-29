import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'models.dart';

class PostDeepLinkPage extends StatefulWidget {
  const PostDeepLinkPage({
    super.key,
    required this.postId,
    required this.themeMode,
  });

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
    final isLight = widget.themeMode == ThemeMode.light;
    final bg = isLight ? const Color(0xfff3f4f6) : const Color(0xff121212);
    final textColor = isLight ? Colors.black : Colors.white;
    final muted = isLight ? const Color(0xff6b7280) : const Color(0xff9ca3af);
    final accentColor = isLight ? const Color(0xff1479ff) : const Color(0xff4ea3ff);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xff1a1a1a),
        elevation: 0,
        title: Text(
          'neat',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(Uri.base.replace(path: '/')),
            child: Text(
              'Open App',
              style: TextStyle(color: accentColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: muted)))
              : _PostView(post: _post!, isLight: isLight, textColor: textColor, muted: muted),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PostView extends StatelessWidget {
  const _PostView({
    required this.post,
    required this.isLight,
    required this.textColor,
    required this.muted,
  });

  final FeedPost post;
  final bool isLight;
  final Color textColor;
  final Color muted;

  Uint8List? _bytes(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    try { return base64Decode(url.substring(comma + 1)); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final avatarBytes = _bytes(post.avatarUrl);
    final firstMedia = post.media.isNotEmpty ? post.media.first : null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Media
          if (firstMedia != null)
            AspectRatio(
              aspectRatio: 1,
              child: firstMedia.isVideo
                  ? _VideoBlock(url: firstMedia.url)
                  : _imageBlock(firstMedia.url),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isLight ? const Color(0xffe5e7eb) : const Color(0xff2a2a2a),
                      foregroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
                      child: avatarBytes == null
                          ? Text(
                              post.author.isNotEmpty ? post.author[0].toUpperCase() : '?',
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${post.author}',
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        if (post.city.isNotEmpty)
                          Text(post.city, style: TextStyle(color: muted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),

                // Text
                if (post.text.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(post.text, style: TextStyle(color: textColor, fontSize: 15, height: 1.4)),
                ],

                const SizedBox(height: 16),

                // Stats row
                Row(
                  children: [
                    Icon(Icons.favorite_rounded, size: 18, color: muted),
                    const SizedBox(width: 4),
                    Text('${post.likes}', style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 16),
                    Icon(Icons.chat_bubble_outline_rounded, size: 18, color: muted),
                    const SizedBox(width: 4),
                    Text('${post.comments.length}', style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageBlock(String url) {
    final bytes = _bytes(url);
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity);
    }
    return Image.network(url, fit: BoxFit.cover, width: double.infinity);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _VideoBlock extends StatefulWidget {
  const _VideoBlock({required this.url});
  final String url;

  @override
  State<_VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends State<_VideoBlock> {
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

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: ctrl.value.size.width,
              height: ctrl.value.size.height,
              child: VideoPlayer(ctrl),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
              ],
            ),
          ),
          Center(
            child: GestureDetector(
              onTap: () {
                ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                setState(() {});
              },
              child: AnimatedOpacity(
                opacity: ctrl.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
