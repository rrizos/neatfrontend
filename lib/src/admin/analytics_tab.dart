import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/http_client.dart' as http;
import '../core/neat_loader.dart';

// Chart hue: one hue, one step per mode, each validated against its own surface
// (light L 0.43–0.77 band, dark L 0.48–0.67) rather than flipping one value.
const _kHueLight = Color(0xff1479ff);
const _kHueDark = Color(0xff3d8bff);
// Status is reserved — only used when something needs attention.
const _kStatus = Color(0xfff66c6c);

Color _hue(bool isLight) => isLight ? _kHueLight : _kHueDark;
Color _ink(bool isLight) => isLight ? const Color(0xff111111) : Colors.white;
Color _inkMuted(bool isLight) =>
    isLight ? const Color(0xff6b7280) : const Color(0xff9aa0a6);
Color _surfaceAlt(bool isLight) =>
    isLight ? const Color(0xfff5f6f8) : const Color(0xff1a1a1a);
Color _hairline(bool isLight) =>
    isLight ? const Color(0xffe6e8ec) : const Color(0xff2a2a2a);

String _compact(num v) {
  if (v is double && v % 1 != 0) return v.toStringAsFixed(2);
  final n = v.toInt();
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
  return n.toString();
}

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key, required this.token});

  final String token;

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(
        adminAnalyticsEndpoint,
        headers: authGetHeaders(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _data = jsonDecode(res.body) as Map<String, dynamic>;
          _loading = false;
        });
      } else if (res.statusCode == 403) {
        setState(() {
          _error = 'Admin access required';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load analytics (${res.statusCode})';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Network error';
          _loading = false;
        });
      }
    }
  }

  int _int(Map<String, dynamic>? m, String k) =>
      (m?[k] as num?)?.toInt() ?? 0;
  double _dbl(Map<String, dynamic>? m, String k) =>
      (m?[k] as num?)?.toDouble() ?? 0;

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
            Text(_error!, style: TextStyle(color: _inkMuted(isLight))),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final d = _data ?? const {};
    final totals = (d['totals'] as Map?)?.cast<String, dynamic>();
    final growth = (d['growth'] as Map?)?.cast<String, dynamic>();
    final active = (d['active'] as Map?)?.cast<String, dynamic>();
    final engagement = (d['engagement'] as Map?)?.cast<String, dynamic>();
    final cities = ((d['top_cities'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final series = (d['series'] as Map?)?.cast<String, dynamic>();
    final signups = ((series?['signups'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => (e['count'] as num?)?.toInt() ?? 0)
        .toList();
    final posts30 = ((series?['posts'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => (e['count'] as num?)?.toInt() ?? 0)
        .toList();

    final pending = _int(totals, 'reports_pending');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // The two headline numbers: the number is the chart.
          Row(
            children: [
              Expanded(
                child: _HeroTile(
                  label: 'Total users',
                  value: _int(totals, 'users'),
                  sub: '+${_int(growth, 'new_users_7d')} this week',
                  isLight: isLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeroTile(
                  label: 'Total posts',
                  value: _int(totals, 'posts'),
                  sub: '+${_int(growth, 'new_posts_7d')} this week',
                  isLight: isLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _Section(label: 'Active users', isLight: isLight),
          _TileGrid(isLight: isLight, tiles: [
            _Stat('Daily', _compact(_int(active, 'dau'))),
            _Stat('Weekly', _compact(_int(active, 'wau'))),
            _Stat('Monthly', _compact(_int(active, 'mau'))),
            _Stat('Stickiness', '${_dbl(active, 'stickiness')}%'),
          ]),
          const SizedBox(height: 24),

          _Section(label: 'Growth', isLight: isLight),
          _TileGrid(isLight: isLight, tiles: [
            _Stat('Users today', _compact(_int(growth, 'new_users_today'))),
            _Stat('Users 30d', _compact(_int(growth, 'new_users_30d'))),
            _Stat('Posts today', _compact(_int(growth, 'new_posts_today'))),
            _Stat('Posts 30d', _compact(_int(growth, 'new_posts_30d'))),
          ]),
          const SizedBox(height: 24),

          // Two measures on different scales — two charts, never one dual axis.
          _Section(label: 'Last 30 days', isLight: isLight),
          _TrendCard(
            title: 'New users per day',
            values: signups,
            isLight: isLight,
          ),
          const SizedBox(height: 12),
          _TrendCard(
            title: 'New posts per day',
            values: posts30,
            isLight: isLight,
          ),
          const SizedBox(height: 24),

          _Section(label: 'Engagement', isLight: isLight),
          _TileGrid(isLight: isLight, tiles: [
            _Stat('Likes / post', _dbl(engagement, 'avg_likes_per_post').toString()),
            _Stat('Comments / post',
                _dbl(engagement, 'avg_comments_per_post').toString()),
            _Stat('Posts / user', _dbl(engagement, 'posts_per_user').toString()),
            _Stat('Comments', _compact(_int(totals, 'comments'))),
          ]),
          const SizedBox(height: 24),

          if (cities.isNotEmpty) ...[
            _Section(label: 'Top cities', isLight: isLight),
            _CityBars(cities: cities, isLight: isLight),
            const SizedBox(height: 24),
          ],

          _Section(label: 'Content & social', isLight: isLight),
          _TileGrid(isLight: isLight, tiles: [
            _Stat('Likes', _compact(_int(totals, 'likes'))),
            _Stat('Saves', _compact(_int(totals, 'saves'))),
            _Stat('Follows', _compact(_int(totals, 'follows'))),
            _Stat('Events', _compact(_int(totals, 'events'))),
            _Stat('Attending', _compact(_int(totals, 'event_attendances'))),
            _Stat('Conversations', _compact(_int(totals, 'conversations'))),
            _Stat('Messages', _compact(_int(totals, 'messages'))),
            _Stat('Polls', _compact(_int(totals, 'polls'))),
            _Stat('Poll votes', _compact(_int(totals, 'poll_votes'))),
            _Stat('Push devices', _compact(_int(totals, 'push_devices'))),
            _Stat('Verified', _compact(_int(totals, 'verified_users'))),
            _Stat('Blocks', _compact(_int(totals, 'blocks'))),
          ]),
          const SizedBox(height: 24),

          _Section(label: 'Moderation', isLight: isLight),
          _StatusTile(
            label: 'Open reports',
            value: pending,
            // Status color only when it actually means "needs attention",
            // and never color-alone — the label and icon carry it too.
            attention: pending > 0,
            isLight: isLight,
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Updated ${_updatedLabel(d['generated_at']?.toString())}',
              style: TextStyle(color: _inkMuted(isLight), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _updatedLabel(String? iso) {
    if (iso == null) return '—';
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '—';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

class _Stat {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.isLight});
  final String label;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: _inkMuted(isLight),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _HeroTile extends StatelessWidget {
  const _HeroTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.isLight,
  });

  final String label;
  final int value;
  final String sub;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _surfaceAlt(isLight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline(isLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: _inkMuted(isLight), fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Text(
            _compact(value),
            style: TextStyle(
              color: _ink(isLight),
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(color: _inkMuted(isLight), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles, required this.isLight});
  final List<_Stat> tiles;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _surfaceAlt(isLight),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _hairline(isLight)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.label,
                        style: TextStyle(
                          color: _inkMuted(isLight),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.value,
                        style: TextStyle(
                          color: _ink(isLight),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.value,
    required this.attention,
    required this.isLight,
  });

  final String label;
  final int value;
  final bool attention;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final color = attention ? _kStatus : _inkMuted(isLight);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _surfaceAlt(isLight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _hairline(isLight)),
      ),
      child: Row(
        children: [
          Icon(
            attention ? Icons.flag_rounded : Icons.check_circle_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(color: _ink(isLight), fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            value.toString(),
            style: TextStyle(
              color: _ink(isLight),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            attention ? 'to review' : 'clear',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// One measure over 30 days. Single series, so no legend — the title names it.
/// Selective labels only (peak + latest), never a number on every bar.
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.values,
    required this.isLight,
  });

  final String title;
  final List<int> values;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final peak = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
    final latest = values.isEmpty ? 0 : values.last;
    final total = values.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _surfaceAlt(isLight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline(isLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _ink(isLight),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$total total',
                style: TextStyle(color: _inkMuted(isLight), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 76,
            child: CustomPaint(
              size: Size.infinite,
              painter: _BarsPainter(
                values: values,
                hue: _hue(isLight),
                baseline: _hairline(isLight),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '30 days ago',
                style: TextStyle(color: _inkMuted(isLight), fontSize: 11),
              ),
              const Spacer(),
              Text(
                'peak $peak · today $latest',
                style: TextStyle(color: _inkMuted(isLight), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.hue,
    required this.baseline,
  });

  final List<int> values;
  final Color hue;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    // Recessive hairline baseline — solid, one shade off the surface.
    final axis = Paint()
      ..color = baseline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      axis,
    );

    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;

    const gap = 2.0; // surface gap between adjacent bars
    final slot = size.width / values.length;
    final barW = (slot - gap).clamp(1.0, 14.0);
    final fill = Paint()..color = hue;

    for (var i = 0; i < values.length; i++) {
      final h = (values[i] / maxV) * (size.height - 6);
      if (h <= 0) continue;
      final left = i * slot + (slot - barW) / 2;
      final rect = RRect.fromRectAndCorners(
        // Anchored to the baseline, rounded data-end only.
        Rect.fromLTWH(left, size.height - h, barW, h),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rect, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.values != values || old.hue != hue || old.baseline != baseline;
}

/// Ranked magnitude across nominal categories — one hue for every bar (a
/// value-ramp here would double-encode length as color).
class _CityBars extends StatelessWidget {
  const _CityBars({required this.cities, required this.isLight});

  final List<Map<String, dynamic>> cities;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final maxUsers = cities.fold<int>(
      0,
      (a, c) => ((c['users'] as num?)?.toInt() ?? 0) > a
          ? ((c['users'] as num?)?.toInt() ?? 0)
          : a,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: _surfaceAlt(isLight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline(isLight)),
      ),
      child: Column(
        children: [
          for (final c in cities)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c['city']?.toString() ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _ink(isLight),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${(c['users'] as num?)?.toInt() ?? 0} users · '
                        '${(c['posts'] as num?)?.toInt() ?? 0} posts',
                        style: TextStyle(color: _inkMuted(isLight), fontSize: 11.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, cons) {
                      final users = (c['users'] as num?)?.toInt() ?? 0;
                      final frac = maxUsers > 0 ? users / maxUsers : 0.0;
                      return Stack(
                        children: [
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: _hairline(isLight),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          Container(
                            height: 6,
                            width: (cons.maxWidth * frac).clamp(0.0, cons.maxWidth),
                            decoration: BoxDecoration(
                              color: _hue(isLight),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
