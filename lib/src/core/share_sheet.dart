import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'models.dart';

Future<void> showShareSheet({
  required BuildContext context,
  required FeedPost post,
  required String token,
  required UserProfile currentUser,
  required Future<void> Function() onLogout,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareSheet(
      post: post,
      token: token,
      currentUser: currentUser,
      onLogout: onLogout,
    ),
  );
}

// ── internal model ────────────────────────────────────────────────────────────

class _Target {
  _Target({
    required this.username,
    this.fullName = '',
    this.avatarUrl = '',
    this.conversationId,
  });
  final String username;
  final String fullName;
  final String avatarUrl;
  final int? conversationId;
}

// ── sheet widget ──────────────────────────────────────────────────────────────

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.post,
    required this.token,
    required this.currentUser,
    required this.onLogout,
  });
  final FeedPost post;
  final String token;
  final UserProfile currentUser;
  final Future<void> Function() onLogout;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  List<_Target> _targets = [];
  List<_Target>? _searchResults;
  bool _loading = true;
  bool _searching = false;
  final _search = TextEditingController();
  String _query = '';
  final Set<String> _sent = {};
  final Set<String> _sending = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── data loading ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        http.get(inboxEndpoint, headers: authGetHeaders(widget.token)),
        http.get(followingEndpoint(widget.currentUser.username), headers: authGetHeaders(widget.token)),
      ]);
      if (results[0].statusCode == 401) { await widget.onLogout(); return; }

      final seen = <String>{};
      final targets = <_Target>[];

      if (results[0].statusCode == 200) {
        final body = jsonDecode(results[0].body) as Map<String, dynamic>;
        final convs = (body['conversations'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ConversationSummary.fromJson);
        for (final c in convs) {
          seen.add(c.otherUser);
          targets.add(_Target(username: c.otherUser, fullName: c.otherFullName, conversationId: c.id));
        }
      }

      if (results[1].statusCode == 200) {
        final body = jsonDecode(results[1].body) as Map<String, dynamic>;
        final users = (body['users'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(UserProfile.fromJson);
        for (final u in users) {
          if (!seen.contains(u.username)) {
            targets.add(_Target(username: u.username, fullName: u.fullName, avatarUrl: u.avatarUrl));
          }
        }
      }

      if (mounted) setState(() { _targets = targets; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value.trim();
      _searchResults = null;
    });
    if (_query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _query;
    if (q.isEmpty) return;
    if (mounted) setState(() => _searching = true);
    try {
      final res = await http.get(searchUsersEndpoint(q), headers: authGetHeaders(widget.token));
      if (!mounted || _query != q) return;
      if (res.statusCode != 200) { setState(() => _searching = false); return; }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final myCity = widget.currentUser.city.trim().toLowerCase();
      final results = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .where((u) => u.username != widget.currentUser.username)
          .where((u) => myCity.isEmpty || u.city.trim().toLowerCase() == myCity)
          .map((u) {
            _Target? existing;
            for (final t in _targets) {
              if (t.username == u.username) { existing = t; break; }
            }
            return _Target(
              username: u.username,
              fullName: u.fullName,
              avatarUrl: u.avatarUrl,
              conversationId: existing?.conversationId,
            );
          })
          .toList();
      setState(() { _searchResults = results; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  List<_Target> get _filtered {
    if (_query.isEmpty) return _targets;
    final q = _query.toLowerCase();
    final localMatch = _targets
        .where((t) => t.username.toLowerCase().contains(q) || t.fullName.toLowerCase().contains(q))
        .toList();
    if (_searchResults == null) return localMatch;
    final seen = localMatch.map((t) => t.username).toSet();
    for (final t in _searchResults!) {
      if (!seen.contains(t.username)) localMatch.add(t);
    }
    return localMatch;
  }

  // ── DM sending ──────────────────────────────────────────────────────────────

  String get _dmPayload {
    return '__neat_post__:${jsonEncode({
      'id': widget.post.id,
      'author': widget.post.author,
      'text': widget.post.text,
      'imageUrl': widget.post.imageUrl,
      'likes': widget.post.likes,
    })}';
  }

  Future<void> _sendTo(_Target target) async {
    final key = target.username;
    if (_sending.contains(key) || _sent.contains(key)) return;
    setState(() => _sending.add(key));
    try {
      int convId;
      if (target.conversationId != null) {
        convId = target.conversationId!;
      } else {
        final r = await http.post(
          startConversationEndpoint,
          headers: authJsonHeaders(widget.token),
          body: jsonEncode({'username': target.username}),
        );
        if (!mounted) return;
        if (r.statusCode == 401) { await widget.onLogout(); return; }
        if (r.statusCode != 200 && r.statusCode != 201) { setState(() => _sending.remove(key)); return; }
        final conv = ConversationSummary.fromJson(
          (jsonDecode(r.body) as Map<String, dynamic>)['conversation'] as Map<String, dynamic>,
        );
        convId = conv.id;
      }
      final r = await http.post(
        messageConversationEndpoint(convId),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'text': _dmPayload}),
      );
      if (!mounted) return;
      if (r.statusCode == 401) { await widget.onLogout(); return; }
      setState(() {
        _sending.remove(key);
        if (r.statusCode == 201) _sent.add(key);
      });
    } catch (_) {
      if (mounted) setState(() => _sending.remove(key));
    }
  }

  // ── external share ──────────────────────────────────────────────────────────

  String get _shareText {
    final t = widget.post.text;
    final snippet = t.length > 120 ? '${t.substring(0, 120)}…' : t;
    return '@${widget.post.author} on Neat: "$snippet"';
  }

  String get _shareLink => '$webBaseUrl/post/${widget.post.id}';

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _shareLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  static const _shareChannel = MethodChannel('com.neat/share');

  Future<void> _nativeShare() async {
    if (kIsWeb) {
      await _copyLink();
      return;
    }
    try {
      await _shareChannel.invokeMethod<void>('share', {'text': _shareLink});
    } catch (_) {}
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : const Color(0xff111111);
    final surface = isLight ? const Color(0xfff3f4f6) : const Color(0xff1c1c1e);
    final textColor = isLight ? Colors.black : Colors.white;
    final muted = isLight ? const Color(0xff6b7280) : const Color(0xff9ca3af);
    final divider = isLight ? const Color(0xffe5e7eb) : const Color(0xff222222);
    final filtered = _filtered;

    return FractionallySizedBox(
      heightFactor: 0.84,
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          children: [
            // drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 14),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xffcbd5e1) : const Color(0xff3f3f46),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // post preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _PostPreview(post: widget.post, isLight: isLight),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: divider),

            // header + search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send to', style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _search,
                      onChanged: _onSearchChanged,
                      style: TextStyle(color: textColor, fontSize: 14),
                      cursorColor: textColor,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded, color: muted, size: 18),
                        suffix: _searching
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : null,
                        hintText: 'Search people in your city…',
                        hintStyle: TextStyle(color: muted, fontSize: 13.5),
                        filled: true,
                        fillColor: surface,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: divider)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // contacts
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_search_rounded, size: 40, color: muted),
                              const SizedBox(height: 10),
                              Text(
                                _query.isEmpty ? 'No contacts yet' : 'No one found in your city',
                                style: TextStyle(color: muted, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: divider),
                          itemBuilder: (ctx, i) {
                            final t = filtered[i];
                            final isSent = _sent.contains(t.username);
                            final isSending = _sending.contains(t.username);
                            final bytes = t.avatarUrl.isNotEmpty ? _dataUrlBytes(t.avatarUrl) : null;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: isLight ? const Color(0xffe5e7eb) : const Color(0xff2a2a2a),
                                    foregroundImage: bytes != null ? MemoryImage(bytes) : null,
                                    child: bytes == null
                                        ? Text(initialFor(t.username), style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14))
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.username, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
                                        if (t.fullName.isNotEmpty)
                                          Text(t.fullName, style: TextStyle(color: muted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _SendBtn(isSent: isSent, isSending: isSending, onTap: () => _sendTo(t)),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // external share
            Divider(height: 1, color: divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _ExtBtn(label: 'Instagram', onTap: _nativeShare, child: const _IgIcon()),
                    const SizedBox(width: 16),
                    _ExtBtn(label: 'WhatsApp', onTap: () => _launch('https://wa.me/?text=${Uri.encodeComponent('$_shareText\n$_shareLink')}'), child: const _WhatsAppIcon()),
                    const SizedBox(width: 16),
                    _ExtBtn(label: 'X (Twitter)', onTap: () => _launch('https://x.com/intent/tweet?text=${Uri.encodeComponent('$_shareText\n$_shareLink')}'), child: const _XIcon()),
                    const SizedBox(width: 16),
                    _ExtBtn(label: 'Telegram', onTap: () => _launch('https://t.me/share/url?url=${Uri.encodeComponent(_shareLink)}&text=${Uri.encodeComponent(_shareText)}'), child: const _TelegramIcon()),
                    const SizedBox(width: 16),
                    _ExtBtn(label: 'Facebook', onTap: () => _launch('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_shareLink)}'), child: const _FbIcon()),
                    const SizedBox(width: 16),
                    _ExtBtn(label: 'Copy link', onTap: _copyLink, child: _LinkIcon(isLight: isLight)),
                  ],
                ),
              ),
            ),
            SafeArea(top: false, child: const SizedBox(height: 4)),
          ],
        ),
      ),
    );
  }
}

// ── post preview ──────────────────────────────────────────────────────────────

class _PostPreview extends StatelessWidget {
  const _PostPreview({required this.post, required this.isLight});
  final FeedPost post;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final textColor = isLight ? Colors.black : Colors.white;
    final muted = isLight ? const Color(0xff6b7280) : const Color(0xff9ca3af);
    final bg = isLight ? const Color(0xfff9fafb) : const Color(0xff1c1c1e);
    final border = isLight ? const Color(0xffe5e7eb) : const Color(0xff2a2a2a);
    final bytes = post.imageUrl.isNotEmpty ? _dataUrlBytes(post.imageUrl) : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isLight ? const Color(0xffe5e7eb) : const Color(0xff2a2a2a),
            child: Text(initialFor(post.author), style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.author, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                if (post.text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    post.text.length > 60 ? '${post.text.substring(0, 60)}…' : post.text,
                    style: TextStyle(color: muted, fontSize: 12.5, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (post.imageUrl.isNotEmpty) ...[
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48, height: 48,
                child: bytes != null ? Image.memory(bytes, fit: BoxFit.cover) : Image.network(post.imageUrl, fit: BoxFit.cover),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── send button ───────────────────────────────────────────────────────────────

class _SendBtn extends StatelessWidget {
  const _SendBtn({required this.isSent, required this.isSending, required this.onTap});
  final bool isSent;
  final bool isSending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (isSent) {
      return Row(mainAxisSize: MainAxisSize.min, children: const [
        Icon(Icons.check_circle_rounded, color: Color(0xff22c55e), size: 15),
        SizedBox(width: 4),
        Text('Sent', style: TextStyle(color: Color(0xff22c55e), fontWeight: FontWeight.w700, fontSize: 13)),
      ]);
    }
    if (isSending) {
      return const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xff3897f0)));
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xff3897f0), borderRadius: BorderRadius.circular(8)),
        child: const Text('Send', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}

// ── external button ───────────────────────────────────────────────────────────

class _ExtBtn extends StatelessWidget {
  const _ExtBtn({required this.label, required this.onTap, required this.child});
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.light
        ? const Color(0xff6b7280)
        : const Color(0xff9ca3af);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            child,
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── brand icons ───────────────────────────────────────────────────────────────

class _IgIcon extends StatelessWidget {
  const _IgIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xfff09433), Color(0xffe6683c), Color(0xffdc2743), Color(0xffcc2366), Color(0xffbc1888)],
          begin: Alignment.bottomLeft, end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2.5),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          Positioned(
            top: 12, right: 13,
            child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
        ],
      ),
    );
  }
}

class _WhatsAppIcon extends StatelessWidget {
  const _WhatsAppIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(color: const Color(0xff25D366), borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

class _XIcon extends StatelessWidget {
  const _XIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(color: const Color(0xff000000), borderRadius: BorderRadius.circular(16)),
      child: const Center(
        child: Text(
          'X',
          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1),
        ),
      ),
    );
  }
}

class _TelegramIcon extends StatelessWidget {
  const _TelegramIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff2AABEE), Color(0xff229ED9)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.near_me_rounded, color: Colors.white, size: 26),
    );
  }
}

class _FbIcon extends StatelessWidget {
  const _FbIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(color: const Color(0xff1877F2), borderRadius: BorderRadius.circular(16)),
      child: const Center(
        child: Text('f', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1)),
      ),
    );
  }
}

class _LinkIcon extends StatelessWidget {
  const _LinkIcon({required this.isLight});
  final bool isLight;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: isLight ? const Color(0xffe5e7eb) : const Color(0xff2a2a2a),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.link_rounded, color: isLight ? Colors.black : Colors.white, size: 28),
    );
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

Uint8List? _dataUrlBytes(String value) {
  if (!value.startsWith('data:')) return null;
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  try { return base64Decode(value.substring(comma + 1)); } catch (_) { return null; }
}
