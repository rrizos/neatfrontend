import 'dart:convert';

import 'package:flutter/material.dart';
import '../core/http_client.dart' as http;

import '../../l10n/app_localizations.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/neat_loader.dart';


class NeatPassPage extends StatefulWidget {
  const NeatPassPage({
    super.key,
    required this.token,
    required this.currentUser,
  });

  final String token;
  final UserProfile currentUser;

  @override
  State<NeatPassPage> createState() => _NeatPassPageState();
}

class _NeatPassPageState extends State<NeatPassPage> {
  int? _points;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Try the dedicated endpoint first; fall back to computing from virals.
    try {
      final res = await http.get(neatPassEndpoint, headers: authGetHeaders(widget.token));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _points = (data['points'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    await _loadFromVirals();
  }

  Future<void> _loadFromVirals() async {
    try {
      final endpoint = viralPostsEndpoint(
        city: widget.currentUser.city,
        period: 'daily',
      );
      final res = await http.get(endpoint, headers: authGetHeaders(widget.token));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List?)?.cast<Map<String, dynamic>>() ?? [];
        var total = 0.0;
        for (final p in list) {
          if (p['author']?.toString() != widget.currentUser.username) continue;
          final likes = (p['likes'] as num?)?.toDouble() ?? 0;
          final comments = (p['comment_count'] as num?)?.toDouble() ?? 0;
          final shares = ((p['shares'] ?? p['share_count']) as num?)?.toDouble() ?? 0;
          total += (likes * 0.33 + comments * 0.33 + shares * 0.33) * 100;
        }
        setState(() { _points = total.round(); _loading = false; });
      } else {
        setState(() { _points = 0; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _points = 0; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: isLight ? const Color(0xfff2f2f7) : Colors.black,
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xff0d0d0d),
        surfaceTintColor: Colors.transparent,
        title: Text(
          loc.neatPass,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isLight ? Colors.black : Colors.white,
          ),
        ),
        iconTheme: IconThemeData(color: isLight ? Colors.black : Colors.white),
      ),
      body: _loading
          ? const Center(child: NeatLoader())
          : _error
              ? _buildError(loc)
              : _buildContent(loc),
    );
  }

  Widget _buildError(AppLocalizations loc) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Color(0xff8e8e93)),
          const SizedBox(height: 12),
          Text(
            loc.somethingWentWrong,
            style: const TextStyle(color: Color(0xff8e8e93)),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: () { setState(() { _loading = true; _error = false; }); _load(); }, child: Text(loc.retry)),
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations loc) {
    final points = _points ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NeatPassCard(
            username: widget.currentUser.username,
            displayName: widget.currentUser.fullName,
            avatarUrl: widget.currentUser.avatarUrl,
            points: points,
          ),
          const SizedBox(height: 28),
          _SectionHeader(title: loc.neatPoints),
          const SizedBox(height: 12),
          _PointsRow(label: loc.neatPassCurrentPoints, value: points),
          const SizedBox(height: 28),
          _SectionHeader(title: loc.neatPassHowToEarn),
          const SizedBox(height: 12),
          _EarnTile(
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xffFF3B30),
            title: 'Virals',
            subtitle: 'Points are earned when your post enters Virals and keep updating based on your engagement score while you stay in it.',
          ),
        ],
      ),
    );
  }
}

class _NeatPassCard extends StatelessWidget {
  const _NeatPassCard({
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.points,
  });

  final String username;
  final String displayName;
  final String? avatarUrl;
  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xff0a84ff), Color(0xff0055cc)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x440a84ff), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/neat_logo.png',
              width: 62,
              height: 62,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
            ),
            const Spacer(),
            Text(
              '$points pts',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              displayName.isNotEmpty ? displayName : '@$username',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '@$username',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isLight ? const Color(0xff8e8e93) : const Color(0xff636366),
        letterSpacing: 0.3,
      ),
    );
  }
}

class _PointsRow extends StatelessWidget {
  const _PointsRow({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xff1c1c1e),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.stars_rounded, color: Color(0xffFFCC00), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: isLight ? Colors.black : Colors.white,
              ),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xff0a84ff),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarnTile extends StatelessWidget {
  const _EarnTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xff1c1c1e),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isLight ? const Color(0xff8e8e93) : const Color(0xff636366),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
