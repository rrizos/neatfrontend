import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:giphy_flutter_sdk/dto/giphy_content_type.dart';
import 'package:giphy_flutter_sdk/dto/giphy_media.dart';
import 'package:giphy_flutter_sdk/dto/giphy_settings.dart';
import 'package:giphy_flutter_sdk/dto/giphy_theme.dart';
import 'package:giphy_flutter_sdk/giphy_dialog.dart';
import '../core/http_client.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import '../core/media_cache.dart';
import '../core/models.dart';
import '../core/report_post_sheet.dart';

// ─── Colour tokens ────────────────────────────────────────────────────────────

const _kBlue      = Color(0xff3897f0);
const _kOtherDark = Color(0xff262626);
const _kOtherLgt  = Color(0xffefefef);
const _kBgDark    = Color(0xff000000);
const _kBgLgt     = Color(0xffffffff);
const _kInputDark = Color(0xff1c1c1e);
const _kInputLgt  = Color(0xfff0f0f0);
const _kSubDark   = Color(0xff8e8e8e);
const _kSubLgt    = Color(0xff737373);
const _kDivDark   = Color(0xff1c1c1e);
const _kDivLgt    = Color(0xffe0e0e0);

// ─── Message-type prefixes ────────────────────────────────────────────────────

const _kPostPrefix  = '__neat_post__:';
const _kImagePrefix = '__neat_image__:';
const _kVoicePrefix = '__neat_voice__:';
const _kReplyPrefix = '__neat_reply__:';

// ─── Image helpers ────────────────────────────────────────────────────────────

Uint8List? _dataUrlBytes(String v) {
  if (!v.startsWith('data:')) return null;
  final c = v.indexOf(',');
  if (c < 0) return null;
  try { return base64Decode(v.substring(c + 1)); } catch (_) { return null; }
}

ImageProvider? _imgProvider(String url) {
  if (url.isEmpty) return null;
  final b = _dataUrlBytes(url);
  if (b != null) return MemoryImage(b);
  return CachedNetworkImageProvider(url, cacheManager: imageCacheManager);
}

Widget _avatar({
  required String username,
  required String url,
  required double radius,
  bool isLight = false,
  bool ring = false,
}) {
  Widget w = CircleAvatar(
    radius: radius,
    backgroundColor: isLight ? const Color(0xffd8d8d8) : const Color(0xff3a3a3a),
    foregroundImage: _imgProvider(url),
    // always provide child as letter fallback in case foregroundImage fails
    child: Text(
      initialFor(username),
      style: TextStyle(
        color: isLight ? Colors.black87 : Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.72,
      ),
    ),
  );
  if (!ring) return w;
  return Container(
    padding: const EdgeInsets.all(2),
    decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
    child: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xff000000), width: 2),
      ),
      child: w,
    ),
  );
}

// ─── Bubble radius ────────────────────────────────────────────────────────────

BorderRadius _bubbleRadius(bool mine, bool isLast) {
  const big  = Radius.circular(20);
  const tail = Radius.circular(4);
  if (!isLast) return const BorderRadius.all(big);
  return mine
      ? const BorderRadius.only(topLeft: big, topRight: big, bottomLeft: big, bottomRight: tail)
      : const BorderRadius.only(topLeft: big, topRight: big, bottomLeft: tail, bottomRight: big);
}

// ─── Time helpers ─────────────────────────────────────────────────────────────

String _inboxTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours   < 1) return '${d.inMinutes}m';
  if (d.inDays    < 1) return '${d.inHours}h';
  if (d.inDays    < 7) return '${d.inDays}d';
  return '${t.day}/${t.month}';
}

// ─── Presence helpers ─────────────────────────────────────────────────────────

const _kGreen = Color(0xff3fc95a);
const _kActiveNowThreshold = Duration(minutes: 5);

/// Returns "Active now", "Active 3m ago", "Active 2h ago", "Active 3d ago",
/// or null when last_active is unknown / too old (>7 days).
String? _presenceLabel(DateTime? lastActive) {
  if (lastActive == null) return null;
  final d = DateTime.now().toUtc().difference(lastActive.toUtc());
  if (d < _kActiveNowThreshold) return 'Active now';
  if (d.inMinutes < 60) return 'Active ${d.inMinutes}m ago';
  if (d.inHours   < 24) return 'Active ${d.inHours}h ago';
  if (d.inDays    < 7)  return 'Active ${d.inDays}d ago';
  return null;
}

bool _isActiveNow(DateTime? lastActive) {
  if (lastActive == null) return false;
  return DateTime.now().toUtc().difference(lastActive.toUtc()) < _kActiveNowThreshold;
}

String _chatTime(DateTime t) {
  final d  = DateTime.now().difference(t);
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  if (d.inDays == 0) return '$hh:$mm';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (d.inDays < 7) return '${days[t.weekday - 1]} $hh:$mm';
  return '${t.day}/${t.month}/${t.year}';
}

bool _showDivider(List<MessageItem> msgs, int i) =>
    i == 0 || msgs[i].created.difference(msgs[i - 1].created).inMinutes >= 5;

bool _isLastInGroup(List<MessageItem> msgs, int i) =>
    i == msgs.length - 1 || msgs[i].sender != msgs[i + 1].sender;

String? _extractError(String body) {
  try {
    final d = jsonDecode(body);
    if (d is Map<String, dynamic>) return d['error']?.toString();
  } catch (_) {}
  return null;
}

// ─── Message-type parsers ─────────────────────────────────────────────────────

Map<String, dynamic>? _parsePost(String t) {
  if (!t.startsWith(_kPostPrefix)) return null;
  try {
    final d = jsonDecode(t.substring(_kPostPrefix.length));
    return d is Map<String, dynamic> ? d : null;
  } catch (_) { return null; }
}

Uint8List? _parseImage(String t) {
  if (!t.startsWith(_kImagePrefix)) return null;
  try { return base64Decode(t.substring(_kImagePrefix.length)); }
  catch (_) { return null; }
}

({Uint8List bytes, int secs})? _parseVoice(String t) {
  if (!t.startsWith(_kVoicePrefix)) return null;
  final data = t.substring(_kVoicePrefix.length);
  final sep  = data.lastIndexOf('|');
  if (sep < 0) return null;
  try {
    final bytes = base64Decode(data.substring(0, sep));
    final secs  = int.tryParse(data.substring(sep + 1)) ?? 0;
    return (bytes: bytes, secs: secs);
  } catch (_) { return null; }
}

({String sender, String preview, String text, int? id})? _parseReply(String t) {
  if (!t.startsWith(_kReplyPrefix)) return null;
  try {
    final d = jsonDecode(t.substring(_kReplyPrefix.length)) as Map<String, dynamic>;
    return (
      sender: d['sender']?.toString() ?? '',
      preview: d['preview']?.toString() ?? '',
      text: d['text']?.toString() ?? '',
      id: d['id'] != null ? int.tryParse(d['id'].toString()) : null,
    );
  } catch (_) { return null; }
}

// ─────────────────────────────────────────────────────────────────────────────
// MessagesPage  (inbox)
// ─────────────────────────────────────────────────────────────────────────────

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.token,
    required this.currentUsername,
    required this.suggestedUsers,
    required this.onLogout,
    this.onOpenPost,
    this.onOpenUserProfile,
  });

  final String token;
  final String currentUsername;
  final List<UserProfile> suggestedUsers;
  final Future<void> Function() onLogout;
  final void Function(String author, int postId)? onOpenPost;
  final ValueChanged<String>? onOpenUserProfile;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  List<ConversationSummary> _convs = [];
  bool _loading = true;
  bool _isOffline = false;
  final _search = TextEditingController();
  Timer? _presenceTimer;
  Timer? _inboxPollTimer;

  @override
  void initState() {
    super.initState();
    _loadInboxCache();
    _load();
    _pingPresence();
    _presenceTimer   = Timer.periodic(const Duration(seconds: 30), (_) => _pingPresence());
    _inboxPollTimer  = Timer.periodic(const Duration(seconds: 3),  (_) => _load());
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _inboxPollTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _pingPresence() async {
    try {
      await http.post(presenceEndpoint, headers: authJsonHeaders(widget.token));
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final res = await http.get(inboxEndpoint, headers: authGetHeaders(widget.token));
      if (res.statusCode == 401) return widget.onLogout();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rawList = (body['conversations'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final items = rawList.map(ConversationSummary.fromJson).toList();
      unawaited(_saveInboxCache(rawList));
      if (mounted) setState(() { _convs = items; _loading = false; _isOffline = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _isOffline = true; });
    }
  }

  static const _secureStorage = FlutterSecureStorage();

  Future<void> _saveInboxCache(List<dynamic> raw) async {
    try {
      await _secureStorage.write(key: 'neat_inbox_cache', value: jsonEncode(raw));
    } catch (_) {}
  }

  Future<void> _loadInboxCache() async {
    try {
      final raw = await _secureStorage.read(key: 'neat_inbox_cache');
      if (raw == null || !mounted) return;
      final list = (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().toList();
      final items = list.map(ConversationSummary.fromJson).toList();
      if (!mounted || items.isEmpty) return;
      setState(() { _convs = items; _loading = false; });
    } catch (_) {}
  }

  Future<void> _open(ConversationSummary s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationPage(
        token: widget.token,
        currentUsername: widget.currentUsername,
        conversationId: s.id,
        otherUsername: s.otherUser,
        otherFullName: s.otherFullName,
        otherAvatarUrl: s.otherAvatarUrl,
        otherLastActive: s.otherLastActive,
        onLogout: widget.onLogout,
        onOpenPost: widget.onOpenPost,
        onOpenUserProfile: widget.onOpenUserProfile,
      ),
    ));
    if (mounted) _load();
  }

  Future<void> _startChatWith(String username) async {
    final u = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (u.isEmpty) return;
    final res = await http.post(
      startConversationEndpoint,
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'username': u}),
    );
    if (res.statusCode == 401) return widget.onLogout();
    if (res.statusCode != 200 && res.statusCode != 201) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractError(res.body) ?? 'Could not start chat')),
      );
      return;
    }
    final conv = ConversationSummary.fromJson(
      (jsonDecode(res.body) as Map<String, dynamic>)['conversation'] as Map<String, dynamic>,
    );
    if (mounted) await _open(conv);
  }

  Future<void> _compose() async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final username = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isLight ? _kBgLgt : _kBgDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _NewMessageSheet(suggestedUsers: widget.suggestedUsers),
      ),
    );
    if (username == null || username.isEmpty) return;
    await _startChatWith(username);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? _kBgLgt : _kBgDark;
    final q  = _search.text.toLowerCase().trim();
    final nonSelf = _convs.where((c) => c.otherUser != widget.currentUsername).toList();
    final filtered = q.isEmpty
        ? nonSelf
        : nonSelf.where((c) =>
            c.otherUser.toLowerCase().contains(q) ||
            c.otherFullName.toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 44,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 4,
        title: Text(
          widget.currentUsername,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: isLight ? Colors.black : Colors.white,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'New message',
              icon: Icon(Icons.edit_square, color: isLight ? Colors.black : Colors.white, size: 26),
              onPressed: _compose,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kBlue,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: _SearchField(
                  controller: _search,
                  isLight: isLight,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            if (_isOffline)
              const SliverToBoxAdapter(child: _InboxOfflineBanner()),
            if (q.isEmpty) ...() {
                final activeConvs = _convs
                    .where((c) => c.otherUser != widget.currentUsername && _isActiveNow(c.otherLastActive))
                    .toList();
                if (activeConvs.isEmpty) return const <Widget>[];
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 0, 6),
                      child: Text(
                        'Active Now',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: activeConvs.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 18),
                        itemBuilder: (_, i) {
                          final c = activeConvs[i];
                          return _ActiveChip(
                            username: c.otherUser,
                            avatarUrl: c.otherAvatarUrl,
                            isLight: isLight,
                            onTap: () => _open(c),
                          );
                        },
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Divider(height: 1, color: isLight ? _kDivLgt : _kDivDark),
                  ),
                ];
              }(),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: _kBlue)),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: _EmptyInbox(isLight: isLight, hasSearch: q.isNotEmpty, isOffline: _isOffline),
              )
            else
              SliverList.separated(
                separatorBuilder: (_, i) => Divider(
                  height: 1, indent: 76, color: isLight ? _kDivLgt : _kDivDark,
                ),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _InboxRow(
                  summary: filtered[i],
                  currentUsername: widget.currentUsername,
                  isLight: isLight,
                  onTap: () => _open(filtered[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Inbox row ────────────────────────────────────────────────────────────────

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    required this.summary,
    required this.currentUsername,
    required this.isLight,
    required this.onTap,
  });

  final ConversationSummary summary;
  final String currentUsername;
  final bool isLight;
  final VoidCallback onTap;

  String get _preview {
    final msg = summary.lastMessage;
    final me  = summary.lastSender == currentUsername;
    if (msg.isEmpty) return 'Tap to start chatting';
    if (msg.startsWith(_kPostPrefix))  return me ? 'You sent a post'          : 'Sent a post';
    if (msg.startsWith(_kImagePrefix)) return me ? 'You sent a photo'         : 'Sent a photo';
    if (msg.startsWith(_kVoicePrefix)) return me ? 'You sent a voice message' : 'Sent a voice message';
    if (msg.startsWith(_kReplyPrefix)) return me ? 'You replied'              : 'Replied';
    return me ? 'You: $msg' : msg;
  }

  // Instagram-style "Sent Xh"/"Read Xh" — only meaningful for the last message
  // *you* sent, comparing its time (conversation.updated is bumped exactly
  // when it's created) against the other person's read cursor.
  String get _statusLabel {
    if (summary.lastSender != currentUsername) return '';
    if (summary.lastMessage.isEmpty) return '';
    final otherRead = summary.otherLastReadAt != null &&
        !summary.otherLastReadAt!.isBefore(summary.updated);
    return otherRead ? 'Read' : 'Sent';
  }

  @override
  Widget build(BuildContext context) {
    final unread    = summary.unreadCount > 0;
    final name      = summary.otherFullName.isNotEmpty ? summary.otherFullName : summary.otherUser;
    final activeNow = _isActiveNow(summary.otherLastActive);
    final count     = summary.unreadCount;
    final timeStr   = _inboxTime(summary.updated);
    final status    = _statusLabel;
    final timeLabel = status.isEmpty ? timeStr : '$status $timeStr';

    // Typing takes priority; then 2+ unread → count; else preview · time
    final previewText = summary.isTyping
        ? 'Typing...'
        : (unread && count >= 2)
            ? '$count new messages · $timeStr'
            : '$_preview · $timeLabel';
    final previewColor = summary.isTyping
        ? (isLight ? const Color(0xff3880f4) : const Color(0xff5b9cf6))
        : unread
            ? (isLight ? Colors.black87 : Colors.white)
            : (isLight ? _kSubLgt : _kSubDark);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            // Avatar — active-now dot only, no ring/badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                _avatar(
                  username: summary.otherUser,
                  url: summary.otherAvatarUrl,
                  radius: 28,
                  isLight: isLight,
                  ring: false,
                ),
                if (activeNow)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _kGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isLight ? _kBgLgt : _kBgDark,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Name + inline-time preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: previewColor,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            // Blue dot for unread
            if (unread) ...[
              const SizedBox(width: 10),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: _kBlue,
                  shape: BoxShape.circle,
                ),
              ),
            ] else
              const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Quick-start chip ─────────────────────────────────────────────────────────

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.username, required this.avatarUrl, required this.isLight, required this.onTap});
  final String username;
  final String avatarUrl;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _avatar(username: username, url: avatarUrl, radius: 26, isLight: isLight),
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: const Color(0xff4cd964),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isLight ? Colors.white : Colors.black,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.user, required this.isLight, required this.onTap});
  final UserProfile user;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _avatar(username: user.username, url: user.avatarUrl, radius: 26, isLight: isLight),
            const SizedBox(height: 5),
            Text(
              user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Search field ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.isLight, required this.onChanged});
  final TextEditingController controller;
  final bool isLight;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: isLight ? Colors.black : Colors.white, fontSize: 15),
      cursorColor: _kBlue,
      decoration: InputDecoration(
        filled: true,
        fillColor: isLight ? const Color(0xffefefef) : const Color(0xff1c1c1e),
        hintText: 'Search',
        hintStyle: TextStyle(color: isLight ? _kSubLgt : _kSubDark, fontSize: 15),
        prefixIcon: Icon(Icons.search_rounded, color: isLight ? _kSubLgt : _kSubDark, size: 20),
        contentPadding: const EdgeInsets.symmetric(vertical: 9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}

// ─── New message sheet ────────────────────────────────────────────────────────

class _NewMessageSheet extends StatefulWidget {
  const _NewMessageSheet({required this.suggestedUsers});
  final List<UserProfile> suggestedUsers;

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isLight  = Theme.of(context).brightness == Brightness.light;
    final textClr  = isLight ? Colors.black : Colors.white;
    final subClr   = isLight ? _kSubLgt : _kSubDark;
    final divClr   = isLight ? _kDivLgt : _kDivDark;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isLight ? const Color(0xffd0d0d0) : const Color(0xff444444),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text('New message', style: TextStyle(color: textClr, fontWeight: FontWeight.w700, fontSize: 16)),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close_rounded, color: textClr, size: 24),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: divClr),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Text('To: ', style: TextStyle(color: textClr, fontWeight: FontWeight.w700, fontSize: 16)),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onSubmitted: (_) {
                      final u = _ctrl.text.trim();
                      if (u.isNotEmpty) Navigator.of(context).pop(u);
                    },
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: textClr, fontSize: 16),
                    cursorColor: _kBlue,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(color: subClr, fontSize: 16),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: divClr),
          if (widget.suggestedUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Suggested', style: TextStyle(color: textClr, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.suggestedUsers.length,
              itemBuilder: (_, i) {
                final u = widget.suggestedUsers[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: _avatar(username: u.username, url: u.avatarUrl, radius: 22, isLight: isLight),
                  title: Text(
                    u.fullName.isNotEmpty ? u.fullName : u.username,
                    style: TextStyle(color: textClr, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: Text('@${u.username}', style: TextStyle(color: subClr, fontSize: 13)),
                  onTap: () => Navigator.of(context).pop(u.username),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty inbox ──────────────────────────────────────────────────────────────

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({required this.isLight, required this.hasSearch, this.isOffline = false});
  final bool isLight;
  final bool hasSearch;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String title;
    final String subtitle;

    if (isOffline && !hasSearch) {
      icon = Icons.wifi_off_rounded;
      title = 'No connection';
      subtitle = 'Your conversations will appear here once you\'re back online.';
    } else if (hasSearch) {
      icon = Icons.chat_bubble_outline_rounded;
      title = 'No results';
      subtitle = 'No conversations match your search.';
    } else {
      icon = Icons.chat_bubble_outline_rounded;
      title = 'Your messages';
      subtitle = 'Send a private message to someone in your city.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 60,
              color: isLight ? const Color(0xffbdbdbd) : const Color(0xff444444),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: isLight ? _kSubLgt : _kSubDark, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ConversationPage
// ─────────────────────────────────────────────────────────────────────────────

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.token,
    required this.currentUsername,
    required this.conversationId,
    required this.otherUsername,
    required this.otherFullName,
    required this.otherAvatarUrl,
    required this.onLogout,
    this.otherLastActive,
    this.onOpenPost,
    this.onOpenUserProfile,
  });

  final String token;
  final String currentUsername;
  final int conversationId;
  final String otherUsername;
  final String otherFullName;
  final String otherAvatarUrl;
  final DateTime? otherLastActive;
  final Future<void> Function() onLogout;
  final void Function(String author, int postId)? onOpenPost;
  final ValueChanged<String>? onOpenUserProfile;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _composer = TextEditingController();
  final _scroll   = ScrollController();
  List<MessageItem> _messages = [];
  bool _loading = true;
  bool _sending = false;
  MessageItem? _replyTo;
  Timer? _presenceTimer;
  Timer? _typingPollTimer;
  Timer? _typingSignalDebounce;
  bool _iTyping = false;
  DateTime? _otherLastActive;
  bool _otherTyping = false;
  bool _blocked = false;
  bool _unavailable = false;
  bool _isOffline = false;
  DateTime? _otherLastReadAt;
  final _messageKeys = <int, GlobalKey>{};

  Future<void> _react(int msgId, String emoji) async {
    final index = _messages.indexWhere((m) => m.id == msgId);
    if (index == -1) return;
    final previous = _messages[index];
    final wasSet = previous.reactionFor(widget.currentUsername) == emoji;
    final optimisticReactions = {
      for (final entry in previous.reactions.entries)
        entry.key: entry.value.where((u) => u != widget.currentUsername).toList(),
    }..removeWhere((_, users) => users.isEmpty);
    if (!wasSet) {
      optimisticReactions.putIfAbsent(emoji, () => []).add(widget.currentUsername);
    }
    setState(() {
      _messages[index] = MessageItem(
        id: previous.id, sender: previous.sender, text: previous.text,
        created: previous.created, reactions: optimisticReactions,
      );
    });
    try {
      final res = await http.post(
        messageReactEndpoint(widget.conversationId, msgId),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'emoji': emoji}),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final updated = MessageItem.fromJson(body['message'] as Map<String, dynamic>);
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1) setState(() => _messages[idx] = updated);
      } else if (mounted) {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1) setState(() => _messages[idx] = previous);
      }
    } catch (_) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) setState(() => _messages[idx] = previous);
    }
  }

  void _showLongPressSheet(MessageItem msg) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final mine    = msg.sender == widget.currentUsername;
    final bg      = isLight ? Colors.white : const Color(0xff1c1c1e);
    final divClr  = isLight ? const Color(0xffe5e5ea) : const Color(0xff2c2c2e);
    final fgClr   = isLight ? Colors.black87 : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isLight ? const Color(0xffC7C7CC) : const Color(0xff48484A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ── Emoji reactions ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in _kQuickEmojis)
                    GestureDetector(
                      onTap: () { Navigator.of(sheetCtx).pop(); _react(msg.id, emoji); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: msg.reactionFor(widget.currentUsername) == emoji
                              ? const Color(0xff3880f4).withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                  // + button → full emoji picker
                  GestureDetector(
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: const Color(0xff1c1c1e),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        isScrollControlled: true,
                        builder: (_) => DraggableScrollableSheet(
                          expand: false,
                          initialChildSize: 0.5,
                          minChildSize: 0.3,
                          maxChildSize: 0.85,
                          builder: (_, ctrl) => _FullEmojiPicker(
                            scrollController: ctrl,
                            onSelect: (emoji) { Navigator.of(context).pop(); _react(msg.id, emoji); },
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLight ? const Color(0xfff2f2f7) : const Color(0xff2c2c2e),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.add_rounded, size: 28,
                          color: isLight ? const Color(0xff3c3c43) : const Color(0xffaeaeb2)),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: divClr, height: 1),
            // ── Actions ───────────────────────────────────────────────
            ListTile(
              leading: Icon(Icons.reply_rounded, color: fgClr),
              title: Text('Reply', style: TextStyle(color: fgClr)),
              onTap: () { Navigator.of(sheetCtx).pop(); _setReplyTo(msg); },
            ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xfff66c6c)),
                title: const Text('Delete message', style: TextStyle(color: Color(0xfff66c6c))),
                onTap: () async { Navigator.of(sheetCtx).pop(); await _deleteMessage(msg); },
              ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: fgClr),
              title: Text('Report', style: TextStyle(color: fgClr)),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showReportMessageSheet(
                  context,
                  conversationId: widget.conversationId,
                  messageId: msg.id,
                  token: widget.token,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMessage(MessageItem msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Color(0xfff66c6c))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final previous = _messages;
    setState(() => _messages = _messages.where((m) => m.id != msg.id).toList());
    try {
      final res = await http.delete(
        messageDeleteEndpoint(widget.conversationId, msg.id),
        headers: authJsonHeaders(widget.token),
      );
      if (res.statusCode != 200) {
        if (mounted) setState(() => _messages = previous);
        return;
      }
      _saveCache(_messages);
    } catch (_) {
      if (mounted) setState(() => _messages = previous);
    }
  }

  // ── Local message cache ───────────────────────────────────────────────────

  Future<File> get _cacheFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/neat_conv_${widget.conversationId}.json');
  }

  Future<void> _saveCache(List<MessageItem> msgs) async {
    try {
      final file = await _cacheFile;
      final data = msgs.map((m) => {
        'id': m.id,
        'sender': m.sender,
        'text': m.text,
        'created': m.created.toIso8601String(),
        'reactions': m.reactions,
      }).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadCache() async {
    try {
      final file = await _cacheFile;
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as List;
      final msgs = data.whereType<Map<String, dynamic>>().map(MessageItem.fromJson).toList();
      if (!mounted || msgs.isEmpty) return;
      setState(() { _messages = msgs; _loading = false; });
      _scrollToBottom(jump: true);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _otherLastActive = widget.otherLastActive;
    _loadCache();
    _load(initial: true);
    _pingPresence();
    _presenceTimer   = Timer.periodic(const Duration(seconds: 30), (_) => _pingPresence());
    _typingPollTimer = Timer.periodic(const Duration(seconds: 3),  (_) => _poll());
    _composer.addListener(_onComposerChanged);
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _typingPollTimer?.cancel();
    _typingSignalDebounce?.cancel();
    _composer.removeListener(_onComposerChanged);
    if (_iTyping) _sendTypingSignal(false);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onComposerChanged() {
    final hasText = _composer.text.isNotEmpty;
    if (hasText && !_iTyping) {
      _iTyping = true;
      _sendTypingSignal(true);
    }
    _typingSignalDebounce?.cancel();
    if (hasText) {
      _typingSignalDebounce = Timer(const Duration(seconds: 4), () {
        _iTyping = false;
        _sendTypingSignal(false);
      });
    } else {
      _iTyping = false;
      _sendTypingSignal(false);
    }
  }

  Future<void> _sendTypingSignal(bool typing) async {
    try {
      await http.post(
        typingEndpoint(widget.conversationId),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'typing': typing}),
      );
    } catch (_) {}
  }

  // Fetches new messages + typing state every 3 seconds.
  Future<void> _poll() async {
    // Run both requests in parallel.
    final results = await Future.wait([
      http.get(messageConversationEndpoint(widget.conversationId),
          headers: authGetHeaders(widget.token)).catchError((_) => http.Response('', 0)),
      http.get(typingEndpoint(widget.conversationId),
          headers: authGetHeaders(widget.token)).catchError((_) => http.Response('', 0)),
    ]);
    if (!mounted) return;

    // ── messages ──────────────────────────────────────────────────────
    final convRes = results[0];
    if (convRes.statusCode == 200) {
      final body = jsonDecode(convRes.body) as Map<String, dynamic>;
      final conv = body['conversation'] as Map<String, dynamic>?;
      final msgs = (body['messages'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MessageItem.fromJson)
          .toList();
      final serverIds  = msgs.map((m) => m.id).toSet();
      final serverKeys = msgs.map((m) => '${m.sender}\x00${m.text}').toSet();
      final localOnly  = _messages
          .where((m) => !serverIds.contains(m.id))
          .where((m) => m.id >= 0 || !serverKeys.contains('${m.sender}\x00${m.text}'))
          .where((m) => m.id >= 0 || DateTime.now().difference(m.created) < const Duration(seconds: 20))
          .toList();
      final merged = [...msgs, ...localOnly]..sort((a, b) => a.created.compareTo(b.created));
      final hadNewFromOther = merged.length > _messages.length &&
          merged.last.sender != widget.currentUsername;
      final lastActive  = DateTime.tryParse(conv?['otherLastActive']?.toString() ?? '');
      final otherReadAt = DateTime.tryParse(conv?['otherLastReadAt']?.toString() ?? '');
      setState(() {
        _messages = merged;
        if (lastActive != null)  _otherLastActive  = lastActive;
        if (otherReadAt != null) _otherLastReadAt  = otherReadAt;
        if (conv != null) _blocked = conv['viewerBlockedOther'] == true;
      });
      _saveCache(merged);
      if (hadNewFromOther) _scrollToBottom();
    }

    // ── typing ────────────────────────────────────────────────────────
    final typRes = results[1];
    if (typRes.statusCode == 200 && mounted) {
      final isTyping = (jsonDecode(typRes.body) as Map<String, dynamic>)['otherIsTyping'] == true;
      if (isTyping != _otherTyping) {
        setState(() => _otherTyping = isTyping);
        if (isTyping) _scrollToBottom();
      }
    }
  }

  Future<void> _pingPresence() async {
    try {
      await http.post(presenceEndpoint, headers: authJsonHeaders(widget.token));
    } catch (_) {}
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(max);
      } else {
        _scroll.animateTo(max, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final res = await http.get(
        messageConversationEndpoint(widget.conversationId),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode == 401) return widget.onLogout();
      if (res.statusCode == 404) {
        if (mounted) setState(() { _loading = false; _unavailable = true; });
        return;
      }
      if (res.statusCode != 200) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final conv = body['conversation'] as Map<String, dynamic>?;
      final msgs = (body['messages'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MessageItem.fromJson)
          .toList();
      if (!mounted) return;
      // Merge: keep locally-cached messages the server didn't return.
      // For optimistic (negative-ID) entries, also drop them if the server
      // returned a matching sender+text — that means the send was confirmed
      // and the real message has a new positive ID. Without this check,
      // re-entering the DM would show the message twice.
      final serverIds   = msgs.map((m) => m.id).toSet();
      final serverKeys  = msgs.map((m) => '${m.sender}\x00${m.text}').toSet();
      final localOnly   = _messages
          .where((m) => !serverIds.contains(m.id))
          .where((m) => m.id >= 0 || !serverKeys.contains('${m.sender}\x00${m.text}'))
          // An optimistic (negative-ID) message the server still hasn't echoed back after
          // this long clearly failed to send (e.g. a send error the client didn't catch) —
          // drop it so it doesn't linger forever as an unremovable, undeletable phantom.
          .where((m) => m.id >= 0 || DateTime.now().difference(m.created) < const Duration(seconds: 20))
          .toList();
      final merged = [...msgs, ...localOnly]
        ..sort((a, b) => a.created.compareTo(b.created));
      final otherReadAt = DateTime.tryParse(conv?['otherLastReadAt']?.toString() ?? '');
      setState(() {
        _messages = merged;
        _loading = false;
        if (conv != null) _blocked = conv['viewerBlockedOther'] == true;
        if (otherReadAt != null) _otherLastReadAt = otherReadAt;
      });
      _saveCache(merged);
      _scrollToBottom(jump: initial);
    } catch (_) {
      // keep whatever messages are already loaded rather than blanking the screen
      if (mounted) setState(() { _loading = false; _isOffline = true; });
    }
  }

  Future<void> _sendRaw(String text, {bool clearInput = false}) async {
    if (text.isEmpty || _sending) return;
    if (clearInput) _composer.clear();

    final opt = MessageItem(
      id: -DateTime.now().millisecondsSinceEpoch,
      sender: widget.currentUsername,
      text: text,
      created: DateTime.now(),
    );
    final newList = [..._messages, opt];
    setState(() { _messages = newList; _sending = true; });
    _saveCache(newList);
    _scrollToBottom();

    try {
      final res = await http.post(
        messageConversationEndpoint(widget.conversationId),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'text': text}),
      );
      if (res.statusCode == 401) return widget.onLogout();
      if (res.statusCode != 201) {
        if (mounted) {
          setState(() => _messages.removeWhere((m) => m.id == opt.id));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message failed to send')),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _messages.removeWhere((m) => m.id == opt.id));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText() {
    final text = _composer.text.trim();
    if (text.isEmpty) return Future.value();
    _typingSignalDebounce?.cancel();
    _iTyping = false;
    _sendTypingSignal(false);
    if (_replyTo != null) {
      final msg = _replyTo!;
      _clearReply();
      return _sendRaw(
        '$_kReplyPrefix${jsonEncode({'sender': msg.sender, 'preview': _replyPreview(msg), 'text': text, 'id': msg.id})}',
        clearInput: true,
      );
    }
    return _sendRaw(text, clearInput: true);
  }

  Future<void> _sendImage(Uint8List bytes) =>
      _sendRaw('$_kImagePrefix${base64Encode(bytes)}');

  Future<void> _sendVoice(Uint8List bytes, int durationSecs) =>
      _sendRaw('$_kVoicePrefix${base64Encode(bytes)}|$durationSecs');

  void _setReplyTo(MessageItem msg) => setState(() => _replyTo = msg);
  void _clearReply() => setState(() => _replyTo = null);

  int? _findReplyTarget({required String sender, required String preview, required int? id}) {
    if (id != null && _messageKeys.containsKey(id)) return id;
    for (final m in _messages.reversed) {
      if (m.sender != sender) continue;
      if (_replyPreview(m) == preview) return m.id;
    }
    return null;
  }

  Future<void> _scrollToMessage(int msgId) async {
    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx == -1) return;

    // Step 1: animate to approx position so ListView builds the target item.
    if (_scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      final rough = (idx / _messages.length * max).clamp(0.0, max);
      await _scroll.animateTo(
        rough,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }

    // Step 2: fine-tune now that the item is in the tree.
    await Future.delayed(const Duration(milliseconds: 32));
    final key = _messageKeys[msgId];
    if (!mounted || key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
  }

  String _replyPreview(MessageItem msg) {
    if (_parseImage(msg.text) != null) return '📷 Photo';
    if (_parseVoice(msg.text) != null) return '🎤 Voice message';
    if (_parsePost(msg.text) != null) return '📎 Post';
    // Unwrap nested reply so we never store raw JSON as preview.
    final inner = _parseReply(msg.text);
    final t = inner != null ? inner.text : msg.text;
    return t.length > 80 ? '${t.substring(0, 80)}…' : t;
  }

  Future<void> _showOptionsSheet() async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isLight ? _kBgLgt : _kBgDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                _blocked ? Icons.check_circle_outline : Icons.block,
                color: _blocked ? (isLight ? Colors.black : Colors.white) : const Color(0xfff66c6c),
              ),
              title: Text(
                _blocked ? 'Unblock User' : 'Block User',
                style: TextStyle(
                  color: _blocked ? (isLight ? Colors.black : Colors.white) : const Color(0xfff66c6c),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _blocked ? _confirmUnblock() : _confirmBlock();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBlock() async {
    final name = widget.otherUsername;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Block @$name? They won\'t be able to message you or find your '
          'profile or posts, and this conversation will be removed from '
          'your inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block', style: TextStyle(color: Color(0xfff66c6c))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _toggleBlock(blockedMessage: 'User blocked');
  }

  Future<void> _confirmUnblock() async {
    await _toggleBlock(blockedMessage: 'User unblocked');
  }

  Future<void> _toggleBlock({required String blockedMessage}) async {
    try {
      final res = await http.post(
        userBlockEndpoint(widget.otherUsername),
        headers: authJsonHeaders(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_extractError(res.body) ?? 'Something went wrong')),
        );
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final target = body['user'] as Map<String, dynamic>?;
      setState(() => _blocked = target?['isBlocked'] == true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blockedMessage)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg      = isLight ? _kBgLgt : _kBgDark;
    final name    = widget.otherFullName.isNotEmpty ? widget.otherFullName : widget.otherUsername;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 44,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: isLight ? Colors.black : Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: widget.onOpenUserProfile != null
              ? () => widget.onOpenUserProfile!(widget.otherUsername)
              : null,
          child: Row(
            children: [
              _avatar(
                username: widget.otherUsername,
                url: widget.otherAvatarUrl,
                radius: 20,
                isLight: isLight,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Builder(builder: (_) {
                      final label = _presenceLabel(_otherLastActive);
                      final activeNow = _isActiveNow(_otherLastActive);
                      return Text(
                        label ?? '@${widget.otherUsername}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: activeNow
                              ? _kGreen
                              : label != null
                                  ? (isLight ? _kSubLgt : _kSubDark)
                                  : (isLight ? _kSubLgt : _kSubDark),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: isLight ? Colors.black : Colors.white),
            onPressed: _showOptionsSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _kBlue))
                : _messages.isEmpty
                    ? _EmptyConversation(
                        username: widget.otherUsername,
                        avatarUrl: widget.otherAvatarUrl,
                        fullName: widget.otherFullName,
                        isLight: isLight,
                      )
                    : ListView.builder(
                        controller: _scroll,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        itemCount: _messages.length + (_otherTyping ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _messages.length) {
                            // Typing indicator bubble
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _avatar(
                                    username: widget.otherUsername,
                                    url: widget.otherAvatarUrl,
                                    radius: 14,
                                    isLight: isLight,
                                  ),
                                  const SizedBox(width: 6),
                                  _TypingBubble(isLight: isLight),
                                ],
                              ),
                            );
                          }
                          final msg    = _messages[i];
                          final mine   = msg.sender == widget.currentUsername;
                          final isLast = _isLastInGroup(_messages, i);
                          // Show "Read" under the last message I sent that the other person has read.
                          bool showRead = false;
                          if (mine && _otherLastReadAt != null) {
                            final isRead = !msg.created.isAfter(_otherLastReadAt!);
                            if (isRead) {
                              showRead = !_messages.skip(i + 1).any((m) =>
                                  m.sender == widget.currentUsername &&
                                  !m.created.isAfter(_otherLastReadAt!));
                            }
                          }
                          final msgKey = _messageKeys.putIfAbsent(msg.id, () => GlobalKey());
                          final replyData = _parseReply(msg.text);
                          return Column(
                            key: msgKey,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_showDivider(_messages, i))
                                _TimeDivider(time: msg.created, isLight: isLight),
                              _MessageRow(
                                message: msg,
                                mine: mine,
                                isLast: isLast,
                                showRead: showRead,
                                otherUsername: widget.otherUsername,
                                otherAvatarUrl: widget.otherAvatarUrl,
                                isLight: isLight,
                                onOpenPost: widget.onOpenPost,
                                onOpenUserProfile: widget.onOpenUserProfile != null
                                    ? () => widget.onOpenUserProfile!(widget.otherUsername)
                                    : null,
                                reaction: msg.reactionFor(widget.currentUsername),
                                onReply: () => _setReplyTo(msg),
                                onDoubleTap: () => _react(msg.id, '❤️'),
                                onLongPress: msg.id >= 0 ? () => _showLongPressSheet(msg) : null,
                                onTapQuote: replyData != null ? () {
                                  final targetId = _findReplyTarget(
                                    sender: replyData.sender,
                                    preview: replyData.preview,
                                    id: replyData.id,
                                  );
                                  if (targetId != null) _scrollToMessage(targetId);
                                } : null,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          if (_isOffline) _ConvOfflineBanner(isLight: isLight),
          if (_unavailable)
            _BlockedBanner(isLight: isLight, message: 'This conversation is no longer available')
          else if (_blocked)
            _BlockedBanner(isLight: isLight, message: 'User blocked')
          else
            _Composer(
              controller: _composer,
              isLight: isLight,
              sending: _sending,
              onSendText: _sendText,
              onSendImage: _sendImage,
              onSendVoice: _sendVoice,
              replyTo: _replyTo,
              onClearReply: _clearReply,
            ),
        ],
      ),
    );
  }
}

// ─── Message row ──────────────────────────────────────────────────────────────

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.mine,
    required this.isLast,
    required this.otherUsername,
    required this.otherAvatarUrl,
    required this.isLight,
    required this.onOpenPost,
    this.onOpenUserProfile,
    this.onReply,
    this.reaction,
    this.onDoubleTap,
    this.onLongPress,
    this.showRead = false,
    this.onTapQuote,
  });

  final MessageItem message;
  final bool mine;
  final bool isLast;
  final bool showRead;
  final String otherUsername;
  final String otherAvatarUrl;
  final bool isLight;
  final void Function(String, int)? onOpenPost;
  final VoidCallback? onOpenUserProfile;
  final VoidCallback? onReply;
  final String? reaction;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onTapQuote;

  Widget _content() {
    final replyData = _parseReply(message.text);
    if (replyData != null) {
      return _ReplyMessageBubble(replyData: replyData, mine: mine, isLast: isLast, isLight: isLight, onTapQuote: onTapQuote);
    }

    final imgBytes  = _parseImage(message.text);
    if (imgBytes != null) {
      return _ImageBubble(bytes: imgBytes, mine: mine, isLast: isLast);
    }

    final voiceData = _parseVoice(message.text);
    if (voiceData != null) {
      return _VoiceBubble(
        bytes: voiceData.bytes,
        durationSecs: voiceData.secs,
        mine: mine,
        isLast: isLast,
        isLight: isLight,
      );
    }

    final postData = _parsePost(message.text);
    if (postData != null) {
      return _SharedPostCard(
        data: postData,
        isLight: isLight,
        onTap: onOpenPost != null
            ? () => onOpenPost!(
                  postData['author']?.toString() ?? '',
                  (postData['id'] as num?)?.toInt() ?? 0,
                )
            : null,
      );
    }

    return _Bubble(text: message.text, mine: mine, isLast: isLast, isLight: isLight);
  }

  Widget _wrapGesture(Widget child) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: child,
      );

  Widget _reactionBadge() => Container(
        margin: EdgeInsets.only(
          top: 2,
          left: mine ? 0 : 38,
          right: mine ? 4 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xff2a2a2a),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xff1a1a1a), width: 1.5),
        ),
        child: Text(reaction!, style: const TextStyle(fontSize: 14)),
      );

  @override
  Widget build(BuildContext context) {
    final maxW      = MediaQuery.sizeOf(context).width * 0.70;
    final bottomPad = reaction != null ? 2.0 : (isLast ? 6.0 : 2.0);
    final readColor = isLight ? const Color(0xff8e8e93) : const Color(0xff636366);

    if (mine) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _wrapGesture(
                  onReply != null
                      ? _SwipeToReply(
                          onReply: onReply!, isLight: isLight, reverse: true,
                          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: _content()))
                      : ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: _content()),
                ),
              ],
            ),
            if (reaction != null) _reactionBadge(),
            if (reaction != null) SizedBox(height: isLast ? 4 : 2),
            if (showRead)
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 2),
                child: Text('Read', style: TextStyle(fontSize: 11, color: readColor)),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isLast)
                GestureDetector(
                  onTap: onOpenUserProfile,
                  child: _avatar(username: otherUsername, url: otherAvatarUrl, radius: 16, isLight: isLight),
                )
              else
                const SizedBox(width: 32),
              const SizedBox(width: 6),
              _wrapGesture(
                onReply != null
                    ? _SwipeToReply(onReply: onReply!, isLight: isLight,
                        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: _content()))
                    : ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: _content()),
              ),
            ],
          ),
          if (reaction != null) _reactionBadge(),
          if (reaction != null) SizedBox(height: isLast ? 4 : 2),
        ],
      ),
    );
  }
}

// ─── Text bubble ──────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine, required this.isLast, required this.isLight});
  final String text;
  final bool mine;
  final bool isLast;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final bg        = mine ? _kBlue : (isLight ? _kOtherLgt : _kOtherDark);
    final textColor = mine ? Colors.white : (isLight ? Colors.black : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: _bubbleRadius(mine, isLast)),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 15, height: 1.35)),
    );
  }
}

// ─── Image bubble ─────────────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.bytes, required this.mine, required this.isLast});
  final Uint8List bytes;
  final bool mine;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullscreen(context),
      child: ClipRRect(
        borderRadius: _bubbleRadius(mine, isLast),
        child: Image.memory(bytes, width: 220, height: 220, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      pageBuilder: (ctx, a1, a2) {
        final topPad = MediaQuery.of(ctx).padding.top;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      width: MediaQuery.of(ctx).size.width,
                      height: MediaQuery.of(ctx).size.height,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: topPad + 12,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
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
            ],
          ),
        );
      },
    ));
  }
}

// ─── Voice bubble ─────────────────────────────────────────────────────────────

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({
    required this.bytes,
    required this.durationSecs,
    required this.mine,
    required this.isLast,
    required this.isLight,
  });
  final Uint8List bytes;
  final int durationSecs;
  final bool mine;
  final bool isLast;
  final bool isLight;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  late final AudioPlayer _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _position = Duration.zero; });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    if (_tempPath != null) try { File(_tempPath!).deleteSync(); } catch (_) {}
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) { await _player.pause(); return; }
    if (_tempPath == null) {
      final dir = await getTemporaryDirectory();
      _tempPath = '${dir.path}/neat_play_${identityHashCode(this)}.aac';
      await File(_tempPath!).writeAsBytes(widget.bytes);
    }
    await _player.play(DeviceFileSource(_tempPath!));
  }

  @override
  Widget build(BuildContext context) {
    final bg       = widget.mine ? _kBlue : (widget.isLight ? _kOtherLgt : _kOtherDark);
    final fg       = widget.mine ? Colors.white : (widget.isLight ? Colors.black87 : Colors.white);
    final total    = widget.durationSecs;
    final elapsed  = _position.inSeconds;
    final remaining = (total - elapsed).clamp(0, total);
    final mm = (remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (remaining  % 60).toString().padLeft(2, '0');

    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: _bubbleRadius(widget.mine, widget.isLast)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: fg,
              size: 28,
            ),
            const SizedBox(width: 8),
            _WaveformBars(
              progress: total > 0 ? elapsed / total : 0,
              color: fg,
            ),
            const SizedBox(width: 8),
            Text(
              '$mm:$ss',
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Waveform bars ────────────────────────────────────────────────────────────

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.progress, required this.color});
  final double progress;
  final Color color;

  static const _h = [8.0, 15.0, 22.0, 10.0, 18.0, 13.0, 24.0, 7.0, 17.0, 20.0,
                      11.0, 14.0, 6.0, 19.0, 12.0, 9.0, 23.0, 16.0, 10.0, 14.0];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_h.length, (i) {
          final played = i / _h.length < progress;
          return Container(
            width: 3,
            height: _h[i],
            decoration: BoxDecoration(
              color: color.withValues(alpha: played ? 1.0 : 0.35),
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Time divider ─────────────────────────────────────────────────────────────

class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.time, required this.isLight});
  final DateTime time;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          _chatTime(time),
          style: TextStyle(color: isLight ? _kSubLgt : _kSubDark, fontSize: 12),
        ),
      ),
    );
  }
}

// ─── Blocked banner ───────────────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble({required this.isLight});
  final bool isLight;
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isLight ? _kOtherLgt : _kOtherDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = ((_ctrl.value - i * 0.18) % 1.0).clamp(0.0, 1.0);
            final dy = t < 0.5 ? -4.0 * (t / 0.5) : -4.0 * ((1.0 - t) / 0.5);
            return Transform.translate(
              offset: Offset(0, dy),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.isLight ? const Color(0xff8e8e8e) : const Color(0xff8e8e8e),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner({required this.isLight, this.message = 'User blocked'});

  final bool isLight;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: isLight ? _kInputLgt : _kInputDark,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isLight ? _kSubLgt : _kSubDark,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Composer  (stateful — owns recording + image picker)
// ─────────────────────────────────────────────────────────────────────────────

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.isLight,
    required this.sending,
    required this.onSendText,
    required this.onSendImage,
    required this.onSendVoice,
    this.replyTo,
    this.onClearReply,
  });

  final TextEditingController controller;
  final bool isLight;
  final bool sending;
  final VoidCallback onSendText;
  final Future<void> Function(Uint8List) onSendImage;
  final Future<void> Function(Uint8List, int) onSendVoice;
  final MessageItem? replyTo;
  final VoidCallback? onClearReply;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _recorder = AudioRecorder();
  bool _recording  = false;
  int  _recSecs    = 0;
  Timer? _timer;
  String? _recPath;

  void _onTextChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1200,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      await widget.onSendImage(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _pickGif() async {
    final completer = Completer<String?>();
    final listener = _GiphyListener(
      onSelect: (GiphyMedia media) {
        final url = media.images.fixedWidth?.gifUrl ??
            media.images.original?.gifUrl ??
            '';
        if (!completer.isCompleted) completer.complete(url.isNotEmpty ? url : null);
      },
      onDismissed: () {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    GiphyDialog.instance.addListener(listener);
    GiphyDialog.instance.configure(
      settings: GiphySettings(
        theme: GiphyTheme.automaticTheme,
        mediaTypeConfig: [GiphyContentType.gif, GiphyContentType.sticker],
        selectedContentType: GiphyContentType.gif,
        showSuggestionsBar: true,
        showConfirmationScreen: false,
      ),
    );
    GiphyDialog.instance.show();
    final url = await completer.future;
    GiphyDialog.instance.removeListener(listener);
    if (!mounted || url == null) return;
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) await widget.onSendImage(res.bodyBytes);
    } catch (_) {}
  }

  // ── Voice recording ───────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_recording) return;
    final ok = await _recorder.hasPermission();
    if (!ok || !mounted) return;
    final dir = await getTemporaryDirectory();
    _recPath = '${dir.path}/neat_voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: _recPath!);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recSecs++);
    });
    setState(() { _recording = true; _recSecs = 0; });
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    if (!_recording) return;
    _timer?.cancel();
    _timer = null;
    final dur  = _recSecs;
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() { _recording = false; _recSecs = 0; });
    if (cancel || path == null) {
      if (path != null) try { File(path).deleteSync(); } catch (_) {}
      return;
    }
    final bytes = await File(path).readAsBytes();
    try { File(path).deleteSync(); } catch (_) {}
    if (bytes.isNotEmpty) await widget.onSendVoice(bytes, dur > 0 ? dur : 1);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyTo != null)
            _ReplyPreviewBar(
              replyTo: widget.replyTo!,
              isLight: widget.isLight,
              onClear: widget.onClearReply ?? () {},
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _recording ? _buildRecordingBar() : _buildNormalBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    final mm = (_recSecs ~/ 60).toString().padLeft(2, '0');
    final ss = (_recSecs  % 60).toString().padLeft(2, '0');
    final textClr = widget.isLight ? Colors.black : Colors.white;
    return Container(
      key: const ValueKey('rec'),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 26),
            padding: EdgeInsets.zero,
            onPressed: () => _stopRecording(cancel: true),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                const _PulsingDot(),
                const SizedBox(width: 8),
                Text(
                  '$mm:$ss',
                  style: TextStyle(color: textClr, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Text(
                  'Recording...',
                  style: TextStyle(color: widget.isLight ? _kSubLgt : _kSubDark, fontSize: 13),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _stopRecording(cancel: false),
            child: Container(
              width: 38, height: 38,
              decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalBar() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final iconClr = widget.isLight ? Colors.black : Colors.white;
    final pillBg  = widget.isLight ? _kInputLgt : _kInputDark;
    final border  = widget.isLight
        ? Border.all(color: const Color(0xffd0d0d0))
        : Border.all(color: const Color(0xff2e2e2e));

    return Container(
      key: const ValueKey('normal'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Container(
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(28),
          border: border,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Camera inside pill with circle background
            GestureDetector(
              onTap: () => _pickImage(ImageSource.camera),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.isLight
                        ? const Color(0xffd0d0d0)
                        : const Color(0xff3a3a3a),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.camera_alt_rounded, color: iconClr, size: 18),
                ),
              ),
            ),
            // Text field
            Expanded(
              child: TextField(
                controller: widget.controller,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  color: widget.isLight ? Colors.black : Colors.white,
                  fontSize: 15,
                ),
                cursorColor: _kBlue,
                decoration: InputDecoration(
                  hintText: 'Μήνυμα...',
                  hintStyle: TextStyle(
                    color: widget.isLight ? _kSubLgt : _kSubDark,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
            // Right side: send OR mic + gallery + gif
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: hasText
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                      child: GestureDetector(
                        key: const ValueKey('send'),
                        onTap: widget.sending ? null : widget.onSendText,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                              color: _kBlue, shape: BoxShape.circle),
                          child: widget.sending
                              ? const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  ),
                                )
                              : const Icon(Icons.arrow_upward_rounded,
                                  color: Colors.white, size: 20),
                        ),
                      ),
                    )
                  : Padding(
                      key: const ValueKey('actions'),
                      padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _startRecording,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(Icons.mic_none_rounded, color: iconClr, size: 26),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _pickImage(ImageSource.gallery),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(Icons.photo_outlined, color: iconClr, size: 24),
                            ),
                          ),
                          GestureDetector(
                            onTap: _pickGif,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 5, right: 2),
                              child: Icon(Icons.gif_box_outlined, color: iconClr, size: 28),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Giphy listener ──────────────────────────────────────────────────────────

class _GiphyListener implements GiphyMediaSelectionListener {
  _GiphyListener({required this.onSelect, required this.onDismissed});
  final void Function(GiphyMedia media) onSelect;
  final VoidCallback onDismissed;

  @override
  void onMediaSelect(GiphyMedia media) => onSelect(media);

  @override
  void onDismiss() => onDismissed();
}

// ─── Pulsing red dot for recording indicator ──────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 10, height: 10,
        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      ),
    );
  }
}

// ─── Empty conversation ───────────────────────────────────────────────────────

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.username,
    required this.avatarUrl,
    required this.fullName,
    required this.isLight,
  });
  final String username;
  final String avatarUrl;
  final String fullName;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final name = fullName.isNotEmpty ? fullName : username;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _avatar(username: username, url: avatarUrl, radius: 44, isLight: isLight),
          const SizedBox(height: 14),
          Text(
            name,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text('@$username', style: TextStyle(color: isLight ? _kSubLgt : _kSubDark, fontSize: 14)),
          const SizedBox(height: 20),
          Text(
            'Say hi to start the conversation!',
            style: TextStyle(color: isLight ? _kSubLgt : _kSubDark, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─── Shared post card ─────────────────────────────────────────────────────────

class _SharedPostCard extends StatelessWidget {
  const _SharedPostCard({required this.data, required this.isLight, required this.onTap});
  final Map<String, dynamic> data;
  final bool isLight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final author   = data['author']?.toString() ?? '';
    final text     = data['text']?.toString() ?? '';
    final imageUrl = data['imageUrl']?.toString() ?? '';
    final likes    = (data['likes'] as num?)?.toInt() ?? 0;
    final cardBg   = isLight ? Colors.white : const Color(0xff1c1c1e);
    final border   = isLight ? const Color(0xffe0e0e0) : const Color(0xff333333);
    final textClr  = isLight ? Colors.black : Colors.white;
    final sub      = isLight ? _kSubLgt : _kSubDark;
    final imgBytes = imageUrl.isNotEmpty ? _dataUrlBytes(imageUrl) : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 1.6,
                child: imgBytes != null
                    ? Image.memory(imgBytes, fit: BoxFit.cover)
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        cacheManager: imageCacheManager,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                      ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff3a3a3a),
                        child: Text(
                          initialFor(author),
                          style: TextStyle(fontSize: 10, color: textClr, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('@$author', style: TextStyle(color: textClr, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      text.length > 100 ? '${text.substring(0, 100)}…' : text,
                      style: TextStyle(color: sub, fontSize: 13, height: 1.35),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (likes > 0) ...[
                        const Icon(Icons.favorite_rounded, size: 12, color: Colors.red),
                        const SizedBox(width: 3),
                        Text('$likes', style: TextStyle(color: sub, fontSize: 12)),
                        const SizedBox(width: 8),
                      ],
                      if (onTap != null)
                        const Text(
                          'View post',
                          style: TextStyle(color: _kBlue, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                    ],
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

// ─── Swipe-to-reply wrapper ───────────────────────────────────────────────────

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.child,
    required this.onReply,
    required this.isLight,
    this.reverse = false,
  });
  final Widget child;
  final VoidCallback onReply;
  final bool isLight;
  final bool reverse; // true → swipe left (own messages)

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _offset = 0;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // For reverse (left-swipe), invert dx so offset is always positive internally.
    final delta = widget.reverse ? -d.delta.dx : d.delta.dx;
    if (delta < 0 && _offset <= 0) return;
    final newOffset = (_offset + delta).clamp(0.0, 72.0);
    setState(() => _offset = newOffset);
    if (_offset >= 56 && !_triggered) {
      _triggered = true;
      HapticFeedback.lightImpact();
      widget.onReply();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    _triggered = false;
    final startOffset = _offset;
    _ctrl.reset();
    final anim = Tween<double>(begin: startOffset, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    anim.addListener(() { if (mounted) setState(() => _offset = anim.value); });
    _ctrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final progress   = (_offset / 56).clamp(0.0, 1.0);
    final translate  = widget.reverse ? -_offset : _offset;
    final iconCircle = Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: widget.isLight ? const Color(0xffe0e0e0) : const Color(0xff3a3a3a),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.reply_rounded, size: 16,
          color: widget.isLight ? Colors.black54 : Colors.white54),
    );
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.reverse)
            Positioned(
              right: _offset - 36,
              top: 0, bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(scale: 0.7 + progress * 0.3, child: iconCircle),
                ),
              ),
            )
          else
            Positioned(
              left: _offset - 36,
              top: 0, bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(scale: 0.7 + progress * 0.3, child: iconCircle),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(translate, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ─── Reply message bubble (quote + reply text) ────────────────────────────────

class _ReplyMessageBubble extends StatelessWidget {
  const _ReplyMessageBubble({
    required this.replyData,
    required this.mine,
    required this.isLast,
    required this.isLight,
    this.onTapQuote,
  });

  final ({String sender, String preview, String text, int? id}) replyData;
  final bool mine;
  final bool isLast;
  final bool isLight;
  final VoidCallback? onTapQuote;

  @override
  Widget build(BuildContext context) {
    final bubbleBg   = mine ? _kBlue : (isLight ? _kOtherLgt : _kOtherDark);
    final textColor  = mine ? Colors.white : (isLight ? Colors.black : Colors.white);
    final quoteBg    = mine
        ? Colors.white.withValues(alpha: 0.18)
        : (isLight ? Colors.black.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.10));
    final senderClr  = mine ? Colors.white : _kBlue;
    final previewClr = mine
        ? Colors.white.withValues(alpha: 0.68)
        : (isLight ? Colors.black54 : Colors.white54);

    return ClipRRect(
      borderRadius: _bubbleRadius(mine, isLast),
      child: Container(
        color: bubbleBg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── quoted block ─────────────────────────────────────────
            GestureDetector(
              onTap: onTapQuote,
              child: Container(
                width: double.infinity,
                color: quoteBg,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      replyData.sender,
                      style: TextStyle(color: senderClr, fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    if (replyData.preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        replyData.preview,
                        style: TextStyle(color: previewClr, fontSize: 12.5, height: 1.3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ── reply text ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(
                replyData.text,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reply preview bar (shown above composer) ─────────────────────────────────

class _ReplyPreviewBar extends StatelessWidget {
  const _ReplyPreviewBar({required this.replyTo, required this.isLight, required this.onClear});
  final MessageItem replyTo;
  final bool isLight;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bg      = isLight ? const Color(0xfff2f2f2) : const Color(0xff1a1a1a);
    final subClr  = isLight ? _kSubLgt : _kSubDark;
    final divClr  = isLight ? const Color(0xffe0e0e0) : const Color(0xff2a2a2a);

    String preview;
    if (_parseImage(replyTo.text) != null) {
      preview = '📷 Photo';
    } else if (_parseVoice(replyTo.text) != null) {
      preview = '🎤 Voice message';
    } else if (_parsePost(replyTo.text) != null) {
      preview = '📎 Post';
    } else {
      final inner = _parseReply(replyTo.text);
      final raw   = inner != null ? inner.text : replyTo.text;
      preview = raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: divClr)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(color: _kBlue, borderRadius: BorderRadius.circular(1.5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Replying to @${replyTo.sender}',
                    style: const TextStyle(
                        color: _kBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(preview,
                    style: TextStyle(color: subClr, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: subClr),
            padding: const EdgeInsets.all(8),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

// ─── Reaction picker overlay ──────────────────────────────────────────────────

const _kQuickEmojis = ['❤️', '😂', '😮', '😢', '😡', '👍'];

// (overlay removed — long-press now opens bottom sheet)
class _ReactionPickerOverlay extends StatelessWidget {
  const _ReactionPickerOverlay({
    required this.pos,
    required this.screenSize,
    required this.onSelect,
    required this.onMore,
  }) : current = null;

  final Offset pos;
  final Size screenSize;
  final String? current;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    const pickerW = 292.0;
    const pickerH = 52.0;
    const margin = 12.0;

    double left = pos.dx - pickerW / 2;
    left = left.clamp(margin, screenSize.width - pickerW - margin);

    double top = pos.dy - pickerH - 16;
    if (top < margin + MediaQuery.of(context).padding.top) {
      top = pos.dy + 16;
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: _ReactionPill(
              current: current,
              onSelect: onSelect,
              onMore: onMore,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionPill extends StatefulWidget {
  const _ReactionPill({required this.current, required this.onSelect, required this.onMore});
  final String? current;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  @override
  State<_ReactionPill> createState() => _ReactionPillState();
}

class _ReactionPillState extends State<_ReactionPill> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xff2c2c2e),
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in _kQuickEmojis)
              _EmojiBtn(
                emoji: emoji,
                selected: widget.current == emoji,
                onTap: () => widget.onSelect(emoji),
              ),
            Container(width: 1, height: 28, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 4)),
            _MoreBtn(onTap: widget.onMore),
          ],
        ),
      ),
    );
  }
}

class _EmojiBtn extends StatefulWidget {
  const _EmojiBtn({required this.emoji, required this.selected, required this.onTap});
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_EmojiBtn> createState() => _EmojiBtnState();
}

class _EmojiBtnState extends State<_EmojiBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120), lowerBound: 0.8, upperBound: 1.0, value: 1.0);
    _scale = _ctrl;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _press() async {
    await _ctrl.reverse();
    widget.onTap();
    _ctrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _press,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: widget.selected
              ? BoxDecoration(color: Colors.white12, shape: BoxShape.circle)
              : null,
          child: Center(child: Text(widget.emoji, style: const TextStyle(fontSize: 22))),
        ),
      ),
    );
  }
}

class _MoreBtn extends StatelessWidget {
  const _MoreBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(left: 2),
        decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─── Full emoji picker ────────────────────────────────────────────────────────

const _kAllEmojis = [
  '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','☺️','😚','😙',
  '😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬','🤥',
  '😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤧','🥵','🥶','😵','🤯','🤠','🥳','😎','🤓','🧐',
  '😕','😟','🙁','☹️','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣','😞',
  '😓','😩','😫','🥱','😤','😡','😠','🤬','😈','👿','💀','☠️','💩','🤡','👹','👺','👻','👽','👾','🤖',
  '😺','😸','😹','😻','😼','😽','🙀','😿','😾',
  '👍','👎','👊','✊','🤛','🤜','🤞','✌️','🤟','🤘','👌','🤌','🤏','👈','👉','👆','👇','☝️','👋','🤚',
  '🖐️','✋','🖖','💪','🦾','🙏','🤝','👏','🙌','🤲','🫶','❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎',
  '💔','❣️','💕','💞','💓','💗','💖','💘','💝','💟','☮️','✝️','☪️','🕉️','✡️','🔯','🕎','☯️','☦️','🛐',
  '🎉','🎊','🎈','🎁','🎀','🎗️','🏆','🥇','🥈','🥉','🎖️','🏅','🎯','🎮','🎲','🎭','🎬','🎤','🎧','🎸',
  '🔥','💫','⭐','🌟','✨','💥','🌈','☀️','🌙','⚡','❄️','🌊','💧','🌸','🌺','🌹','🍀','🌿','🍃',
  '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🙈','🙉','🙊',
  '🍕','🍔','🌮','🍣','🍜','🍦','🎂','🍰','🧁','🍩','🍪','🍫','🍬','🍭','🥂','🍺','☕','🧃',
  '🚀','✈️','🚗','🚕','🏠','🏖️','🏝️','⛰️','🌏','🗺️','🧳','📸','📱','💻','⌚','🎒','👓','👑',
];

// ─── Offline banners ──────────────────────────────────────────────────────────

class _InboxOfflineBanner extends StatelessWidget {
  const _InboxOfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: const Color(0xff2a2a2a),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 13, color: Color(0xff8e8e8e)),
          const SizedBox(width: 6),
          const Text(
            'No internet connection',
            style: TextStyle(color: Color(0xff8e8e8e), fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ConvOfflineBanner extends StatelessWidget {
  const _ConvOfflineBanner({required this.isLight});
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final subClr = isLight ? _kSubLgt : _kSubDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: isLight ? const Color(0xfff0f0f0) : const Color(0xff1a1a1a),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 13, color: subClr),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'No internet connection',
              style: TextStyle(color: subClr, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullEmojiPicker extends StatelessWidget {
  const _FullEmojiPicker({required this.onSelect, this.scrollController});
  final ValueChanged<String> onSelect;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Emojis', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          Flexible(
            child: GridView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              itemCount: _kAllEmojis.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => onSelect(_kAllEmojis[i]),
                child: Center(child: Text(_kAllEmojis[i], style: const TextStyle(fontSize: 24))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
