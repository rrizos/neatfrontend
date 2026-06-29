import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

class _ReportReason {
  final String key;
  final String label;
  final List<String> subReasons;

  const _ReportReason({
    required this.key,
    required this.label,
    this.subReasons = const [],
  });
}

const _kReasons = [
  _ReportReason(key: 'spam', label: "It's spam"),
  _ReportReason(
    key: 'nudity',
    label: 'Nudity or sexual activity',
    subReasons: [
      'Sexual acts',
      'Genitals',
      'Buttocks or underwear',
      'Sexual services',
      'Suggestive account',
    ],
  ),
  _ReportReason(
    key: 'hate_speech',
    label: 'Hate speech or symbols',
    subReasons: [
      'Race or ethnicity',
      'National origin',
      'Religion',
      'Gender',
      'Sexual orientation',
      'Disability or disease',
      'Caste',
    ],
  ),
  _ReportReason(
    key: 'violence',
    label: 'Violence or dangerous organizations',
    subReasons: [
      'Violence',
      'Weapons',
      'Dangerous individuals or organizations',
      'Child exploitation',
      'Animal abuse',
    ],
  ),
  _ReportReason(
    key: 'illegal_goods',
    label: 'Sale of illegal or regulated goods',
    subReasons: [
      'Drugs',
      'Weapons',
      'Endangered wildlife products',
      'Counterfeit goods',
      'Sexual services',
    ],
  ),
  _ReportReason(
    key: 'bullying',
    label: 'Bullying or harassment',
    subReasons: [
      'Me',
      'Someone I know',
      'A celebrity or public figure',
    ],
  ),
  _ReportReason(
    key: 'intellectual_property',
    label: 'Intellectual property violation',
    subReasons: [
      'Copyright',
      'Trademark',
    ],
  ),
  _ReportReason(
    key: 'self_injury',
    label: 'Suicide or self-injury',
    subReasons: [
      'Suicide or self-harm',
      'Dangerous activities',
    ],
  ),
  _ReportReason(key: 'eating_disorders', label: 'Eating disorders'),
  _ReportReason(
    key: 'scam',
    label: 'Scam or fraud',
    subReasons: [
      'Phishing or hacked account',
      'Romance scam',
      'Financial scam',
      'Purchased followers or likes',
    ],
  ),
  _ReportReason(
    key: 'false_information',
    label: 'False information',
    subReasons: [
      'Health',
      'Politics',
      'Social issue',
      'Something else',
    ],
  ),
  _ReportReason(key: 'dislike', label: "I just don't like it"),
];

enum _Step { reason, subReason, submitting, done }

Future<void> showReportPostSheet(
  BuildContext context, {
  required int postId,
  required String token,
}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isLight ? Colors.white : const Color(0xff141414),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ReportPostSheet(postId: postId, token: token),
  );
}

class _ReportPostSheet extends StatefulWidget {
  final int postId;
  final String token;

  const _ReportPostSheet({required this.postId, required this.token});

  @override
  State<_ReportPostSheet> createState() => _ReportPostSheetState();
}

class _ReportPostSheetState extends State<_ReportPostSheet> {
  _Step _step = _Step.reason;
  _ReportReason? _reason;

  Future<void> _submit(String subReason) async {
    setState(() => _step = _Step.submitting);
    try {
      await http.post(
        postReportEndpoint(widget.postId),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({
          'reason': _reason!.key,
          'sub_reason': subReason,
        }),
      );
    } catch (_) {}
    if (mounted) setState(() => _step = _Step.done);
  }

  void _onReasonTap(_ReportReason reason) {
    if (reason.subReasons.isEmpty) {
      _reason = reason;
      _submit('');
    } else {
      setState(() {
        _reason = reason;
        _step = _Step.subReason;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? Colors.black : Colors.white;
    final subtitleColor = isLight ? const Color(0xff737373) : const Color(0xffa8a8a8);
    final dividerColor = isLight ? const Color(0xffe0e0e0) : const Color(0xff262626);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.25, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: switch (_step) {
        _Step.reason => _ReasonPage(
            key: const ValueKey('reason'),
            textColor: textColor,
            subtitleColor: subtitleColor,
            dividerColor: dividerColor,
            onTap: _onReasonTap,
          ),
        _Step.subReason => _SubReasonPage(
            key: const ValueKey('subReason'),
            reason: _reason!,
            textColor: textColor,
            subtitleColor: subtitleColor,
            dividerColor: dividerColor,
            onBack: () => setState(() { _step = _Step.reason; _reason = null; }),
            onTap: _submit,
          ),
        _Step.submitting => _SubmittingPage(key: const ValueKey('submitting')),
        _Step.done => _DonePage(
            key: const ValueKey('done'),
            textColor: textColor,
            subtitleColor: subtitleColor,
            onDone: () => Navigator.of(context).pop(),
          ),
      },
    );
  }
}

class _ReasonPage extends StatelessWidget {
  final Color textColor;
  final Color subtitleColor;
  final Color dividerColor;
  final void Function(_ReportReason) onTap;

  const _ReasonPage({
    super.key,
    required this.textColor,
    required this.subtitleColor,
    required this.dividerColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Why are you reporting this post?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your report is anonymous, except if you\'re reporting an intellectual property infringement.',
                  style: TextStyle(fontSize: 12, color: subtitleColor, height: 1.4),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.58,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _kReasons.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: dividerColor),
              itemBuilder: (_, i) {
                final r = _kReasons[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    r.label,
                    style: TextStyle(fontSize: 15, color: textColor),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: subtitleColor, size: 22),
                  onTap: () => onTap(r),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SubReasonPage extends StatelessWidget {
  final _ReportReason reason;
  final Color textColor;
  final Color subtitleColor;
  final Color dividerColor;
  final VoidCallback onBack;
  final void Function(String) onTap;

  const _SubReasonPage({
    super.key,
    required this.reason,
    required this.textColor,
    required this.subtitleColor,
    required this.dividerColor,
    required this.onBack,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: textColor),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  reason.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
          Divider(height: 1, color: dividerColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Select a more specific issue',
              style: TextStyle(fontSize: 13, color: subtitleColor),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.52,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: reason.subReasons.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: dividerColor),
              itemBuilder: (_, i) {
                final sub = reason.subReasons[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(sub, style: TextStyle(fontSize: 15, color: textColor)),
                  trailing: Icon(Icons.chevron_right_rounded, color: subtitleColor, size: 22),
                  onTap: () => onTap(sub),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SubmittingPage extends StatelessWidget {
  const _SubmittingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 180,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _DonePage extends StatelessWidget {
  final Color textColor;
  final Color subtitleColor;
  final VoidCallback onDone;

  const _DonePage({
    super.key,
    required this.textColor,
    required this.subtitleColor,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xff0095f6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              'Thanks for letting us know',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'We use these reports to show fewer of these things in the future. If someone is in immediate danger, call local emergency services.',
              style: TextStyle(fontSize: 13, color: subtitleColor, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff0095f6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: onDone,
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
