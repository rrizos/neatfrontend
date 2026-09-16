import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'http_client.dart' as http;
import 'locked_cities.dart'
    show cityAccusative, cityGenitive, cityLocative, citySlug;

/// Above this many people still missing, the sheet stops naming the number.
///
/// "Μένουν 234" reads as a wall rather than an invitation: it tells someone
/// their three friends cannot matter, which is the opposite of what this
/// screen is for. Under it, the number *is* the argument — so it leads.
///
/// invites/views.py holds the same constant for the web page, and the two are
/// meant to say the same thing to the same person.
const int kRevealRemainingAt = 25;

/// The link an invitation travels on: `https://neatapp.gr/<username>/invite`.
///
/// The city rides along as a slug rather than being looked up from the
/// inviter's profile, because the page that reads this link is rendered for
/// logged-out strangers and the profile endpoint needs a token. It is also
/// the more truthful answer: the card this is sent from is about the city on
/// screen, which is not always the city the sender lives in.
///
/// [username] is empty during sign-up, where there is no account to credit
/// yet. The link still works — the page just says that someone invited you
/// rather than who, and nothing is attributed.
String inviteLink({required String city, String? username}) {
  final who = (username == null || username.isEmpty) ? '' : '/$username';
  final slug = citySlug(city);
  final query = slug.isEmpty ? '' : '?city=$slug';
  return '$webBaseUrl$who/invite$query';
}

/// The invite sheet for a locked city: why it is worth sending, and the link.
///
/// [memberCount] and [threshold] are what the caller already knows about the
/// city. Pass 0 for either when it is not known and the copy drops to a
/// version that promises no numbers.
///
/// [forceDark] is for the map, whose city cards are dark whatever the app's
/// theme is — a white sheet rising out of one would be the only light thing
/// on the screen.
Future<void> showInviteSheet(
  BuildContext context, {
  required String city,
  String? username,
  String token = '',
  int memberCount = 0,
  int threshold = 0,
  bool forceDark = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => _InviteSheet(
      city: city,
      username: username,
      token: token,
      memberCount: memberCount,
      threshold: threshold,
      isDark: forceDark || Theme.of(ctx).brightness == Brightness.dark,
    ),
  );
}

/// Tells the server the link went out. Fire-and-forget on purpose: a counter
/// on an internal dashboard is never worth making someone wait, or showing
/// them an error about.
Future<void> reportInviteSent({required String token, required String city}) async {
  if (token.isEmpty) return;
  try {
    await http.post(
      inviteSentEndpoint,
      headers: authJsonHeaders(token),
      body: '{"city": ${jsonQuote(city)}}',
    );
  } catch (_) {
    // Nothing to do and nothing to say.
  }
}

/// Minimal JSON string escaping, so this file does not pull in dart:convert
/// for one field.
String jsonQuote(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
  return '"$escaped"';
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({
    required this.city,
    required this.username,
    required this.token,
    required this.memberCount,
    required this.threshold,
    required this.isDark,
  });

  final String city;
  final String? username;
  final String token;
  final int memberCount;
  final int threshold;
  final bool isDark;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    unawaited(reportInviteSent(token: widget.token, city: widget.city));
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final link = inviteLink(city: widget.city, username: widget.username);
    final remaining = widget.threshold - widget.memberCount;
    // The numbers appear only when they argue for sending. See
    // [kRevealRemainingAt].
    final countable = widget.threshold > 0 &&
        remaining > 0 &&
        remaining <= kRevealRemainingAt;
    final progress = widget.threshold > 0
        ? (widget.memberCount / widget.threshold).clamp(0.0, 1.0)
        : 0.0;

    const blue = Color(0xff2F80ED);
    final bg = dark ? const Color(0xff000000) : Colors.white;
    final ink = dark ? Colors.white : const Color(0xff111111);
    final muted = dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
    final surface = dark ? const Color(0xff141414) : const Color(0xfff3f4f6);
    final hairline = dark ? const Color(0xff222222) : const Color(0xffe5e7eb);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle, same size and colour as every other sheet here.
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 22),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xff3f3f46) : const Color(0xffcbd5e1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Headline ──────────────────────────────────────────────
                  Text(
                    'Φέρε την παρέα σου ${cityLocative(widget.city)}',
                    style: TextStyle(
                      color: ink,
                      fontSize: 26,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    countable
                        ? 'Μένουν $remaining άτομα για να ανοίξει το feed '
                            '${cityGenitive(widget.city)}. Κάθε άτομο που μπαίνει '
                            'από το link σου μετράει.'
                        : 'Το feed ${cityGenitive(widget.city)} ανοίγει μόλις '
                            'μαζευτεί η παρέα — και κάθε άτομο που μπαίνει από το '
                            'link σου το φέρνει πιο κοντά.',
                    style: TextStyle(color: muted, fontSize: 15, height: 1.5),
                  ),

                  // ── The counter, when it is an argument ───────────────────
                  if (countable) ...[
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: hairline,
                        valueColor: const AlwaysStoppedAnimation<Color>(blue),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.memberCount} από ${widget.threshold} άτομα',
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text(
                    'Στείλ’ το σε λίγους φίλους από ${cityAccusative(widget.city)} '
                    'και μόλις ανοίξει, θα είστε ήδη όλοι μέσα.',
                    style: TextStyle(color: muted, fontSize: 15, height: 1.5),
                  ),

                  // ── The wait is not empty ─────────────────────────────────
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Emoji, not a Material icon: a codepoint the base
                        // release never used is missing from the tree-shaken
                        // icon font, and a Shorebird patch does not carry a
                        // new one — it would ship as an empty box.
                        const Text('🇬🇷', style: TextStyle(fontSize: 17)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Μέχρι τότε δεν περιμένεις: το feed της Ελλάδας '
                            'είναι ήδη ανοιχτό για σένα.',
                            style: TextStyle(
                              color: muted,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── The link ──────────────────────────────────────────────
                  const SizedBox(height: 22),
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: surface,
                      border: Border.all(color: hairline),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      // Without the scheme: the recognisable part is what has
                      // to fit on one line, not https://.
                      link.replaceFirst('https://', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () => _copy(link),
                      style: FilledButton.styleFrom(
                        backgroundColor: _copied ? surface : blue,
                        foregroundColor: _copied ? ink : Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _copied ? '✓  Αντιγράφηκε' : 'Αντιγραφή link',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Επικόλλησέ το σε WhatsApp, Instagram ή όπου κάνετε παρέα.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
