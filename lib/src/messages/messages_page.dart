import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import '../core/models.dart';

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
  return NetworkImage(url);
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
  final _search = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final res = await http.get(inboxEndpoint, headers: authGetHeaders(widget.token));
      if (res.statusCode == 401) return widget.onLogout();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (body['conversations'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ConversationSummary.fromJson)
          .toList();
      if (mounted) setState(() { _convs = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
    final filtered = q.isEmpty
        ? _convs
        : _convs.where((c) =>
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
            if (widget.suggestedUsers.isNotEmpty && q.isEmpty) ...[
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: widget.suggestedUsers.length,
                    separatorBuilder: (_, i) => const SizedBox(width: 18),
                    itemBuilder: (_, i) {
                      final u = widget.suggestedUsers[i];
                      return _QuickChip(
                        user: u,
                        isLight: isLight,
                        onTap: () => _startChatWith(u.username),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(height: 1, color: isLight ? _kDivLgt : _kDivDark),
              ),
            ],
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: _kBlue)),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: _EmptyInbox(isLight: isLight, hasSearch: q.isNotEmpty),
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
    return me ? 'You: $msg' : msg;
  }

  @override
  Widget build(BuildContext context) {
    final unread = summary.unreadCount > 0;
    final name   = summary.otherFullName.isNotEmpty ? summary.otherFullName : summary.otherUser;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _avatar(
              username: summary.otherUser,
              url: summary.otherAvatarUrl,
              radius: 28,
              isLight: isLight,
              ring: unread,
            ),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 2),
                  Text(
                    _preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unread
                          ? (isLight ? Colors.black87 : Colors.white)
                          : (isLight ? _kSubLgt : _kSubDark),
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _inboxTime(summary.updated),
                  style: TextStyle(color: isLight ? _kSubLgt : _kSubDark, fontSize: 12),
                ),
                if (unread) ...[
                  const SizedBox(height: 5),
                  Container(
                    width: 9, height: 9,
                    decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick-start chip ─────────────────────────────────────────────────────────

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
  const _EmptyInbox({required this.isLight, required this.hasSearch});
  final bool isLight;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 60,
              color: isLight ? const Color(0xffbdbdbd) : const Color(0xff444444),
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch ? 'No results' : 'Your messages',
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'No conversations match your search.'
                  : 'Send a private message to someone in your city.',
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
    this.onOpenPost,
    this.onOpenUserProfile,
  });

  final String token;
  final String currentUsername;
  final int conversationId;
  final String otherUsername;
  final String otherFullName;
  final String otherAvatarUrl;
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

  @override
  void initState() {
    super.initState();
    _composer.addListener(() => setState(() {}));
    _load(initial: true);
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
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
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final msgs = (body['messages'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MessageItem.fromJson)
          .toList();
      if (!mounted) return;
      setState(() { _messages = msgs; _loading = false; });
      _scrollToBottom(jump: initial);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
    setState(() { _messages = [..._messages, opt]; _sending = true; });
    _scrollToBottom();

    try {
      final res = await http.post(
        messageConversationEndpoint(widget.conversationId),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'text': text}),
      );
      if (res.statusCode == 401) return widget.onLogout();
      if (res.statusCode == 201) await _load();
    } catch (_) {
      if (mounted) setState(() => _messages.removeWhere((m) => m.id == opt.id));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText() => _sendRaw(_composer.text.trim(), clearInput: true);

  Future<void> _sendImage(Uint8List bytes) =>
      _sendRaw('$_kImagePrefix${base64Encode(bytes)}');

  Future<void> _sendVoice(Uint8List bytes, int durationSecs) =>
      _sendRaw('$_kVoicePrefix${base64Encode(bytes)}|$durationSecs');

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
                    Text(
                      '@${widget.otherUsername}',
                      style: TextStyle(fontSize: 11.5, color: isLight ? _kSubLgt : _kSubDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final msg    = _messages[i];
                          final mine   = msg.sender == widget.currentUsername;
                          final isLast = _isLastInGroup(_messages, i);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_showDivider(_messages, i))
                                _TimeDivider(time: msg.created, isLight: isLight),
                              _MessageRow(
                                message: msg,
                                mine: mine,
                                isLast: isLast,
                                otherUsername: widget.otherUsername,
                                otherAvatarUrl: widget.otherAvatarUrl,
                                isLight: isLight,
                                onOpenPost: widget.onOpenPost,
                                onOpenUserProfile: widget.onOpenUserProfile != null
                                    ? () => widget.onOpenUserProfile!(widget.otherUsername)
                                    : null,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          _Composer(
            controller: _composer,
            isLight: isLight,
            sending: _sending,
            onSendText: _sendText,
            onSendImage: _sendImage,
            onSendVoice: _sendVoice,
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
  });

  final MessageItem message;
  final bool mine;
  final bool isLast;
  final String otherUsername;
  final String otherAvatarUrl;
  final bool isLight;
  final void Function(String, int)? onOpenPost;
  final VoidCallback? onOpenUserProfile;

  Widget _content() {
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

  @override
  Widget build(BuildContext context) {
    final maxW     = MediaQuery.sizeOf(context).width * 0.70;
    final bottomPad = isLast ? 6.0 : 2.0;

    if (mine) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: _content()),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Row(
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
          ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: _content()),
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
      pageBuilder: (ctx, a1, a2) => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: InteractiveViewer(child: Image.memory(bytes)),
          ),
        ),
      ),
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
  });

  final TextEditingController controller;
  final bool isLight;
  final bool sending;
  final VoidCallback onSendText;
  final Future<void> Function(Uint8List) onSendImage;
  final Future<void> Function(Uint8List, int) onSendVoice;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _recorder = Record();
  bool _recording  = false;
  int  _recSecs    = 0;
  Timer? _timer;
  String? _recPath;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    Navigator.of(context).pop(); // close bottom sheet first
    final xfile = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1200,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    await widget.onSendImage(bytes);
  }

  void _showImageOptions() {
    final isLight = widget.isLight;
    final textClr = isLight ? Colors.black : Colors.white;
    showModalBottomSheet(
      context: context,
      backgroundColor: isLight ? Colors.white : const Color(0xff1c1c1e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isLight ? const Color(0xffd0d0d0) : const Color(0xff444444),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: textClr),
              title: Text('Camera', style: TextStyle(color: textClr, fontWeight: FontWeight.w500)),
              onTap: () => _pickImage(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: textClr),
              title: Text('Gallery', style: TextStyle(color: textClr, fontWeight: FontWeight.w500)),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Voice recording ───────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_recording) return;
    final ok = await _recorder.hasPermission();
    if (!ok || !mounted) return;
    final dir = await getTemporaryDirectory();
    _recPath = '${dir.path}/neat_voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _recorder.start(path: _recPath!, encoder: AudioEncoder.aacLc);
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _recording ? _buildRecordingBar() : _buildNormalBar(),
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
    final hasText  = widget.controller.text.trim().isNotEmpty;
    final iconClr  = widget.isLight ? Colors.black : Colors.white;
    final fillClr  = widget.isLight ? _kInputLgt : _kInputDark;

    return Container(
      key: const ValueKey('normal'),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Gallery / camera
          IconButton(
            icon: Icon(Icons.image_rounded, color: iconClr, size: 26),
            padding: EdgeInsets.zero,
            onPressed: _showImageOptions,
          ),
          const SizedBox(width: 4),
          // Text input
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: fillClr,
                borderRadius: BorderRadius.circular(22),
                border: widget.isLight ? Border.all(color: const Color(0xffd8d8d8)) : null,
              ),
              child: TextField(
                controller: widget.controller,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: widget.isLight ? Colors.black : Colors.white, fontSize: 15),
                cursorColor: _kBlue,
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(color: widget.isLight ? _kSubLgt : _kSubDark, fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button (has text) or mic (no text)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: hasText
                ? GestureDetector(
                    key: const ValueKey('send'),
                    onTap: widget.sending ? null : widget.onSendText,
                    child: Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
                      child: widget.sending
                          ? const Center(
                              child: SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                    ),
                  )
                : GestureDetector(
                    key: const ValueKey('mic'),
                    onTap: _startRecording,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(Icons.mic_rounded, color: iconClr, size: 26),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
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
                    : Image.network(imageUrl, fit: BoxFit.cover),
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
