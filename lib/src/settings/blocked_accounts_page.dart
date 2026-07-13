import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/http_client.dart' as http;

import '../core/api.dart';
import '../core/media_cache.dart';
import '../core/models.dart';

class BlockedAccountsPage extends StatefulWidget {
  const BlockedAccountsPage({super.key, required this.token});

  final String token;

  @override
  State<BlockedAccountsPage> createState() => _BlockedAccountsPageState();
}

class _BlockedAccountsPageState extends State<BlockedAccountsPage> {
  List<UserProfile> _users = [];
  bool _loading = true;
  final Set<String> _working = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(blockedUsersEndpoint, headers: authGetHeaders(widget.token));
      if (res.statusCode != 200 || !mounted) return;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (decoded['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList();
      setState(() { _users = users; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(UserProfile user) async {
    setState(() => _working.add(user.username));
    try {
      final res = await http.post(
        userBlockEndpoint(user.username),
        headers: authJsonHeaders(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _users = _users.where((u) => u.username != user.username).toList();
        });
      }
    } finally {
      if (mounted) setState(() => _working.remove(user.username));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : const Color(0xff121212);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: isLight ? Colors.black : Colors.white,
        elevation: 0,
        title: const Text('Blocked Accounts'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Text(
                    "You haven't blocked anyone.",
                    style: TextStyle(
                      color: isLight ? const Color(0xff616161) : const Color(0xffb3b3b3),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _users.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: isLight ? const Color(0xffd9dee6) : const Color(0xff262626),
                  ),
                  itemBuilder: (_, i) {
                    final user = _users[i];
                    final working = _working.contains(user.username);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                        foregroundImage: user.avatarUrl.isNotEmpty
                            ? CachedNetworkImageProvider(user.avatarUrl, cacheManager: imageCacheManager)
                            : null,
                        child: Text(
                          initialFor(user.username),
                          style: TextStyle(color: isLight ? Colors.black : Colors.white),
                        ),
                      ),
                      title: Text(
                        user.username,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: user.fullName.isNotEmpty ? Text(user.fullName) : null,
                      trailing: OutlinedButton(
                        onPressed: working ? null : () => _unblock(user),
                        child: working
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Unblock'),
                      ),
                    );
                  },
                ),
    );
  }
}
