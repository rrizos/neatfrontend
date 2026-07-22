import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/http_client.dart' as http;
import '../core/neat_loader.dart';

// Status palette — reserved for severity only, never reused as series colors.
// Every badge also carries its label, so severity is never encoded by color alone.
const _kCritical = Color(0xffd7263d);
const _kHigh = Color(0xffe8590c);
const _kMedium = Color(0xffb8860b);
const _kLow = Color(0xff2f6f9f);
const _kGood = Color(0xff2f9e44);

Color _severityColor(String s) {
  switch (s) {
    case 'critical':
      return _kCritical;
    case 'high':
      return _kHigh;
    case 'medium':
      return _kMedium;
    case 'low':
      return _kLow;
    default:
      return const Color(0xff6b7280);
  }
}

Color _ink(bool l) => l ? const Color(0xff111111) : Colors.white;
Color _muted(bool l) => l ? const Color(0xff6b7280) : const Color(0xff9aa0a6);
Color _surface(bool l) => l ? const Color(0xfff5f6f8) : const Color(0xff1a1a1a);
Color _hairline(bool l) => l ? const Color(0xffe6e8ec) : const Color(0xff2a2a2a);

const _kSeverityFilters = ['alerts', 'all', 'critical', 'high', 'medium', 'low', 'info'];
const _kEventFilters = ['all', 'auth', 'threat', 'admin', 'privilege', 'access', 'alert'];

class SecurityTab extends StatefulWidget {
  const SecurityTab({super.key, required this.token});

  final String token;

  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _logs = const [];
  bool _loading = true;
  String? _error;

  String _severity = 'alerts';
  String _eventType = 'all';
  final _searchCtrl = TextEditingController();
  Timer? _poll;
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    // Near-real-time without a socket: the admin panel is low-traffic, so a
    // short poll is the right cost/benefit here.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final headers = authGetHeaders(widget.token);
      final results = await Future.wait([
        http.get(adminSecuritySummaryEndpoint, headers: headers),
        http.get(
          adminSecurityLogsEndpoint(
            severity: _severity,
            eventType: _eventType,
            query: _searchCtrl.text,
            limit: 120,
          ),
          headers: headers,
        ),
      ]);
      if (!mounted) return;
      final sRes = results[0];
      final lRes = results[1];
      if (sRes.statusCode == 403 || lRes.statusCode == 403) {
        setState(() { _error = 'Admin access required'; _loading = false; });
        return;
      }
      if (sRes.statusCode != 200 || lRes.statusCode != 200) {
        setState(() { _error = 'Failed to load security data'; _loading = false; });
        return;
      }
      final logs = ((jsonDecode(lRes.body) as Map)['logs'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      setState(() {
        _summary = (jsonDecode(sRes.body) as Map).cast<String, dynamic>();
        _logs = logs;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted && !silent) {
        setState(() { _error = 'Network error'; _loading = false; });
      }
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(silent: true));
  }

  Future<void> _action(String action, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_actionTitle(action)),
        content: Text(_actionBody(action, username)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _actionConfirm(action),
              style: const TextStyle(color: _kCritical),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final res = await http.post(
        adminSecurityActionsEndpoint,
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'action': action, 'username': username}),
      );
      if (!mounted) return;
      final ok = res.statusCode == 200;
      String msg;
      if (ok) {
        msg = '${_actionTitle(action)} — done';
      } else {
        try {
          msg = (jsonDecode(res.body) as Map)['error']?.toString() ?? 'Action failed';
        } catch (_) {
          msg = 'Action failed (${res.statusCode})';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _load(silent: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Network error')));
      }
    }
  }

  String _actionTitle(String a) => switch (a) {
        'lock_account' => 'Lock account',
        'unlock_account' => 'Unlock account',
        'revoke_sessions' => 'Revoke sessions',
        _ => 'Action',
      };

  String _actionConfirm(String a) => switch (a) {
        'lock_account' => 'Lock',
        'unlock_account' => 'Unlock',
        'revoke_sessions' => 'Revoke',
        _ => 'Confirm',
      };

  String _actionBody(String a, String u) => switch (a) {
        'lock_account' =>
          'Disable "$u" and revoke every session/API token. They will be signed out immediately and cannot sign in until unlocked.',
        'unlock_account' => 'Re-enable "$u" so they can sign in again.',
        'revoke_sessions' =>
          'Sign "$u" out of all devices by revoking every session/API token. The account stays active.',
        _ => 'Proceed?',
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (_loading) return const NeatLoader();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: _muted(isLight))),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final s = _summary ?? const {};
    final last24 = ((s['last24h'] as Map?) ?? const {}).cast<String, dynamic>();
    final integrity = ((s['integrity'] as Map?) ?? const {}).cast<String, dynamic>();
    final critical = (last24['critical'] as num?)?.toInt() ?? 0;
    final high = (last24['high'] as num?)?.toInt() ?? 0;
    final chainOk = integrity['ok'] == true;
    final dropped = (s['droppedRecords'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          if (critical > 0 || high > 0)
            _AlertBanner(critical: critical, high: high, isLight: isLight),
          if (!chainOk)
            _IntegrityBanner(
              firstBadId: (integrity['firstBadId'] as num?)?.toInt(),
              isLight: isLight,
            ),
          if (dropped > 0)
            _NoticeBanner(
              text: '$dropped audit record(s) dropped under load — queue saturated.',
              isLight: isLight,
            ),

          _SeverityRow(counts: last24, isLight: isLight),
          const SizedBox(height: 10),
          _MetaRow(
            chainOk: chainOk,
            checked: (integrity['checked'] as num?)?.toInt() ?? 0,
            locked: (s['lockedAccounts'] as num?)?.toInt() ?? 0,
            total: (s['totalEvents'] as num?)?.toInt() ?? 0,
            isLight: isLight,
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: TextStyle(color: _ink(isLight), fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search actor, IP, path, message…',
              hintStyle: TextStyle(color: _muted(isLight), fontSize: 14),
              prefixIcon: Icon(Icons.search, size: 18, color: _muted(isLight)),
              isDense: true,
              filled: true,
              fillColor: _surface(isLight),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _hairline(isLight)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _hairline(isLight)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _FilterChips(
            values: _kSeverityFilters,
            selected: _severity,
            isLight: isLight,
            onSelect: (v) {
              setState(() => _severity = v);
              _load(silent: true);
            },
          ),
          const SizedBox(height: 6),
          _FilterChips(
            values: _kEventFilters,
            selected: _eventType,
            isLight: isLight,
            onSelect: (v) {
              setState(() => _eventType = v);
              _load(silent: true);
            },
          ),
          const SizedBox(height: 12),

          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No events match these filters.',
                  style: TextStyle(color: _muted(isLight)),
                ),
              ),
            )
          else
            for (final log in _logs)
              _LogRow(
                log: log,
                isLight: isLight,
                onAction: _action,
              ),
        ],
      ),
    );
  }
}

// ─── Banners & header ────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.critical, required this.high, required this.isLight});
  final int critical;
  final int high;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final color = critical > 0 ? _kCritical : _kHigh;
    final parts = [
      if (critical > 0) '$critical critical',
      if (high > 0) '$high high',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$parts severity event(s) in the last 24h',
              style: TextStyle(
                color: _ink(isLight),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegrityBanner extends StatelessWidget {
  const _IntegrityBanner({required this.firstBadId, required this.isLight});
  final int? firstBadId;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _kCritical.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kCritical),
      ),
      child: Row(
        children: [
          const Icon(Icons.gpp_bad_rounded, color: _kCritical, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Audit chain broken from entry #${firstBadId ?? '?'} — a record was '
              'altered or removed outside the application.',
              style: TextStyle(
                color: _ink(isLight),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text, required this.isLight});
  final String text;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kMedium.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kMedium.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: _kMedium, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: TextStyle(color: _ink(isLight), fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _SeverityRow extends StatelessWidget {
  const _SeverityRow({required this.counts, required this.isLight});
  final Map<String, dynamic> counts;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    const order = ['critical', 'high', 'medium', 'low', 'info'];
    return Row(
      children: [
        for (final s in order) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: _surface(isLight),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _hairline(isLight)),
              ),
              child: Column(
                children: [
                  Text(
                    '${(counts[s] as num?)?.toInt() ?? 0}',
                    style: TextStyle(
                      color: _ink(isLight),
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _severityColor(s),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s == 'critical' ? 'crit' : s,
                        style: TextStyle(color: _muted(isLight), fontSize: 10.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (s != order.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.chainOk,
    required this.checked,
    required this.locked,
    required this.total,
    required this.isLight,
  });
  final bool chainOk;
  final int checked;
  final int locked;
  final int total;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          chainOk ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
          size: 15,
          color: chainOk ? _kGood : _kCritical,
        ),
        const SizedBox(width: 5),
        Text(
          chainOk ? 'Chain verified ($checked)' : 'Chain broken',
          style: TextStyle(
            color: chainOk ? _kGood : _kCritical,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '$locked locked · $total events',
          style: TextStyle(color: _muted(isLight), fontSize: 11.5),
        ),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.values,
    required this.selected,
    required this.isLight,
    required this.onSelect,
  });
  final List<String> values;
  final String selected;
  final bool isLight;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final v = values[i];
          final on = v == selected;
          return GestureDetector(
            onTap: () => onSelect(v),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: on ? _ink(isLight) : _surface(isLight),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _hairline(isLight)),
              ),
              child: Text(
                v,
                style: TextStyle(
                  color: on ? (isLight ? Colors.white : Colors.black) : _muted(isLight),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Log row ─────────────────────────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.isLight, required this.onAction});

  final Map<String, dynamic> log;
  final bool isLight;
  final void Function(String action, String username) onAction;

  String _time() {
    final t = DateTime.tryParse(log['created']?.toString() ?? '')?.toLocal();
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final severity = log['severity']?.toString() ?? 'info';
    final color = _severityColor(severity);
    final actor = log['actor']?.toString() ?? '';
    final meta = (log['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surface(isLight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _hairline(isLight)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              _SeverityBadge(severity: severity, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  log['eventType']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink(isLight),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _time(),
                style: TextStyle(color: _muted(isLight), fontSize: 11),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              log['message']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _muted(isLight), fontSize: 12),
            ),
          ),
          children: [
            _kv('Actor', actor.isEmpty ? '—' : actor, isLight),
            _kv('IP', log['ip']?.toString() ?? '—', isLight),
            _kv('Session', log['sessionId']?.toString() ?? '—', isLight),
            _kv(
              'Request',
              '${log['method'] ?? ''} ${log['path'] ?? ''} '
                  '${log['statusCode'] != null ? '→ ${log['statusCode']}' : ''}'.trim(),
              isLight,
            ),
            _kv('MFA', log['mfa']?.toString() ?? 'none', isLight),
            _kv('User agent', log['userAgent']?.toString() ?? '—', isLight),
            if (meta.isNotEmpty) _kv('Metadata', jsonEncode(meta), isLight),
            _kv('Hash', log['entryHash']?.toString() ?? '—', isLight),
            if (actor.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionButton(
                    label: 'Revoke sessions',
                    icon: Icons.logout_rounded,
                    color: _kHigh,
                    onTap: () => onAction('revoke_sessions', actor),
                  ),
                  _ActionButton(
                    label: 'Lock account',
                    icon: Icons.lock_outline_rounded,
                    color: _kCritical,
                    onTap: () => onAction('lock_account', actor),
                  ),
                  _ActionButton(
                    label: 'Unlock',
                    icon: Icons.lock_open_rounded,
                    color: _kGood,
                    onTap: () => onAction('unlock_account', actor),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              k,
              style: TextStyle(color: _muted(isLight), fontSize: 11.5),
            ),
          ),
          Expanded(
            child: SelectableText(
              v.isEmpty ? '—' : v,
              style: TextStyle(color: _ink(isLight), fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity, required this.color});
  final String severity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      // Label + color together: severity is never conveyed by color alone.
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
