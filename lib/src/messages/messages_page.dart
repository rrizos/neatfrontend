import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import '../core/models.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.token,
    required this.currentUsername,
    required this.onLogout,
  });

  final String token;
  final String currentUsername;
  final Future<void> Function() onLogout;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  List<ConversationSummary> _conversations = [];
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        inboxEndpoint,
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode == 401) return widget.onLogout();
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (decoded['conversations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ConversationSummary.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _conversations = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openConversation(ConversationSummary summary) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationPage(
          token: widget.token,
          currentUsername: widget.currentUsername,
          conversationId: summary.id,
          otherUsername: summary.otherUser,
          otherFullName: summary.otherFullName,
          onLogout: widget.onLogout,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _startChat() async {
    final controller = TextEditingController();
    final username = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xff121212),
      showDragHandle: true,
      builder: (context) {
        return _StartChatSheet(controller: controller);
      },
    );
    if (username == null || username.isEmpty) return;
    final res = await http.post(
      startConversationEndpoint,
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'username': username}),
    );
    if (res.statusCode == 401) return widget.onLogout();
    if (res.statusCode != 200 && res.statusCode != 201) {
      final message =
          _errorFromResponse(res.body) ?? 'Could not start chat (${res.statusCode})';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final conversation = ConversationSummary.fromJson(
      decoded['conversation'] as Map<String, dynamic>,
    );
    if (!mounted) return;
    await _openConversation(conversation);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.text.trim().isEmpty
        ? _conversations
        : _conversations
            .where(
              (item) =>
                  item.otherUser.toLowerCase().contains(_search.text.toLowerCase()) ||
                  item.otherFullName.toLowerCase().contains(_search.text.toLowerCase()),
            )
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xff121212),
      appBar: AppBar(
        backgroundColor: const Color(0xff121212),
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _startChat,
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: Color(0xff9c9c9c)),
                hintText: 'Search',
                hintStyle: const TextStyle(color: Color(0xff9c9c9c)),
                filled: true,
                fillColor: const Color(0xff1b1b1b),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: Text(
                    'No messages yet.',
                    style: TextStyle(color: Color(0xff9c9c9c)),
                  ),
                ),
              )
            else
              ...filtered.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openConversation(item),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xff171717),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xff232323)),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xff2a2a2a),
                            child: Text(initialFor(item.otherUser)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.otherFullName.isNotEmpty
                                            ? item.otherFullName
                                            : item.otherUser,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _timeLabel(item.updated),
                                      style: const TextStyle(
                                        color: Color(0xff8e8e8e),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.lastMessage.isEmpty
                                      ? 'Tap to start chatting'
                                      : '${item.lastSender.isEmpty ? '' : '${item.lastSender}: '} ${item.lastMessage}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: item.unreadCount > 0
                                        ? Colors.white
                                        : const Color(0xff9c9c9c),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (item.unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xfff66c6c),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StartChatSheet extends StatefulWidget {
  const _StartChatSheet({required this.controller});
  final TextEditingController controller;

  @override
  State<_StartChatSheet> createState() => _StartChatSheetState();
}

class _StartChatSheetState extends State<_StartChatSheet> {
  String? _error;

  void _submit() {
    final username = widget.controller.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Enter a username');
      return;
    }
    Navigator.of(context).pop(username);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'New message',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Username',
                hintStyle: const TextStyle(color: Color(0xff9c9c9c)),
                filled: true,
                fillColor: const Color(0xff1b1b1b),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xfff66c6c)),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Start chat'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _errorFromResponse(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded['error']?.toString();
    }
  } catch (_) {}
  return null;
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.token,
    required this.currentUsername,
    required this.conversationId,
    required this.otherUsername,
    required this.otherFullName,
    required this.onLogout,
  });

  final String token;
  final String currentUsername;
  final int conversationId;
  final String otherUsername;
  final String otherFullName;
  final Future<void> Function() onLogout;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _composer = TextEditingController();
  List<MessageItem> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        messageConversationEndpoint(widget.conversationId),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode == 401) return widget.onLogout();
      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final messages = (decoded['messages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MessageItem.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final res = await http.post(
      messageConversationEndpoint(widget.conversationId),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'text': text}),
    );
    if (res.statusCode == 401) return widget.onLogout();
    if (res.statusCode != 201) return;
    _composer.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff121212),
      appBar: AppBar(
        backgroundColor: const Color(0xff121212),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xff2a2a2a),
              child: Text(initialFor(widget.otherUsername)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherFullName.isNotEmpty
                      ? widget.otherFullName
                      : widget.otherUsername,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '@${widget.otherUsername}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xff9c9c9c),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final mine = message.sender == widget.currentUsername;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.76,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xff2b2b2b)
                                : const Color(0xff1a1a1a),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xff2a2a2a),
                            ),
                          ),
                          child: Text(
                            message.text,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        hintStyle: const TextStyle(color: Color(0xff9c9c9c)),
                        filled: true,
                        fillColor: const Color(0xff1b1b1b),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white,
                    child: IconButton(
                      onPressed: _send,
                      icon: const Icon(
                        Icons.send,
                        color: Colors.black,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _timeLabel(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
