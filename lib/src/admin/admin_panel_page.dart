import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';

class AdminPanelPage extends StatelessWidget {
  final String token;

  const AdminPanelPage({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isLight ? Colors.white : const Color(0xff0a0a0a),
        appBar: AppBar(
          backgroundColor: isLight ? Colors.white : const Color(0xff121212),
          title: Text(
            'Admin Panel',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isLight ? Colors.black : Colors.white,
            ),
          ),
          bottom: TabBar(
            labelColor: const Color(0xff0095f6),
            unselectedLabelColor: isLight ? const Color(0xff737373) : const Color(0xffa8a8a8),
            indicatorColor: const Color(0xff0095f6),
            tabs: const [
              Tab(text: 'Reports'),
              Tab(text: 'Users'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReportsTab(token: token),
            _UsersTab(token: token),
          ],
        ),
      ),
    );
  }
}

// ─── Reports Tab ─────────────────────────────────────────────────────────────

class _ReportsTab extends StatefulWidget {
  final String token;
  const _ReportsTab({required this.token});

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<_Report> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(adminReportsEndpoint, headers: authGetHeaders(widget.token));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['reports'] as List).cast<Map<String, dynamic>>();
        setState(() {
          _reports = list.map(_Report.fromJson).toList();
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to load reports'; _loading = false; });
      }
    } catch (_) {
      setState(() { _error = 'Network error'; _loading = false; });
    }
  }

  Future<void> _deletePost(int postId, int reportId) async {
    await http.delete(adminDeletePostEndpoint(postId), headers: authGetHeaders(widget.token));
    setState(() => _reports.removeWhere((r) => r.postId == postId));
    if (mounted) _showSnack('Post deleted');
  }

  Future<void> _dismissReport(int reportId) async {
    await http.delete(adminDismissReportEndpoint(reportId), headers: authGetHeaders(widget.token));
    setState(() => _reports.removeWhere((r) => r.id == reportId));
    if (mounted) _showSnack('Report dismissed');
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xfff66c6c))),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined, size: 48,
                color: isLight ? const Color(0xffb0b0b0) : const Color(0xff444444)),
            const SizedBox(height: 12),
            Text('No reports', style: TextStyle(
              color: isLight ? const Color(0xff737373) : const Color(0xffa8a8a8),
              fontSize: 16,
            )),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: 0),
        itemBuilder: (_, i) => _ReportCard(
          report: _reports[i],
          onDeletePost: () => _deletePost(_reports[i].postId, _reports[i].id),
          onDismiss: () => _dismissReport(_reports[i].id),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final _Report report;
  final VoidCallback onDeletePost;
  final VoidCallback onDismiss;

  const _ReportCard({
    required this.report,
    required this.onDeletePost,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardColor = isLight ? Colors.white : const Color(0xff1a1a1a);
    final textColor = isLight ? Colors.black : Colors.white;
    final subColor = isLight ? const Color(0xff737373) : const Color(0xffa8a8a8);
    final divColor = isLight ? const Color(0xffe8e8e8) : const Color(0xff2a2a2a);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.06 : 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: reporter info + reason
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xfff66c6c).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.flag_rounded, size: 16, color: Color(0xfff66c6c)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${report.reporterUsername}  reported a post',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                      ),
                      Text(
                        _timeAgo(report.created),
                        style: TextStyle(fontSize: 11, color: subColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Reason chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(
              spacing: 6,
              children: [
                _Chip(label: report.reason, color: const Color(0xfff66c6c)),
                if (report.subReason.isNotEmpty)
                  _Chip(label: report.subReason, color: const Color(0xffff9800)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: divColor),
          // Post preview
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              'Post by @${report.postAuthor}',
              style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              report.postText.isEmpty ? '(no text)' : report.postText,
              style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Divider(height: 1, color: divColor),
          // Actions
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Dismiss'),
                  style: TextButton.styleFrom(
                    foregroundColor: subColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              Container(width: 1, height: 32, color: divColor),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _confirmDeletePost(context),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete Post'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xfff66c6c),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDeletePost(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This will permanently delete the post and all its reports.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(context); onDeletePost(); },
            child: const Text('Delete', style: TextStyle(color: Color(0xfff66c6c))),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Users Tab ────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  final String token;
  const _UsersTab({required this.token});

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<_AdminUser> _users = [];
  bool _loading = false;
  String? _error;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.get(adminUsersEndpoint(q), headers: authGetHeaders(widget.token));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['users'] as List).cast<Map<String, dynamic>>();
        setState(() {
          _users = list.map(_AdminUser.fromJson).toList();
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to load users'; _loading = false; });
      }
    } catch (_) {
      setState(() { _error = 'Network error'; _loading = false; });
    }
  }

  Future<void> _toggleVerify(_AdminUser user) async {
    final res = await http.post(
      adminVerifyUserEndpoint(user.username),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'verified': !user.isVerified}),
    );
    if (res.statusCode == 200) {
      setState(() {
        final idx = _users.indexWhere((u) => u.username == user.username);
        if (idx != -1) _users[idx] = _users[idx].copyWith(isVerified: !user.isVerified);
      });
    }
  }

  Future<void> _toggleOfficialEligibility(_AdminUser user) async {
    final res = await http.post(
      adminSetOfficialEligibilityEndpoint(user.username),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'eligible': !user.canCreateOfficialEvents}),
    );
    if (res.statusCode == 200) {
      setState(() {
        final idx = _users.indexWhere((u) => u.username == user.username);
        if (idx != -1) {
          _users[idx] = _users[idx].copyWith(canCreateOfficialEvents: !user.canCreateOfficialEvents);
        }
      });
    }
  }

  Future<void> _deleteUser(_AdminUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text('This will permanently delete @${user.username} and all their data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xfff66c6c))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await http.delete(adminDeleteUserEndpoint(user.username), headers: authGetHeaders(widget.token));
    if (res.statusCode == 200) {
      setState(() => _users.removeWhere((u) => u.username == user.username));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('@${user.username} deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final subColor = isLight ? const Color(0xff737373) : const Color(0xffa8a8a8);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _ctrl,
            onChanged: (q) => _search(q),
            decoration: InputDecoration(
              hintText: 'Search users...',
              hintStyle: TextStyle(color: subColor),
              prefixIcon: Icon(Icons.search, color: subColor),
              filled: true,
              fillColor: isLight ? Colors.white : const Color(0xff1a1a1a),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Color(0xfff66c6c))))
                  : _users.isEmpty
                      ? Center(child: Text('No users found', style: TextStyle(color: subColor)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          itemCount: _users.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _UserCard(
                            user: _users[i],
                            onVerify: () => _toggleVerify(_users[i]),
                            onToggleOfficialEligibility: () => _toggleOfficialEligibility(_users[i]),
                            onDelete: () => _deleteUser(_users[i]),
                          ),
                        ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final _AdminUser user;
  final VoidCallback onVerify;
  final VoidCallback onToggleOfficialEligibility;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.onVerify,
    required this.onToggleOfficialEligibility,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardColor = isLight ? Colors.white : const Color(0xff1a1a1a);
    final textColor = isLight ? Colors.black : Colors.white;
    final subColor = isLight ? const Color(0xff737373) : const Color(0xffa8a8a8);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.06 : 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              child: Text(
                user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
              ),
            ),
            const SizedBox(width: 12),
            // Username + badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '@${user.username}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 14, color: Color(0xff0095f6)),
                      ],
                      if (user.canCreateOfficialEvents) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.event_available_rounded, size: 14, color: Color(0xff34c759)),
                      ],
                      if (user.isAdmin) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.shield_rounded, size: 14, color: Color(0xffffd700)),
                      ],
                    ],
                  ),
                  if (user.fullName.isNotEmpty)
                    Text(user.fullName, style: TextStyle(fontSize: 12, color: subColor)),
                  Text(
                    '${user.followers} followers · ${user.following} following',
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                ],
              ),
            ),
            // Actions
            IconButton(
              tooltip: user.isVerified ? 'Remove verification' : 'Verify user',
              icon: Icon(
                user.isVerified ? Icons.verified_rounded : Icons.verified_outlined,
                color: user.isVerified ? const Color(0xff0095f6) : subColor,
                size: 22,
              ),
              onPressed: onVerify,
            ),
            IconButton(
              tooltip: user.canCreateOfficialEvents
                  ? 'Revoke official event badge'
                  : 'Grant official event badge',
              icon: Icon(
                user.canCreateOfficialEvents
                    ? Icons.event_available_rounded
                    : Icons.event_available_outlined,
                color: user.canCreateOfficialEvents ? const Color(0xff34c759) : subColor,
                size: 22,
              ),
              onPressed: onToggleOfficialEligibility,
            ),
            IconButton(
              tooltip: 'Delete user',
              icon: const Icon(Icons.delete_outline, color: Color(0xfff66c6c), size: 22),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

class _Report {
  final int id;
  final String reason;
  final String subReason;
  final DateTime created;
  final String reporterUsername;
  final int postId;
  final String postAuthor;
  final String postText;

  const _Report({
    required this.id,
    required this.reason,
    required this.subReason,
    required this.created,
    required this.reporterUsername,
    required this.postId,
    required this.postAuthor,
    required this.postText,
  });

  factory _Report.fromJson(Map<String, dynamic> j) => _Report(
    id: j['id'] as int,
    reason: j['reason']?.toString() ?? '',
    subReason: j['subReason']?.toString() ?? '',
    created: DateTime.tryParse(j['created']?.toString() ?? '') ?? DateTime.now(),
    reporterUsername: (j['reporter'] as Map?)?['username']?.toString() ?? '',
    postId: (j['post'] as Map?)?['id'] as int? ?? 0,
    postAuthor: (j['post'] as Map?)?['author']?.toString() ?? '',
    postText: (j['post'] as Map?)?['text']?.toString() ?? '',
  );
}

class _AdminUser {
  final int id;
  final String username;
  final String fullName;
  final int followers;
  final int following;
  final bool isVerified;
  final bool isAdmin;
  final bool canCreateOfficialEvents;

  const _AdminUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.followers,
    required this.following,
    required this.isVerified,
    required this.isAdmin,
    required this.canCreateOfficialEvents,
  });

  factory _AdminUser.fromJson(Map<String, dynamic> j) {
    int parseInt(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return _AdminUser(
      id: parseInt(j['id']),
      username: j['username']?.toString() ?? '',
      fullName: j['fullName']?.toString() ?? '',
      followers: parseInt(j['followers']),
      following: parseInt(j['following']),
      isVerified: j['isVerified'] == true,
      isAdmin: j['isAdmin'] == true,
      canCreateOfficialEvents: j['canCreateOfficialEvents'] == true,
    );
  }

  _AdminUser copyWith({bool? isVerified, bool? canCreateOfficialEvents}) => _AdminUser(
    id: id, username: username, fullName: fullName,
    followers: followers, following: following,
    isVerified: isVerified ?? this.isVerified,
    isAdmin: isAdmin,
    canCreateOfficialEvents: canCreateOfficialEvents ?? this.canCreateOfficialEvents,
  );
}
