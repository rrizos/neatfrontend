import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'http_client.dart' as http;

import '../../l10n/app_localizations.dart';
import 'api.dart';
import 'avatar_store.dart';
import 'link_preview.dart';
import 'models.dart';
import 'post_card.dart' show decodeAvatarUrl;

final RegExp mentionRegex = RegExp(r'@([\w.]+)');

/// One tappable run found in the text — either a mention or a URL.
class _Hit {
  const _Hit(this.start, this.end, this.text, this.isLink);
  final int start;
  final int end;
  final String text;
  final bool isLink;
}

/// Splits [text] into spans, rendering "@username" runs and URLs as tappable,
/// distinctly-styled links. Used everywhere free text is displayed: post
/// captions, post comments, event comments and DM bubbles.
///
/// Mentions go to [onTapMention]. Links open in the in-app browser unless
/// [onTapLink] overrides that. Pass [linkStyle] to colour links differently
/// from mentions — by default they share [mentionStyle].
List<InlineSpan> buildMentionSpans(
  String text, {
  required TextStyle style,
  required TextStyle mentionStyle,
  required ValueChanged<String> onTapMention,
  TextStyle? linkStyle,
  ValueChanged<String>? onTapLink,
}) {
  final effectiveLinkStyle = linkStyle ?? mentionStyle;
  final hits = <_Hit>[];

  for (final m in linkMatches(text)) {
    hits.add(_Hit(m.start, m.end, m.url, true));
  }

  for (final m in mentionRegex.allMatches(text)) {
    // A "@handle" inside a URL path belongs to the URL, not to a user.
    final overlapsLink =
        hits.any((h) => h.isLink && m.start < h.end && m.end > h.start);
    if (overlapsLink) continue;
    hits.add(_Hit(m.start, m.end, m.group(0)!, false));
  }

  hits.sort((a, b) => a.start.compareTo(b.start));

  final spans = <InlineSpan>[];
  var last = 0;
  for (final hit in hits) {
    if (hit.start < last) continue; // defensive: overlapping runs
    if (hit.start > last) {
      spans.add(TextSpan(text: text.substring(last, hit.start), style: style));
    }
    if (hit.isLink) {
      spans.add(TextSpan(
        text: hit.text,
        style: effectiveLinkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () =>
              onTapLink != null ? onTapLink(hit.text) : openLink(hit.text),
      ));
    } else {
      final username = hit.text.substring(1);
      spans.add(TextSpan(
        text: hit.text,
        style: mentionStyle,
        recognizer: TapGestureRecognizer()..onTap = () => onTapMention(username),
      ));
    }
    last = hit.end;
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
      final res = await http.get(searchUsersEndpoint(query, true), headers: authGetHeaders(widget.token));
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
    final bg = isLight ? Colors.white : const Color(0xff141414);
    final dividerColor = isLight ? const Color(0xfff0f0f0) : const Color(0xff2a2a2a);
    final topBorderColor = isLight ? const Color(0xffe0e0e0) : const Color(0xff303030);
    final textColor = isLight ? const Color(0xff0a0a0a) : Colors.white;
    final subColor = isLight ? const Color(0xff8b95a3) : const Color(0xff888888);
    final avatarBg = isLight ? const Color(0xffedeff2) : const Color(0xff2c2c2c);
    final highlightColor = isLight ? const Color(0xfff7f8fa) : const Color(0xff252525);

    Widget body;
    if (_loading) {
      body = SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: isLight ? const Color(0xff3897f0) : const Color(0xff3897f0)),
          ),
        ),
      );
    } else if (_results.isEmpty) {
      body = SizedBox(
        height: 48,
        child: Center(
          child: Text(
            AppLocalizations.of(context).noMatchesInTown,
            style: TextStyle(fontSize: 13, color: subColor),
          ),
        ),
      );
    } else {
      body = ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _results.length,
        separatorBuilder: (_, i) => Divider(height: 1, thickness: 1, color: dividerColor, indent: 56, endIndent: 0),
        itemBuilder: (_, i) {
          final u = _results[i];
          final bytes = decodeAvatarUrl(AvatarStore.resolve(u.username, u.avatarUrl));
          return InkWell(
            onTap: () => _select(u),
            highlightColor: highlightColor,
            splashColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: avatarBg,
                    foregroundImage: bytes != null ? MemoryImage(bytes) : null,
                    child: bytes == null
                        ? Text(
                            initialFor(u.username),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
                          )
                        : null,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '@${u.username}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor, height: 1.2),
                        ),
                        if (u.fullName.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            u.fullName,
                            style: TextStyle(fontSize: 12.5, color: subColor, height: 1.2),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: topBorderColor, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.06 : 0.25),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: body,
    );
  }
}
