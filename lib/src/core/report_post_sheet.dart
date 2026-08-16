import 'dart:convert';

import 'package:flutter/material.dart';
import 'http_client.dart' as http;

import '../../l10n/app_localizations.dart';
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

List<_ReportReason> _buildReasons(AppLocalizations l10n) => [
  _ReportReason(key: 'spam', label: l10n.reportSpam),
  _ReportReason(
    key: 'nudity',
    label: l10n.reportNudity,
    subReasons: [
      l10n.reportSubSexualActs,
      l10n.reportSubGenitals,
      l10n.reportSubButtocks,
      l10n.reportSubSexualServices,
      l10n.reportSubSuggestiveAccount,
    ],
  ),
  _ReportReason(
    key: 'hate_speech',
    label: l10n.reportHateSpeech,
    subReasons: [
      l10n.reportSubRace,
      l10n.reportSubNationalOrigin,
      l10n.reportSubReligion,
      l10n.reportSubGender,
      l10n.reportSubSexualOrientation,
      l10n.reportSubDisability,
      l10n.reportSubCaste,
    ],
  ),
  _ReportReason(
    key: 'violence',
    label: l10n.reportViolence,
    subReasons: [
      l10n.reportSubViolence,
      l10n.reportSubWeapons,
      l10n.reportSubDangerousOrgs,
      l10n.reportSubChildExploitation,
      l10n.reportSubAnimalAbuse,
    ],
  ),
  _ReportReason(
    key: 'illegal_goods',
    label: l10n.reportIllegalGoods,
    subReasons: [
      l10n.reportSubDrugs,
      l10n.reportSubWeapons,
      l10n.reportSubWildlife,
      l10n.reportSubCounterfeit,
      l10n.reportSubSexualServices,
    ],
  ),
  _ReportReason(
    key: 'bullying',
    label: l10n.reportBullying,
    subReasons: [
      l10n.reportSubMe,
      l10n.reportSubSomeoneIKnow,
      l10n.reportSubPublicFigure,
    ],
  ),
  _ReportReason(
    key: 'intellectual_property',
    label: l10n.reportIntellectualProperty,
    subReasons: [
      l10n.reportSubCopyright,
      l10n.reportSubTrademark,
    ],
  ),
  _ReportReason(
    key: 'self_injury',
    label: l10n.reportSelfInjury,
    subReasons: [
      l10n.reportSubSelfHarm,
      l10n.reportSubDangerousActivities,
    ],
  ),
  _ReportReason(key: 'eating_disorders', label: l10n.reportEatingDisorders),
  _ReportReason(
    key: 'scam',
    label: l10n.reportScam,
    subReasons: [
      l10n.reportSubPhishing,
      l10n.reportSubRomanceScam,
      l10n.reportSubFinancialScam,
      l10n.reportSubPurchasedFollowers,
    ],
  ),
  _ReportReason(
    key: 'false_information',
    label: l10n.reportFalseInformation,
    subReasons: [
      l10n.reportSubHealth,
      l10n.reportSubPolitics,
      l10n.reportSubSocialIssue,
      l10n.reportSubSomethingElse,
    ],
  ),
  _ReportReason(key: 'dislike', label: l10n.reportDislike),
];

enum _Step { reason, subReason, submitting, done }

Future<void> showReportPostSheet(
  BuildContext context, {
  required int postId,
  required String token,
}) {
  return _showReportSheet(
    context,
    submit: (reason, subReason) => http.post(
      postReportEndpoint(postId),
      headers: authJsonHeaders(token),
      body: jsonEncode({'reason': reason, 'sub_reason': subReason}),
    ),
  );
}

Future<void> showReportMessageSheet(
  BuildContext context, {
  required int conversationId,
  required int messageId,
  required String token,
}) {
  return _showReportSheet(
    context,
    submit: (reason, subReason) => http.post(
      messageReportEndpoint(conversationId, messageId),
      headers: authJsonHeaders(token),
      body: jsonEncode({'reason': reason}),
    ),
  );
}

Future<void> showReportCommentSheet(
  BuildContext context, {
  required Uri endpoint,
  required String token,
}) {
  return _showReportSheet(
    context,
    submit: (reason, subReason) => http.post(
      endpoint,
      headers: authJsonHeaders(token),
      body: jsonEncode({'reason': reason}),
    ),
  );
}

Future<void> showReportEventSheet(
  BuildContext context, {
  required int eventId,
  required String token,
}) {
  return _showReportSheet(
    context,
    submit: (reason, subReason) => http.post(
      eventReportEndpoint(eventId),
      headers: authJsonHeaders(token),
      body: jsonEncode({'reason': reason}),
    ),
  );
}

Future<void> _showReportSheet(
  BuildContext context, {
  required Future<void> Function(String reason, String subReason) submit,
}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: isLight ? Colors.white : const Color(0xff000000),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ReportSheet(submit: submit),
  );
}

class _ReportSheet extends StatefulWidget {
  final Future<void> Function(String reason, String subReason) submit;

  const _ReportSheet({required this.submit});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  _Step _step = _Step.reason;
  _ReportReason? _reason;

  Future<void> _submit(String subReason) async {
    setState(() => _step = _Step.submitting);
    try {
      await widget.submit(_reason!.key, subReason);
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
    final l10n = AppLocalizations.of(context);
    final reasons = _buildReasons(l10n);
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
                  l10n.reportTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.reportWhyPost,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.reportAnonymousNote,
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
              itemCount: reasons.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: dividerColor),
              itemBuilder: (_, i) {
                final r = reasons[i];
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
              AppLocalizations.of(context).reportSelectSpecific,
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
    final l10n = AppLocalizations.of(context);
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
              l10n.reportThanks,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.reportThanksBody,
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
                child: Text(
                  l10n.done,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
