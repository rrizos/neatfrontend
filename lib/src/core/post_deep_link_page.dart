import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'http_client.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import 'api.dart';
import 'link_preview.dart';
import 'media_cache.dart';
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
      final l10n = AppLocalizations.of(context);
      if (res.statusCode == 404) {
        setState(() { _error = l10n.postNotFound; _loading = false; }); return;
      }
      if (res.statusCode != 200) {
        setState(() { _error = l10n.couldNotLoadPost; _loading = false; }); return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() { _post = FeedPost.fromJson(json); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = AppLocalizations.of(context).couldNotLoadPost; _loading = false; });
    }
  }

  void _openComments() {
    final post = _post;
    if (post == null) return;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(comments: post.comments),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0a0a0a),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))
          : _error != null
              ? _ErrorBody(error: _error!)
              : _PostBody(post: _post!, onCommentsTap: _openComments),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error state
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _Header(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 15)),
              ),
            ),
          ),
          _DownloadSection(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main scrollable body
// ─────────────────────────────────────────────────────────────────────────────

class _PostBody extends StatelessWidget {
  const _PostBody({required this.post, required this.onCommentsTap});
  final FeedPost post;
  final VoidCallback onCommentsTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Header()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _PostCard(post: post, onCommentsTap: onCommentsTap),
            ),
          ),
          SliverToBoxAdapter(child: _DownloadSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Branded header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/neat_logo.png', width: 38, height: 38),
          ),
          const SizedBox(width: 10),
          const Text(
            'Neat',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          _GetAppButton(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Get the app" button (top-right)
// ─────────────────────────────────────────────────────────────────────────────

class _GetAppButton extends StatelessWidget {
  Future<void> _tap() async {
    // Try custom scheme — works if app happens to be installed after all
    final deepLink = Uri.parse('neat://post/0');
    if (await canLaunchUrl(deepLink)) {
      // Has the app: this shouldn't normally show for app users but handle gracefully
      return;
    }
    // iOS vs Android: check platform
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    await _launch(isIos ? _iosUrl : _androidUrl);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xff1479ff),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Get the app',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post card
// ─────────────────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onCommentsTap});
  final FeedPost post;
  final VoidCallback onCommentsTap;

  @override
  Widget build(BuildContext context) {
    final avatarBytes = _decodeDataUrl(post.avatarUrl);
    final firstMedia = post.media.isNotEmpty ? post.media.first : null;
    final linkPreview = post.linkPreview;
    final hasMedia = firstMedia != null ||
        (linkPreview != null && linkPreview.imageUrl.isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff141414),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xff272727), width: 0.8),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Author row ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xff2a2a2a),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: avatarBytes != null
                      ? Image.memory(avatarBytes, fit: BoxFit.cover)
                      : Center(
                          child: Text(
                            post.author.isNotEmpty ? post.author[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${post.author}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (post.city.isNotEmpty)
                        Text(
                          post.city,
                          style: const TextStyle(
                            color: Color(0xff888888),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                // Neat logo badge
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset('assets/neat_logo.png', width: 24, height: 24),
                ),
              ],
            ),
          ),

          // ── Caption (if present and there's media) ─────────────────────────
          if (post.text.isNotEmpty && hasMedia)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                post.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xffe8e8e8),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),

          // ── Media ──────────────────────────────────────────────────────────
          if (firstMedia != null)
            _MediaBlock(media: firstMedia)
          else if (linkPreview != null && linkPreview.imageUrl.isNotEmpty)
            _LinkBlock(preview: linkPreview)
          else if (post.text.isNotEmpty)
            // Text-only post: show the text big and centred inside the card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              color: const Color(0xff1a1a1a),
              child: Text(
                post.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ),

          // ── Counts row ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: null,
                  child: Row(
                    children: [
                      const Icon(Icons.favorite_rounded, color: Color(0xff888888), size: 17),
                      const SizedBox(width: 5),
                      Text(
                        _fmt(post.likes),
                        style: const TextStyle(color: Color(0xff888888), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: onCommentsTap,
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xff888888), size: 17),
                      const SizedBox(width: 5),
                      Text(
                        _fmt(post.comments.length),
                        style: const TextStyle(color: Color(0xff888888), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Media block (image or video, contained within the card)
// ─────────────────────────────────────────────────────────────────────────────

class _MediaBlock extends StatelessWidget {
  const _MediaBlock({required this.media});
  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: media.isVideo
          ? _VideoMedia(url: media.url)
          : _ImageMedia(url: media.url),
    );
  }
}

class _LinkBlock extends StatelessWidget {
  const _LinkBlock({required this.preview});
  final LinkPreviewData preview;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openLink(preview.resolvedUrl),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              preview.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xff1a1a1a)),
            ),
            if (preview.isVideo)
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 3),
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Download CTA section
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        decoration: BoxDecoration(
          color: const Color(0xff141414),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xff272727), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Join your city\'s conversation',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Neat is where your city talks — local posts, local news, local people.',
              style: TextStyle(
                color: Color(0xff888888),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
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
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xff1479ff),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 17),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
    const bg = Color(0xff0f0f0f);
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
                decoration: BoxDecoration(
                  color: const Color(0xff3f3f46),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(ctx).commentsCount(comments.length),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
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
                  ? Center(
                      child: Text(
                        AppLocalizations.of(ctx).noCommentsYet,
                        style: const TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    )
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isReply ? 10 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${comment.author}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.text,
                    style: const TextStyle(
                      color: Color(0xffe0e0e0),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  if (comment.likes > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.favorite_rounded, size: 12, color: Colors.white38),
                        const SizedBox(width: 3),
                        Text(
                          '${comment.likes}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
// Media widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ImageMedia extends StatelessWidget {
  const _ImageMedia({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final decodeWidth =
        (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
            .round();
    final bytes = _decodeDataUrl(url);
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: double.infinity, cacheWidth: decodeWidth);
    }
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: imageCacheManager,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: decodeWidth,
      fadeInDuration: Duration.zero,
    );
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
      final cached = kIsWeb ? null : await getCachedVideoFile(widget.url);
      final ctrl = cached != null
          ? VideoPlayerController.file(cached)
          : VideoPlayerController.networkUrl(Uri.parse(widget.url));
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
        color: Color(0xff1a1a1a),
        child: Center(
          child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2),
        ),
      );
    }
    final ctrl = _ctrl!;
    final duration = ctrl.value.duration;
    final position = ctrl.value.position;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () {
        ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
        setState(() {});
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black, child: SizedBox.expand()),
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: ctrl.value.size.width,
                height: ctrl.value.size.height,
                child: VideoPlayer(ctrl),
              ),
            ),
          ),
          if (!ctrl.value.isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
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
