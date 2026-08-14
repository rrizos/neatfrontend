// Instagram-style link handling: URLs typed into posts, comments and DMs are
// rendered as tappable links, and the first one in a message gets an Open
// Graph preview card underneath it.
//
// The metadata comes from our own backend (/api/link-preview/) rather than
// being fetched here, for three reasons: the card is then identical on every
// platform, one fetch per URL is shared by every viewer instead of one per
// device, and the web build can't fetch arbitrary origins from the browser
// anyway (CORS). It also keeps viewers' IP addresses away from whatever site
// someone happened to paste.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'http_client.dart' as http;

/// Matches bare URLs in free text: an explicit scheme, or a `www.` host, or a
/// plain `host.tld/path`. Deliberately conservative about the trailing
/// character — prose puts `.`, `,`, `)` and `;` right after a link and those
/// are almost never part of it.
final RegExp linkRegex = RegExp(
  r'\b(?:https?://|www\.)[^\s<>"]+'
  r'|\b[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9-]+)*'
  r'\.(?:com|gr|org|net|io|dev|app|edu|gov|co|uk|de|eu|info|me|tv|news|xyz)'
  r'(?:/[^\s<>"]*)?',
  caseSensitive: false,
);

/// Trailing punctuation that reads as sentence punctuation rather than URL.
const _kTrailingJunk = '.,;:!?)]}\'"«»…';

/// The substring of [match] that is actually the link, with sentence
/// punctuation trimmed off the end. Keeps a balanced ")" (Wikipedia URLs).
String trimTrailingPunctuation(String raw) {
  var end = raw.length;
  while (end > 0 && _kTrailingJunk.contains(raw[end - 1])) {
    // "…/Athens_(city)" — a ")" that closes a "(" inside the URL belongs to it.
    if (raw[end - 1] == ')' &&
        '('.allMatches(raw.substring(0, end)).length >=
            ')'.allMatches(raw.substring(0, end)).length) {
      break;
    }
    end--;
  }
  return raw.substring(0, end);
}

/// Turns a matched run into something launchable — bare `www.x.gr` and
/// `x.gr/y` need a scheme bolted on before they'll open.
String normaliseUrl(String raw) =>
    raw.startsWith(RegExp(r'https?://', caseSensitive: false))
        ? raw
        : 'https://$raw';

/// Where each link sits in the text, with punctuation already trimmed.
///
/// The single place link detection is decided — the span builders and
/// [extractUrls] all go through here, so what gets underlined and what gets a
/// preview card can never disagree.
List<({int start, int end, String url})> linkMatches(String text) {
  final out = <({int start, int end, String url})>[];
  for (final m in linkRegex.allMatches(text)) {
    // "someone@example.com" — the domain half of an email is not a link.
    if (m.start > 0 && text[m.start - 1] == '@') continue;
    final url = trimTrailingPunctuation(m.group(0)!);
    if (url.isEmpty) continue;
    out.add((start: m.start, end: m.start + url.length, url: url));
  }
  return out;
}

/// Every link in [text], in order, as they appear (already trimmed).
List<String> extractUrls(String text) =>
    linkMatches(text).map((m) => m.url).toList();

/// The link a preview card should describe: the first one in the text.
/// Matches how Instagram, Messenger and Slack all behave — one card per
/// message, no matter how many links it contains.
String? firstUrl(String text) {
  final urls = extractUrls(text);
  return urls.isEmpty ? null : urls.first;
}

/// Opens [url] in the in-app browser, falling back to the system browser.
Future<void> openLink(String url) async {
  final uri = Uri.tryParse(normaliseUrl(url));
  if (uri == null) return;
  try {
    if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return;
  } catch (_) {
    // Some Android devices have no Custom Tabs provider; fall through.
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Nothing can open it — silently give up rather than throwing mid-build.
  }
}

/// Splits [text] into spans with only the URLs made tappable.
///
/// The counterpart to `buildMentionSpans` for surfaces that don't have
/// mentions — DM bubbles — where treating "@someone" as a link would style
/// something that has nowhere to go.
List<InlineSpan> buildLinkSpans(
  String text, {
  required TextStyle style,
  required TextStyle linkStyle,
  ValueChanged<String>? onTapLink,
}) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in linkMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(text: text.substring(last, match.start), style: style));
    }
    spans.add(TextSpan(
      text: match.url,
      style: linkStyle,
      recognizer: TapGestureRecognizer()
        ..onTap = () =>
            onTapLink != null ? onTapLink(match.url) : openLink(match.url),
    ));
    last = match.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: style));
  }
  return spans;
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class LinkPreviewData {
  const LinkPreviewData({
    required this.url,
    required this.resolvedUrl,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.imageWidth,
    required this.imageHeight,
    required this.siteName,
    required this.authorName,
    required this.authorHandle,
    required this.authorUrl,
    required this.kind,
  });

  final String url;
  final String resolvedUrl;
  final String title;
  final String description;
  final String imageUrl;

  /// 0 when the source didn't say — the card then measures the image itself.
  final int imageWidth;
  final int imageHeight;

  final String siteName;

  /// Who posted it. Empty for a plain article or a site homepage, which is
  /// what keeps a shared newspaper link looking like a newspaper link.
  final String authorName;
  final String authorHandle;
  final String authorUrl;

  /// '', 'video', 'article' or 'website'.
  final String kind;

  static int _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

  factory LinkPreviewData.fromJson(Map<String, dynamic> json) => LinkPreviewData(
        url: (json['url'] ?? '') as String,
        resolvedUrl: (json['resolved_url'] ?? json['url'] ?? '') as String,
        title: (json['title'] ?? '') as String,
        description: (json['description'] ?? '') as String,
        imageUrl: (json['image_url'] ?? '') as String,
        imageWidth: _int(json['image_width']),
        imageHeight: _int(json['image_height']),
        siteName: (json['site_name'] ?? '') as String,
        authorName: (json['author_name'] ?? '') as String,
        authorHandle: (json['author_handle'] ?? '') as String,
        authorUrl: (json['author_url'] ?? '') as String,
        kind: (json['kind'] ?? '') as String,
      );

  bool get isVideo => kind == 'video';

  /// True when the link points at one person's post rather than at a site —
  /// a TikTok or a reel, as opposed to a newspaper front page.
  bool get hasAuthor => authorName.isNotEmpty || authorHandle.isNotEmpty;

  /// "@zachking" where a handle is known, otherwise the display name.
  String get authorLabel =>
      authorHandle.isNotEmpty ? '@$authorHandle' : authorName;

  /// The known aspect ratio, or null when the card has to measure the image.
  double? get imageAspect =>
      (imageWidth > 0 && imageHeight > 0) ? imageWidth / imageHeight : null;

  /// The host, for the little "in.gr" line on the card.
  String get displayHost {
    if (siteName.isNotEmpty) return siteName;
    final host = Uri.tryParse(resolvedUrl)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

/// Process-wide cache of resolved previews.
///
/// A feed re-renders its cards constantly (scroll, setState, tab switches) and
/// the same link can appear in a post and in three comments. Caching by URL —
/// including the misses, as `null` — means one network call per link per app
/// run. In-flight requests are shared so a burst of identical widgets building
/// on the same frame produces one call, not one each.
class LinkPreviewService {
  LinkPreviewService._();
  static final LinkPreviewService instance = LinkPreviewService._();

  final Map<String, LinkPreviewData?> _cache = {};
  final Map<String, Future<LinkPreviewData?>> _inFlight = {};

  // ── Disk cache ────────────────────────────────────────────────────────────
  //
  // Kept alongside the in-memory map so a cold start opens with the cards it
  // had last time instead of re-earning every one of them over the network.
  //
  // Bounded two ways, because this is a cache and not a record of anything:
  // entries older than [_kMaxAge] are dropped on load, and if more than
  // [_kMaxEntries] survive that, the oldest go too. Both happen while reading,
  // so a file that grew during a heavy session is trimmed the next time the
  // app opens rather than growing forever.
  //
  // Only successes are stored. A miss is cheap to re-ask and the server keeps
  // its own negative cache; persisting "this had no card" would make a link
  // that has since gained one stay blank for a week.
  static const _kMaxAge = Duration(days: 7);
  static const _kMaxEntries = 400;
  static const _kFileName = 'link_previews.json';

  /// When each entry was written, for expiry and for evicting the oldest.
  final Map<String, int> _storedAt = {};
  File? _file;
  bool _restored = false;
  Timer? _saveDebounce;

  /// Reads the previous session's cards. Call once at startup; failures are
  /// silent because an unreadable cache is only ever a slower start.
  Future<void> restore() async {
    if (_restored || kIsWeb) return;
    _restored = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_kFileName');
      _file = file;
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) return;

      final cutoff = DateTime.now().millisecondsSinceEpoch - _kMaxAge.inMilliseconds;
      final entries = <MapEntry<String, ({int at, LinkPreviewData data})>>[];
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final at = value['at'];
        final data = value['data'];
        if (at is! int || at < cutoff || data is! Map<String, dynamic>) continue;
        entries.add(MapEntry(entry.key,
            (at: at, data: LinkPreviewData.fromJson(data))));
      }
      // Newest first, so the cap keeps what is most likely to be looked at.
      entries.sort((a, b) => b.value.at.compareTo(a.value.at));
      for (final entry in entries.take(_kMaxEntries)) {
        // Never overwrite something this run already resolved or was sent.
        _cache.putIfAbsent(entry.key, () => entry.value.data);
        _storedAt.putIfAbsent(entry.key, () => entry.value.at);
      }
      // Trim the file itself if it had grown past either bound.
      if (entries.length > _kMaxEntries || entries.length != raw.length) {
        _scheduleSave();
      }
    } catch (_) {
      // Corrupt or unreadable — start empty rather than fail to launch.
    }
  }

  void _remember(String url, LinkPreviewData data) {
    _storedAt[url] = DateTime.now().millisecondsSinceEpoch;
    _scheduleSave();
  }

  /// Batches writes: a feed resolving twenty links should produce one file
  /// write, not twenty.
  void _scheduleSave() {
    if (kIsWeb) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 3), _save);
  }

  Future<void> _save() async {
    if (kIsWeb) return;
    try {
      final file = _file ??=
          File('${(await getApplicationSupportDirectory()).path}/$_kFileName');
      final keys = _storedAt.keys.toList()
        ..sort((a, b) => (_storedAt[b] ?? 0).compareTo(_storedAt[a] ?? 0));
      final out = <String, dynamic>{};
      for (final key in keys.take(_kMaxEntries)) {
        final data = _cache[key];
        if (data == null) continue; // misses are never persisted
        out[key] = {
          'at': _storedAt[key],
          'data': {
            'url': data.url,
            'resolved_url': data.resolvedUrl,
            'title': data.title,
            'description': data.description,
            'image_url': data.imageUrl,
            'image_width': data.imageWidth,
            'image_height': data.imageHeight,
            'site_name': data.siteName,
            'author_name': data.authorName,
            'author_handle': data.authorHandle,
            'author_url': data.authorUrl,
            'kind': data.kind,
          },
        };
      }
      await file.writeAsString(jsonEncode(out), flush: true);
    } catch (_) {
      // Out of space, sandbox denial — the cache is expendable.
    }
  }

  /// Records a card the server sent alongside its post, so the widget that
  /// eventually renders it paints on its first frame instead of asking for
  /// something we were already given.
  void seed(String url, LinkPreviewData data) {
    final key = normaliseUrl(url);
    _cache[key] = data;
    _remember(key, data);
  }

  /// Cached value if we already have one. Lets a widget paint a known card on
  /// its first frame instead of flashing a loading state.
  ///
  /// Keyed on the normalised URL like [fetch] is, so "in.gr" and
  /// "https://in.gr" are one entry rather than a hit and a permanent miss.
  bool isCached(String url) => _cache.containsKey(normaliseUrl(url));
  LinkPreviewData? cached(String url) => _cache[normaliseUrl(url)];

  Future<LinkPreviewData?> fetch(String rawUrl, String token) {
    // Text is full of scheme-less links ("www.in.gr", "neatapp.gr/post/12").
    // The server only fetches http/https, so a bare host has to gain a scheme
    // here or it comes back with no card at all — which is why typed website
    // links looked broken while pasted social links (always https://) worked.
    final url = normaliseUrl(rawUrl);
    if (_cache.containsKey(url)) return Future.value(_cache[url]);
    final existing = _inFlight[url];
    if (existing != null) return existing;

    final future = _load(url, token).whenComplete(() => _inFlight.remove(url));
    _inFlight[url] = future;
    return future;
  }

  Future<LinkPreviewData?> _load(String url, String token) async {
    try {
      final res = await http
          .get(linkPreviewEndpoint(url), headers: authGetHeaders(token))
          .timeout(const Duration(seconds: 12));
      // Only a 200 is an answer about the link. Anything else is a statement
      // about this request — a 401 because the session had not finished
      // loading when the feed painted, a 429 from the rate limiter, a 502 —
      // and caching those as "this link has no card" is what made previews
      // vanish for the rest of the run after a cold start. The server keeps
      // its own negative cache, so asking again is cheap.
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final raw = body['preview'];
      final data = raw is Map<String, dynamic>
          ? LinkPreviewData.fromJson(raw)
          : null;
      _cache[url] = data;
      if (data != null) _remember(url, data);
      return data;
    } catch (_) {
      // Offline or timed out. Not cached: worth retrying on the next build.
      return null;
    }
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

/// The play button drawn over a video thumbnail, so a shared TikTok or reel
/// reads as something to watch rather than as a photo.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
          ),
          // Nudged right so the triangle looks centred inside the circle.
          child: const Padding(
            padding: EdgeInsets.only(left: 3),
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
          ),
        ),
      );
}

/// The preview card itself. Renders nothing at all until a preview resolves,
/// so a link with no metadata (or no connection) just leaves the tappable text
/// on its own rather than leaving a skeleton behind.
class LinkPreviewCard extends StatefulWidget {
  const LinkPreviewCard({
    super.key,
    required this.url,
    required this.token,
    required this.isLight,
    this.compact = false,
    this.maxWidth,
    this.onSurface = false,
  });

  final String url;
  final String token;
  final bool isLight;

  /// Tighter layout for DM bubbles, where width is already constrained.
  final bool compact;
  final double? maxWidth;

  /// True when the card sits on a coloured bubble (a sent DM) rather than on
  /// the page background — it then uses translucent white instead of grey.
  final bool onSurface;

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkPreviewData? _data;
  bool _resolved = false;

  /// Filled in when the server didn't report image dimensions (Instagram
  /// doesn't) — resolved from the decoded image so a portrait reel is drawn
  /// portrait instead of being cropped into a letterbox.
  double? _measuredAspect;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(LinkPreviewCard old) {
    super.didUpdateWidget(old);
    // A token arriving matters as much as the url changing: on a cold start
    // the feed paints from its local cache before the session has loaded, so
    // the first build of a card often has nothing to authenticate with.
    if (old.url != widget.url || old.token != widget.token) {
      _stopMeasuring();
      _retry?.cancel();
      _data = null;
      _resolved = false;
      _measuredAspect = null;
      _attempts = 0;
      _start();
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _stopMeasuring();
    super.dispose();
  }

  void _stopMeasuring() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  /// Retries after a request that told us nothing — no session yet, offline,
  /// rate limited, server hiccup. Without these the card gave up on the first
  /// attempt and stayed empty for the rest of the run, which is why previews
  /// were there when a post was written and gone after the app restarted.
  static const _kRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  int _attempts = 0;
  Timer? _retry;

  void _start() {
    final service = LinkPreviewService.instance;
    if (service.isCached(widget.url)) {
      _data = service.cached(widget.url);
      _resolved = true;
      _measureIfNeeded();
      return;
    }
    // No session yet — the feed can paint before it loads. Wait to be given
    // one (didUpdateWidget) rather than settling as "this link has no card".
    if (widget.token.isEmpty) return;

    service.fetch(widget.url, widget.token).then((data) {
      if (!mounted) return;
      // A null that the service recorded is an answer: the link genuinely has
      // no card. A null it did not record means the request never got one.
      final answered = data != null || service.isCached(widget.url);
      if (answered) {
        setState(() {
          _data = data;
          _resolved = true;
        });
        _measureIfNeeded();
        return;
      }
      if (_attempts >= _kRetryDelays.length) {
        setState(() => _resolved = true);
        return;
      }
      _retry = Timer(_kRetryDelays[_attempts++], () {
        if (mounted) _start();
      });
    });
  }

  /// Listens for the decoded image just long enough to learn its shape.
  void _measureIfNeeded() {
    final data = _data;
    if (data == null || data.imageUrl.isEmpty) return;
    if (data.imageAspect != null) return; // server told us already

    final stream = NetworkImage(data.imageUrl).resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      final w = info.image.width, h = info.image.height;
      if (h <= 0) return;
      setState(() => _measuredAspect = w / h);
      _stopMeasuring();
    }, onError: (_, _) => _stopMeasuring());

    _stopMeasuring();
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  /// How tall to draw the thumbnail.
  ///
  /// Clamped rather than used raw: a 9:16 TikTok frame at its true 0.53 ratio
  /// is nearly twice as tall as it is wide, which swamps a feed post. 1.25
  /// (a 4:5 crop, the shape Instagram uses) still reads as portrait video but
  /// keeps the card to a reasonable share of the screen. Wide banners are held
  /// at the standard og:image 1.91 so they don't collapse to a sliver.
  static const double _minAspect = 1.25;
  static const double _maxAspect = 1.91;

  double _aspectFor(LinkPreviewData data) {
    final aspect = data.imageAspect ?? _measuredAspect;
    if (aspect == null || aspect <= 0) {
      // Unknown: assume the standard og:image banner, unless it's a video,
      // where a squarer crop is the safer guess for short-form.
      return data.isVideo ? _minAspect : _maxAspect;
    }
    return aspect.clamp(_minAspect, _maxAspect);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (!_resolved || data == null) return const SizedBox.shrink();

    final isLight = widget.isLight;
    final bg = widget.onSurface
        ? Colors.white.withValues(alpha: 0.14)
        : (isLight ? const Color(0xfff2f4f7) : const Color(0xff141414));
    final border = widget.onSurface
        ? Colors.white.withValues(alpha: 0.22)
        : (isLight ? const Color(0xffe2e6ec) : const Color(0xff2c2c2e));
    final titleColor =
        widget.onSurface ? Colors.white : (isLight ? Colors.black : Colors.white);
    final subColor = widget.onSurface
        ? Colors.white.withValues(alpha: 0.75)
        : (isLight ? const Color(0xff667085) : const Color(0xff98a2b3));

    final hasImage = data.imageUrl.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(top: widget.compact ? 6 : 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth ?? double.infinity),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openLink(data.resolvedUrl),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasImage)
                    AspectRatio(
                      aspectRatio: _aspectFor(data),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            data.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            // A broken or slow image shouldn't blank the whole
                            // card — the text below it is the useful part.
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                    ? child
                                    : Container(
                                        color: isLight
                                            ? const Color(0xffe8ecf1)
                                            : const Color(0xff232326),
                                      ),
                          ),
                          if (data.isVideo) const _PlayBadge(),
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.all(widget.compact ? 9 : 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // "TIKTOK · @zachking" — the provider plus whoever
                        // posted it, which is the line that tells you what a
                        // shared video actually is before the image loads.
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                data.displayHost.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                  color: subColor,
                                ),
                              ),
                            ),
                            if (data.hasAuthor) ...[
                              Text(' · ',
                                  style: TextStyle(fontSize: 10.5, color: subColor)),
                              Flexible(
                                flex: 2,
                                child: Text(
                                  data.authorLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (data.title.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            data.title,
                            maxLines: widget.compact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: widget.compact ? 13 : 14,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                        ],
                        if (data.description.isNotEmpty && !widget.compact) ...[
                          const SizedBox(height: 3),
                          Text(
                            data.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: subColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
