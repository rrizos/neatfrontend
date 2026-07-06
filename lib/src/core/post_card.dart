import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'api.dart';
import 'icons.dart';
import 'media_cache.dart';
import 'models.dart';

// ── Shared helpers ────────────────────────────────────────────────────────────

// Persists mute preference across feed and fullscreen players.
final _globalMuted = ValueNotifier<bool>(true);

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

// Temp-file cache so the same video data URL isn't decoded + written twice.
final _videoTempCache = <int, String>{};

class _FeedMedia extends StatelessWidget {
  const _FeedMedia({required this.url, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma > -1) {
        try {
          return Image.memory(
            base64Decode(url.substring(comma + 1)),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
          );
        } catch (_) {}
      }
    }
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: imageCacheManager,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: Duration.zero,
      placeholder: (context, _) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: isLight ? const Color(0xfff0f0f0) : const Color(0xff1e1e1e),
          child: const Center(child: CircularProgressIndicator()),
        );
      },
      errorWidget: (context, _, _) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: isLight ? const Color(0xfff0f0f0) : const Color(0xff1e1e1e),
        );
      },
    );
  }
}

// ── Video player widget ───────────────────────────────────────────────────────
// Feed mode: auto-plays muted, tap opens fullscreen.
// Fullscreen mode: auto-plays muted, tap toggles controls overlay with
// play/pause, seek bar, time counter, and mute button.

class _FeedVideoPlayer extends StatefulWidget {
  const _FeedVideoPlayer({required this.url, this.onTap, this.fullscreen = false, this.onDoubleTap});
  final String url;
  final VoidCallback? onTap; // feed: opens fullscreen; null in fullscreen mode
  final bool fullscreen;
  final VoidCallback? onDoubleTap;

  @override
  State<_FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<_FeedVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;
  bool _muted = _globalMuted.value;
  bool _showControls = false;
  Timer? _hideTimer;

  // Video is only fetched/decoded once it's actually about to be on screen,
  // and playback is suspended while scrolled away — this keeps the feed from
  // downloading or decoding videos the user never actually looks at.
  final _visibilityKey = UniqueKey();
  bool _initStarted = false;
  bool _autoPaused = false;

  @override
  void initState() {
    super.initState();
    _globalMuted.addListener(_onGlobalMuteChanged);
  }

  void _onGlobalMuteChanged() {
    final newMuted = _globalMuted.value;
    if (_muted == newMuted) return;
    setState(() => _muted = newMuted);
    _ctrl?.setVolume(newMuted ? 0 : 1);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!_initStarted && info.visibleFraction > 0) {
      _initStarted = true;
      _init();
      return;
    }
    final ctrl = _ctrl;
    if (ctrl == null || !_ready) return;
    if (info.visibleFraction < 0.1) {
      if (ctrl.value.isPlaying) {
        _autoPaused = true;
        ctrl.pause();
      }
    } else if (_autoPaused) {
      _autoPaused = false;
      ctrl.play();
    }
  }

  Future<void> _init() async {
    try {
      VideoPlayerController ctrl;
      final url = widget.url;
      if (url.startsWith('data:') && !kIsWeb) {
        final key = url.hashCode;
        var path = _videoTempCache[key];
        if (path == null || !File(path).existsSync()) {
          final comma = url.indexOf(',');
          final bytes = base64Decode(url.substring(comma + 1));
          final dir = await getTemporaryDirectory();
          path = '${dir.path}/neatv_$key.mp4';
          await File(path).writeAsBytes(bytes);
          _videoTempCache[key] = path;
        }
        ctrl = VideoPlayerController.file(File(path));
      } else {
        // Cache the video to disk once so scrolling away and back (or
        // reopening the same post) replays from local storage instead of
        // re-streaming from the server every time.
        final cached = await getCachedVideoFile(url);
        ctrl = cached != null
            ? VideoPlayerController.file(cached)
            : VideoPlayerController.networkUrl(Uri.parse(url));
      }
      await ctrl.initialize();
      ctrl.setLooping(true);
      ctrl.setVolume(_muted ? 0 : 1);
      ctrl.play();
      ctrl.addListener(_onVideoUpdate);
      if (!mounted) { ctrl.dispose(); return; }
      setState(() { _ctrl = ctrl; _ready = true; });
    } catch (e) {
      debugPrint('[VideoPlayer] failed to load ${widget.url}: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onVideoUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _globalMuted.removeListener(_onGlobalMuteChanged);
    _hideTimer?.cancel();
    _ctrl?.removeListener(_onVideoUpdate);
    _ctrl?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _globalMuted.value = _muted;
    _ctrl?.setVolume(_muted ? 0 : 1);
  }

  void _togglePlayPause() {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    _resetHideTimer();
    setState(() {});
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onTap() {
    if (!widget.fullscreen) {
      widget.onTap?.call();
      return;
    }
    if (_showControls) {
      _togglePlayPause();
    } else {
      _showControlsTemporarily();
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_failed) {
      return GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 36),
          ),
        ),
      );
    }
    if (!_ready || _ctrl == null) {
      return GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
          ),
        ),
      );
    }

    final ctrl = _ctrl!;
    final duration = ctrl.value.duration;
    final position = ctrl.value.position;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final isPlaying = ctrl.value.isPlaying;

    return GestureDetector(
      onTap: _onTap,
      onDoubleTap: widget.onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video frame
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: ctrl.value.size.width,
              height: ctrl.value.size.height,
              child: VideoPlayer(ctrl),
            ),
          ),

          // Mute button — in fullscreen sits left of the X button, in feed top-right
          Positioned(
            top: widget.fullscreen
                ? MediaQuery.of(context).padding.top + 12
                : 10,
            right: widget.fullscreen ? 62 : 10,
            child: GestureDetector(
              onTap: _toggleMute,
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: EdgeInsets.all(widget.fullscreen ? 8 : 7),
                child: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: widget.fullscreen ? 22 : 16,
                ),
              ),
            ),
          ),

          // Controls overlay (fullscreen only)
          if (widget.fullscreen && (_showControls || kIsWeb)) ...[
            // Semi-transparent scrim at bottom
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                height: 90,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),
            // Play/pause centre button
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            ),
            // Seek bar + time at bottom
            Positioned(
              left: 16, right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmtDuration(position),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _fmtDuration(duration),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Seek slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white38,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: (v) {
                        final target = Duration(milliseconds: (v * duration.inMilliseconds).round());
                        ctrl.seekTo(target);
                        _resetHideTimer();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Feed-mode: small play indicator in centre when paused
          if (!widget.fullscreen && !isPlaying)
            Center(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Navigation arrow used in both carousel and fullscreen ─────────────────────

class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.left, required this.onTap});
  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? 10 : null,
      right: left ? null : 10,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(6),
            child: Icon(
              left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ── In-feed media carousel (images + videos, max 4) ──────────────────────────

class _PostMediaCarousel extends StatefulWidget {
  const _PostMediaCarousel({required this.media, required this.onTap, this.onDoubleTap});
  final List<MediaItem> media;
  final ValueChanged<int> onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<_PostMediaCarousel> {
  final _pageCtrl = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Widget _buildPage(MediaItem item, int index) {
    if (item.isVideo) {
      return _FeedVideoPlayer(
        url: item.url,
        onTap: () => widget.onTap(index),
        onDoubleTap: widget.onDoubleTap,
      );
    }
    return GestureDetector(
      onTap: () => widget.onTap(index),
      onDoubleTap: widget.onDoubleTap,
      child: _FeedMedia(url: item.url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final single = widget.media.length == 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                  children: [
                    if (single)
                      _buildPage(widget.media.first, 0)
                    else
                      PageView.builder(
                        controller: _pageCtrl,
                        itemCount: widget.media.length,
                        onPageChanged: (i) => setState(() => _current = i),
                        itemBuilder: (_, i) => _buildPage(widget.media[i], i),
                      ),
                  if (!single) ...[
                    // Counter badge
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          '${_current + 1}/${widget.media.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (_current > 0)
                      _NavArrow(
                        left: true,
                        onTap: () => _pageCtrl.previousPage(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeInOut,
                        ),
                      ),
                    if (_current < widget.media.length - 1)
                      _NavArrow(
                        left: false,
                        onTap: () => _pageCtrl.nextPage(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeInOut,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!single) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.media.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _current ? 8 : 5,
                height: i == _current ? 8 : 5,
                decoration: BoxDecoration(
                  color: i == _current
                      ? (isLight ? Colors.black : Colors.white)
                      : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Fullscreen media viewer (swipeable, images + videos) ─────────────────────

class _FullscreenMediaViewer extends StatefulWidget {
  const _FullscreenMediaViewer({required this.media, required this.initialIndex});
  final List<MediaItem> media;
  final int initialIndex;

  @override
  State<_FullscreenMediaViewer> createState() => _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<_FullscreenMediaViewer> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.media.length == 1;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: widget.media.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final item = widget.media[i];
              if (item.isVideo) {
                return _FeedVideoPlayer(url: item.url, fullscreen: true);
              }
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(child: _FeedMedia(url: item.url, fit: BoxFit.contain)),
              );
            },
          ),
          // Close button
          Positioned(
            top: topPad + 12,
            right: 16,
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
          if (!single) ...[
            if (_current > 0)
              _NavArrow(
                left: true,
                onTap: () => _ctrl.previousPage(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOut,
                ),
              ),
            if (_current < widget.media.length - 1)
              _NavArrow(
                left: false,
                onTap: () => _ctrl.nextPage(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOut,
                ),
              ),
            Positioned(
              bottom: botPad + 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.media.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _current ? 8 : 5,
                    height: i == _current ? 8 : 5,
                    decoration: BoxDecoration(
                      color: i == _current ? Colors.white : Colors.white54,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LikersSheet extends StatefulWidget {
  const _LikersSheet({
    required this.postId,
    required this.token,
    required this.currentUsername,
    required this.followingAuthors,
    this.followerAuthors = const {},
    this.onFollow,
    required this.onUnfollow,
    required this.onOpenUserProfile,
  });
  final int postId;
  final String token;
  final String currentUsername;
  final Set<String> followingAuthors;
  final Set<String> followerAuthors;
  final Future<void> Function(String)? onFollow;
  final Future<void> Function(String) onUnfollow;
  final ValueChanged<String> onOpenUserProfile;

  @override
  State<_LikersSheet> createState() => _LikersSheetState();
}

class _LikersSheetState extends State<_LikersSheet> {
  List<UserProfile>? _users;
  bool _error = false;
  late Set<String> _following;

  @override
  void initState() {
    super.initState();
    _following = Set.of(widget.followingAuthors);
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        postLikersEndpoint(widget.postId),
        headers: authGetHeaders(widget.token),
      );
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
      if (mounted) setState(() => _error = true);
    }
  }

  void _toggleFollow(String username) {
    if (widget.onFollow == null) return;
    if (_following.contains(username)) {
      setState(() => _following.remove(username));
      widget.onUnfollow(username);
    } else {
      setState(() => _following.add(username));
      widget.onFollow!(username);
    }
  }

  void _openProfile(String username) {
    widget.onOpenUserProfile(username);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : const Color(0xff111111);
    final textColor = isLight ? Colors.black : Colors.white;
    final users = _users;

    Widget body;
    if (_error) {
      body = const Center(child: Text('Could not load likes.'));
    } else if (users == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (users.isEmpty) {
      body = const Center(
        child: Text('No likes yet.', style: TextStyle(color: Color(0xffb3b3b3))),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        itemCount: users.length,
        itemBuilder: (_, i) {
          final u = users[i];
          final bytes = decodeAvatarUrl(u.avatarUrl);
          final isSelf = u.username == widget.currentUsername;
          final isFollowing = _following.contains(u.username);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: GestureDetector(
              onTap: () => _openProfile(u.username),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                foregroundImage: bytes != null ? MemoryImage(bytes) : null,
                child: bytes == null
                    ? Text(
                        u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: textColor),
                      )
                    : null,
              ),
            ),
            title: GestureDetector(
              onTap: () => _openProfile(u.username),
              child: Text(
                u.fullName.isNotEmpty ? u.fullName : u.username,
                style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
              ),
            ),
            subtitle: u.fullName.isNotEmpty
                ? GestureDetector(
                    onTap: () => _openProfile(u.username),
                    child: Text('@${u.username}', style: const TextStyle(color: Color(0xffb3b3b3))),
                  )
                : null,
            trailing: (isSelf || widget.onFollow == null)
                ? null
                : SizedBox(
                    height: 34,
                    child: OutlinedButton(
                      onPressed: () => _toggleFollow(u.username),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        side: BorderSide(
                          color: isFollowing
                              ? (isLight ? const Color(0xffb0b0b0) : const Color(0xff555555))
                              : (isLight ? Colors.black : Colors.white),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        foregroundColor: isFollowing
                            ? (isLight ? const Color(0xffb0b0b0) : const Color(0xff555555))
                            : textColor,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      child: Text(isFollowing ? 'Following' : widget.followerAuthors.contains(u.username) ? 'Follow Back' : 'Follow'),
                    ),
                  ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Likes',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textColor),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: isLight ? const Color(0xffe0e0e0) : const Color(0xff242424),
          ),
        ),
      ),
      body: body,
    );
  }
}

// ── _LikedByText ─────────────────────────────────────────────────────────────

class _LikedByText extends StatelessWidget {
  const _LikedByText({
    required this.likedByFollowing,
    required this.totalLikes,
    required this.isLight,
  });
  final List<String> likedByFollowing;
  final int totalLikes;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final boldStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: isLight ? Colors.black : Colors.white,
    );
    final normalStyle = TextStyle(
      fontSize: 13,
      color: isLight ? const Color(0xff444444) : const Color(0xffb3b3b3),
    );

    final others = totalLikes - likedByFollowing.length;
    final spans = <InlineSpan>[TextSpan(text: 'Liked by ', style: normalStyle)];

    for (int i = 0; i < likedByFollowing.length; i++) {
      if (i > 0) {
        final isLast = i == likedByFollowing.length - 1 && others <= 0;
        spans.add(TextSpan(text: isLast ? ' and ' : ', ', style: normalStyle));
      }
      spans.add(TextSpan(text: likedByFollowing[i], style: boldStyle));
    }

    if (others > 0) {
      spans.add(TextSpan(text: ' and ', style: normalStyle));
      spans.add(TextSpan(
        text: '$others ${others == 1 ? "other" : "others"}',
        style: boldStyle,
      ));
    }

    return RichText(text: TextSpan(children: spans));
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
    this.onUnfollow,
    this.isFollowing = false,
    this.followingAuthors = const {},
    this.followerAuthors = const {},
    this.onFollowUser,
    this.onUnfollowUser,
    this.onHideNavBar,
    this.onShowNavBar,
    this.likingEnabled = true,
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
  final VoidCallback? onUnfollow;
  final bool isFollowing;
  final Set<String> followingAuthors;
  final Set<String> followerAuthors;
  final Future<void> Function(String)? onFollowUser;
  final Future<void> Function(String)? onUnfollowUser;
  final VoidCallback? onHideNavBar;
  final VoidCallback? onShowNavBar;
  final bool likingEnabled;

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> with TickerProviderStateMixin {
  late bool _liked;
  late bool _saved;
  late int _likes;

  late final AnimationController _heartBounceCtrl;
  late final Animation<double> _heartBounceAnim;
  late final AnimationController _floatHeartCtrl;
  late final Animation<double> _floatHeartFade;
  late final Animation<double> _floatHeartScale;
  bool _floatHeartVisible = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _saved = widget.post.saved;
    _likes = widget.post.likes;

    _heartBounceCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _heartBounceAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4),  weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.85), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.0), weight: 30),
    ]).animate(_heartBounceCtrl);

    _floatHeartCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _floatHeartFade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_floatHeartCtrl);
    _floatHeartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.3,  end: 1.25), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0),  weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0,  end: 1.0),  weight: 40),
    ]).animate(_floatHeartCtrl);
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

  @override
  void dispose() {
    _heartBounceCtrl.dispose();
    _floatHeartCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLike() async {
    if (!widget.likingEnabled) return;
    final wasLiked = _liked;
    final wasLikes = _likes;
    final willLike = !_liked;
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
      widget.post.liked = _liked;
      widget.post.likes = _likes;
    });
    if (willLike) _heartBounceCtrl.forward(from: 0);
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

  void _handleDoubleTapLike() {
    if (!widget.likingEnabled) return;
    setState(() => _floatHeartVisible = true);
    _floatHeartCtrl.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _floatHeartVisible = false);
    });
    if (!_liked) {
      _handleLike();
    } else {
      _heartBounceCtrl.forward(from: 0);
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

  void _openFullscreen(BuildContext context, {int initialIndex = 0}) {
    widget.onHideNavBar?.call();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) => _FullscreenMediaViewer(
          media: widget.post.media,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ).whenComplete(() => widget.onShowNavBar?.call());
  }

  void _openLikers() {
    if (_likes == 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: false,
        builder: (_) => _LikersSheet(
          postId: widget.post.id,
          token: widget.token,
          currentUsername: widget.currentUser.username,
          followingAuthors: widget.followingAuthors,
          followerAuthors: widget.followerAuthors,
          onFollow: widget.onFollowUser,
          onUnfollow: widget.onUnfollowUser ?? (_) async {},
          onOpenUserProfile: widget.onOpenUserProfile,
        ),
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.post.author,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isLight ? Colors.black : Colors.white,
                                ),
                              ),
                              if (widget.post.authorVerified) ...[
                                const SizedBox(width: 3),
                                const Icon(Icons.verified_rounded, size: 14, color: Color(0xff0095f6)),
                              ],
                            ],
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
                  if (widget.onFollow != null || widget.onUnfollow != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: widget.isFollowing ? widget.onUnfollow : widget.onFollow,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: isLight ? Colors.black : Colors.white,
                        ),
                        foregroundColor: isLight ? Colors.black : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        widget.isFollowing
                            ? 'Following'
                            : widget.followerAuthors.contains(widget.post.author)
                                ? 'Follow Back'
                                : 'Follow',
                        style: const TextStyle(
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
            if (widget.post.media.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    _PostMediaCarousel(
                      media: widget.post.media,
                      onTap: (index) => _openFullscreen(context, initialIndex: index),
                      onDoubleTap: _handleDoubleTapLike,
                    ),
                    if (_floatHeartVisible)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _floatHeartCtrl,
                            builder: (_, _) => Center(
                              child: Opacity(
                                opacity: _floatHeartFade.value,
                                child: Transform.scale(
                                  scale: _floatHeartScale.value,
                                  child: const Icon(
                                    Icons.favorite_rounded,
                                    color: Colors.white,
                                    size: 80,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: Row(
                children: [
                  if (widget.likingEnabled)
                    AnimatedBuilder(
                      animation: _heartBounceCtrl,
                      builder: (_, child) => Transform.scale(
                        scale: _heartBounceAnim.value,
                        child: child,
                      ),
                      child: IconButton(
                        onPressed: _handleLike,
                        icon: Icon(
                          _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: _liked ? Colors.red : (isLight ? Colors.black : Colors.white),
                          size: 28,
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.favorite_border_rounded,
                              color: isLight ? Colors.black : Colors.white,
                              size: 28,
                            ),
                            CustomPaint(
                              size: const Size(28, 28),
                              painter: _SlashPainter(
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                          ],
                        ),
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
            if (widget.post.likedByFollowing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: GestureDetector(
                  onTap: _openLikers,
                  child: _LikedByText(
                    likedByFollowing: widget.post.likedByFollowing,
                    totalLikes: _likes,
                    isLight: isLight,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _openLikers,
                    child: Text(
                      '$_likes ${_likes == 1 ? "like" : "likes"}',
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
                          ? (widget.likingEnabled ? 'Add a comment...' : 'No comments yet.')
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

class _SlashPainter extends CustomPainter {
  const _SlashPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.72, size.height * 0.04),
      Offset(size.width * 0.28, size.height * 0.96),
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }
  @override
  bool shouldRepaint(_SlashPainter old) => old.color != color;
}
