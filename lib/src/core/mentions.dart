import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'models.dart';
import 'post_card.dart' show decodeAvatarUrl;

final RegExp mentionRegex = RegExp(r'@([\w.]+)');

/// Splits [text] into spans, rendering "@username" runs as tappable,
/// distinctly-styled links via [onTapMention]. Used everywhere mentionable
/// text is displayed: post captions, post comments, event comments.
List<InlineSpan> buildMentionSpans(
  String text, {
  required TextStyle style,
  required TextStyle mentionStyle,
  required ValueChanged<String> onTapMention,
}) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in mentionRegex.allMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(text: text.substring(last, match.start), style: style));
    }
    final username = match.group(1)!;
    spans.add(TextSpan(
      text: match.group(0),
      style: mentionStyle,
      recognizer: TapGestureRecognizer()..onTap = () => onTapMention(username),
    ));
    last = match.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: style));
  }
  return spans;
}

/// Instagram-style "@" autocomplete: watches [controller] for an active
/// "@token" run at the caret, and — while one is active — shows a scrollable
/// list of matching users (people the viewer already follows/is followed by
/// surface first, then the rest) scoped to the viewer's own city, since
/// mentions are a hyperlocal-only feature here.
class MentionSuggestions extends StatefulWidget {
  const MentionSuggestions({
    super.key,
    required this.controller,
    required this.token,
  });

  final TextEditingController controller;
  final String token;

  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  Timer? _debounce;
  String? _activeQuery;
  List<UserProfile> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _debounce?.cancel();
    super.dispose();
  }

  String? _currentMentionToken() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.start != selection.end) return null;
    final cursor = selection.start;
    if (cursor <= 0 || cursor > text.length) return null;
    final upToCursor = text.substring(0, cursor);
    final atIndex = upToCursor.lastIndexOf('@');
    if (atIndex == -1) return null;
    // Must be start-of-text or preceded by whitespace to count as a mention trigger.
    if (atIndex > 0 && upToCursor[atIndex - 1].trim().isNotEmpty) return null;
    final token = upToCursor.substring(atIndex + 1);
    if (token.contains(' ') || token.contains('\n')) return null;
    return token;
  }

  void _onTextChanged() {
    final token = _currentMentionToken();
    if (token == _activeQuery) return;
    setState(() => _activeQuery = token);
    if (token == null) {
      setState(() => _results = []);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(token));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final res = await http.get(searchUsersEndpoint(query), headers: authGetHeaders(widget.token));
      if (!mounted || _activeQuery != query) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final raw = body is Map<String, dynamic> ? (body['users'] as List? ?? const []) : const [];
        setState(() {
          _results = raw.whereType<Map<String, dynamic>>().map(UserProfile.fromJson).toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(UserProfile user) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.start;
    final upToCursor = text.substring(0, cursor);
    final atIndex = upToCursor.lastIndexOf('@');
    if (atIndex == -1) return;
    final before = text.substring(0, atIndex);
    final after = text.substring(cursor);
    final insertion = '@${user.username} ';
    widget.controller.value = TextEditingValue(
      text: '$before$insertion$after',
      selection: TextSelection.collapsed(offset: (before + insertion).length),
    );
    setState(() {
      _activeQuery = null;
      _results = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_activeQuery == null) return const SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : const Color(0xff1a1a1a);
    final borderColor = isLight ? const Color(0xffe0e0e0) : const Color(0xff2a2a2a);
    final textColor = isLight ? Colors.black : Colors.white;
    final subColor = isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a);

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else if (_results.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(child: Text('No matches in your town', style: TextStyle(fontSize: 12, color: subColor))),
      );
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _results.length,
        itemBuilder: (_, i) {
          final u = _results[i];
          final bytes = decodeAvatarUrl(u.avatarUrl);
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              foregroundImage: bytes != null ? MemoryImage(bytes) : null,
              child: bytes == null
                  ? Text(
                      initialFor(u.username),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textColor),
                    )
                  : null,
            ),
            title: Text('@${u.username}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textColor)),
            subtitle: u.fullName.isNotEmpty
                ? Text(u.fullName, style: TextStyle(fontSize: 12, color: subColor))
                : null,
            onTap: () => _select(u),
          );
        },
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: body,
    );
  }
}
