import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/models.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({
    super.key,
    required this.token,
    required this.city,
    required this.currentUser,
    required this.onOpenUserProfile,
  });

  final String token;
  final String city;
  final UserProfile currentUser;
  final ValueChanged<String> onOpenUserProfile;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  int _tab = 0;
  bool _loading = true;
  List<EventItem> _events = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        eventsEndpoint(city: widget.city),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode != 200) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final events = (decoded['events'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EventItem.fromJson)
          .toList();
      events.sort((a, b) => b.attendees.compareTo(a.attendees));
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createEvent() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff0f0f10),
      builder: (_) => const _CreateEventSheet(),
    );
    if (result == null) return;
    final res = await http.post(
      eventsEndpoint(),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode(result),
    );
    if (res.statusCode == 201) {
      await _load();
    }
  }

  Future<void> _attend(EventItem event) async {
    final res = await http.post(
      eventAttendEndpoint(event.id),
      headers: authJsonHeaders(widget.token),
    );
    if (res.statusCode != 200) return;
    await _load();
  }

  Future<void> _deleteEvent(EventItem event) async {
    final res = await http.delete(
      eventDeleteEndpoint(event.id),
      headers: authGetHeaders(widget.token),
    );
    if (res.statusCode == 200) {
      await _load();
    }
  }

  Future<void> _openComments(EventItem event) async {
    final comments = await _loadComments(event.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff0f0f10),
      builder: (_) => _EventCommentsSheet(
        event: event,
        token: widget.token,
        comments: comments,
        onChanged: _load,
      ),
    );
  }

  Future<List<EventCommentItem>> _loadComments(int eventId) async {
    try {
      final res = await http.get(
        Uri.parse('${eventsEndpoint().toString()}$eventId/comments/'),
        headers: authGetHeaders(widget.token),
      );
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      return (decoded['comments'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EventCommentItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<EventItem> get _official =>
      _events.where((e) => e.eventType == 'official').toList();
  List<EventItem> get _community =>
      _events.where((e) => e.eventType == 'community').toList();
  List<EventItem> get _popular =>
      [..._events]..sort((a, b) => b.attendees.compareTo(a.attendees));

  @override
  Widget build(BuildContext context) {
    final visible = switch (_tab) {
      1 => _official,
      2 => _community,
      _ => _events,
    };

    return Scaffold(
      backgroundColor: const Color(0xff0f0f10),
      appBar: AppBar(
        backgroundColor: const Color(0xff0f0f10),
        title: const Text(
          'Events',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _createEvent,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Row(
              children: [
                _TabPill(
                  label: 'All',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
                _TabPill(
                  label: 'Official',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
                const SizedBox(width: 8),
                _TabPill(
                  label: 'Community',
                  selected: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x1fffffff)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                    children: [
                      if (_tab == 0 && _popular.isNotEmpty) ...[
                        const Text(
                          'POPULAR TODAY 🔥',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 290,
                          child: PageView.builder(
                            controller: PageController(viewportFraction: 0.92),
                            itemCount: _popular.length > 3 ? 3 : _popular.length,
                            itemBuilder: (context, index) {
                              final event = _popular[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _EventCard(
                                  event: event,
                                  currentUsername: widget.currentUser.username,
                                  onAttend: () => _attend(event),
                                  onComments: () => _openComments(event),
                                  onDelete: () => _deleteEvent(event),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 44),
                          child: Center(
                            child: Text(
                              'No events yet.',
                              style: TextStyle(color: Color(0xff9c9c9c)),
                            ),
                          ),
                        )
                      else
                        ...visible.map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _EventCard(
                              event: event,
                              currentUsername: widget.currentUser.username,
                              onAttend: () => _attend(event),
                              onComments: () => _openComments(event),
                              onDelete: () => _deleteEvent(event),
                            ),
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

class EventItem {
  const EventItem({
    required this.id,
    required this.city,
    required this.eventType,
    required this.title,
    required this.description,
    required this.location,
    required this.imageUrl,
    required this.creator,
    required this.organizer,
    required this.hasTickets,
    required this.ticketsUrl,
    required this.attendees,
  });

  final int id;
  final String city;
  final String eventType;
  final String title;
  final String description;
  final String location;
  final String imageUrl;
  final String creator;
  final String organizer;
  final bool hasTickets;
  final String ticketsUrl;
  final int attendees;

  factory EventItem.fromJson(Map<String, dynamic> json) {
    int p(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return EventItem(
      id: p(json['id']),
      city: json['city']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? 'community',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      creator: json['creator']?.toString() ?? '',
      organizer: json['organizer']?.toString() ?? '',
      hasTickets: json['hasTickets'] == true,
      ticketsUrl: json['ticketsUrl']?.toString() ?? '',
      attendees: p(json['attendees']),
    );
  }
}

class EventCommentItem {
  const EventCommentItem({
    required this.id,
    required this.author,
    required this.text,
    required this.created,
  });

  final int id;
  final String author;
  final String text;
  final DateTime created;

  factory EventCommentItem.fromJson(Map<String, dynamic> json) {
    int p(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return EventCommentItem(
      id: p(json['id']),
      author: json['author']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      created:
          DateTime.tryParse(json['created']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.currentUsername,
    required this.onAttend,
    required this.onComments,
    required this.onDelete,
  });

  final EventItem event;
  final String currentUsername;
  final VoidCallback onAttend;
  final VoidCallback onComments;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final official = event.eventType == 'official';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff171718),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xff262626)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (official && event.imageUrl.isNotEmpty)
            Stack(
              children: [
                Image.network(
                  event.imageUrl,
                  height: 170,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (official) ...[
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.location.isEmpty ? event.city : event.location,
                    style: const TextStyle(
                      color: Color(0xffb3b3b3),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${event.organizer.isEmpty ? event.city : event.organizer} • Official',
                    style: const TextStyle(
                      color: Color(0xff8f8f8f),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    event.description.isEmpty ? event.title : event.description,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.4,
                      fontSize: 15,
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xff2a2a2a),
                        child: Text(
                          initialFor(
                            event.organizer.isNotEmpty
                                ? event.organizer
                                : event.title,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.organizer.isEmpty
                                  ? 'Community'
                                  : event.organizer,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${event.city} • Community',
                              style: const TextStyle(
                                color: Color(0xff8f8f8f),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    event.description.isEmpty ? event.title : event.description,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.35,
                      fontSize: 15,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${event.attendees} people attending',
                      style: const TextStyle(color: Color(0xffb3b3b3)),
                    ),
                    const Spacer(),
                    if (event.creator == currentUsername)
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white,
                        ),
                        onSelected: (value) async {
                          if (value == 'delete') onDelete();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Delete event',
                              style: TextStyle(color: Color(0xfff66c6c)),
                            ),
                          ),
                        ],
                      ),
                    IconButton(
                      onPressed: onComments,
                      icon: const Icon(
                        Icons.mode_comment_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (official && event.hasTickets)
                      TextButton(
                        onPressed: event.ticketsUrl.isEmpty
                            ? null
                            : () async {
                                final uri = Uri.tryParse(event.ticketsUrl);
                                if (uri == null) return;
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                        child: const Text('Buy Tickets'),
                      ),
                    if (official && event.hasTickets) const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: onAttend,
                      child: const Text('Attend'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: selected ? 44 : 0,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateEventSheet extends StatefulWidget {
  const _CreateEventSheet();

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  bool _official = false;
  bool _tickets = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create event',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              style: const TextStyle(color: Colors.white),
              maxLines: 4,
              decoration: _dec('Description'),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: _official,
              onChanged: (v) => setState(() => _official = v),
              title: const Text(
                'Official event',
                style: TextStyle(color: Colors.white),
              ),
            ),
            SwitchListTile(
              value: _tickets,
              onChanged: (v) => setState(() => _tickets = v),
              title: const Text(
                'Has tickets',
                style: TextStyle(color: Colors.white),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop({
                    'title': _title.text.trim(),
                    'description': _desc.text.trim(),
                    'eventType': _official ? 'official' : 'community',
                    'hasTickets': _tickets,
                  });
                },
                child: const Text('Publish'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xff8f8f8f)),
        filled: true,
        fillColor: const Color(0xff1a1a1b),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      );
}

class _EventCommentsSheet extends StatefulWidget {
  const _EventCommentsSheet({
    required this.event,
    required this.comments,
    required this.token,
    required this.onChanged,
  });

  final EventItem event;
  final List<EventCommentItem> comments;
  final String token;
  final Future<void> Function() onChanged;

  @override
  State<_EventCommentsSheet> createState() => _EventCommentsSheetState();
}

class _EventCommentsSheetState extends State<_EventCommentsSheet> {
  final _controller = TextEditingController();
  late List<EventCommentItem> _comments;

  @override
  void initState() {
    super.initState();
    _comments = widget.comments;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final res = await http.post(
      Uri.parse('${eventsEndpoint().toString()}${widget.event.id}/comments/'),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode({'text': text}),
    );
    if (res.statusCode != 201) return;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final comment =
        EventCommentItem.fromJson(decoded['comment'] as Map<String, dynamic>);
    if (!mounted) return;
    setState(() {
      _comments = [..._comments, comment];
      _controller.clear();
    });
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          0,
          14,
          MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Comments',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
            const Divider(height: 1, color: Color(0x1fffffff)),
            const SizedBox(height: 12),
            if (_comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text(
                  'No comments yet.',
                  style: TextStyle(color: Color(0xff9c9c9c)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _comments.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xff232323)),
                  itemBuilder: (_, index) {
                    final comment = _comments[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xff2a2a2a),
                        child: Text(initialFor(comment.author)),
                      ),
                      title: Text(
                        comment.author,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        comment.text,
                        style: const TextStyle(color: Color(0xffb3b3b3)),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      hintStyle: const TextStyle(color: Color(0xff8f8f8f)),
                      filled: true,
                      fillColor: const Color(0xff1a1a1b),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _send,
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
