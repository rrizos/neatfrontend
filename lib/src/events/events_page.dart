import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    this.preferredTab,
  });

  final String token;
  final String city;
  final UserProfile currentUser;
  final ValueChanged<String> onOpenUserProfile;
  final int? preferredTab;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  int _tab = 0; // 0 = Official, 1 = Community
  bool _loading = true;
  List<EventItem> _events = [];
  final ImagePicker _picker = ImagePicker();
  String _selectedCategory = 'All';
  final Map<int, String> _localCategories = {};
  final Map<int, String> _localDates = {};
  final Set<int> _localAttending = {};

  @override
  void initState() {
    super.initState();
    if (widget.preferredTab != null) _tab = widget.preferredTab!;
    Future.wait([_loadLocalCategories(), _loadLocalDates(), _loadLocalAttending()]).then((_) => _load());
  }

  @override
  void didUpdateWidget(EventsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preferredTab != null &&
        widget.preferredTab != oldWidget.preferredTab) {
      setState(() => _tab = widget.preferredTab!);
    }
  }

  Future<void> _loadLocalCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('event_categories') ?? '{}';
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _localCategories.clear();
      for (final entry in map.entries) {
        final id = int.tryParse(entry.key);
        if (id != null) _localCategories[id] = entry.value.toString();
      }
    } catch (_) {}
  }

  Future<void> _saveLocalCategory(int eventId, String category) async {
    _localCategories[eventId] = category;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'event_categories',
      jsonEncode({for (final e in _localCategories.entries) '${e.key}': e.value}),
    );
  }

  Future<void> _loadLocalDates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('event_dates') ?? '{}';
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _localDates.clear();
      for (final entry in map.entries) {
        final id = int.tryParse(entry.key);
        if (id != null) _localDates[id] = entry.value.toString();
      }
    } catch (_) {}
  }

  Future<void> _saveLocalDate(int eventId, String date) async {
    _localDates[eventId] = date;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'event_dates',
      jsonEncode({for (final e in _localDates.entries) '${e.key}': e.value}),
    );
  }

  Future<void> _loadLocalAttending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('event_attending') ?? '[]';
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _localAttending.clear();
      for (final v in list) {
        final id = int.tryParse(v.toString());
        if (id != null) _localAttending.add(id);
      }
    } catch (_) {}
  }

  Future<void> _saveLocalAttending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('event_attending', jsonEncode(_localAttending.toList()));
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
          .map((e) {
            final localCat = _localCategories[e.id];
            final localDate = _localDates[e.id];
            return EventItem(
              id: e.id, city: e.city, eventType: e.eventType,
              category: (localCat != null && e.category.isEmpty) ? localCat : e.category,
              title: e.title, description: e.description,
              location: e.location, imageUrl: e.imageUrl, creator: e.creator,
              organizer: e.organizer, hasTickets: e.hasTickets,
              ticketsUrl: e.ticketsUrl, attendees: e.attendees,
              isAttending: _localAttending.contains(e.id),
              date: (localDate != null && e.date.isEmpty) ? localDate : e.date,
            );
          })
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (_) => _CreateEventSheet(picker: _picker),
    );
    if (result == null) return;
    final res = await http.post(
      eventsEndpoint(),
      headers: authJsonHeaders(widget.token),
      body: jsonEncode(result),
    );
    if (res.statusCode == 201) {
      final category = result['category'] as String?;
      final date = result['date'] as String?;
      if (category != null && category.isNotEmpty || date != null && date.isNotEmpty) {
        try {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final eventMap = (body['event'] ?? body) as Map<String, dynamic>?;
          final id = int.tryParse(eventMap?['id']?.toString() ?? '');
          if (id != null) {
            if (category != null && category.isNotEmpty) await _saveLocalCategory(id, category);
            if (date != null && date.isNotEmpty) await _saveLocalDate(id, date);
          }
        } catch (_) {}
      }
      await _load();
    }
  }

  Future<void> _attend(EventItem event) async {
    final nowAttending = !event.isAttending;
    if (nowAttending) {
      _localAttending.add(event.id);
    } else {
      _localAttending.remove(event.id);
    }
    await _saveLocalAttending();
    setState(() {
      _events = _events.map((e) {
        if (e.id != event.id) return e;
        return EventItem(
          id: e.id, city: e.city, eventType: e.eventType,
          category: e.category, title: e.title, description: e.description,
          location: e.location, imageUrl: e.imageUrl, creator: e.creator,
          organizer: e.organizer, hasTickets: e.hasTickets,
          ticketsUrl: e.ticketsUrl,
          attendees: nowAttending ? e.attendees + 1 : e.attendees - 1,
          isAttending: nowAttending,
          date: e.date,
        );
      }).toList();
    });
    final res = await http.post(
      eventAttendEndpoint(event.id),
      headers: authJsonHeaders(widget.token),
    );
    if (res.statusCode != 200) {
      if (nowAttending) {
        _localAttending.remove(event.id);
      } else {
        _localAttending.add(event.id);
      }
      await _saveLocalAttending();
      await _load();
    }
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

  void _showEventDetail(EventItem event) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isLight ? Colors.white : const Color(0xff111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EventDetailSheet(
        event: event,
        currentUsername: widget.currentUser.username,
        onAttend: () => _attend(event),
        onDelete: () {
          Navigator.of(context).pop();
          _deleteEvent(event);
        },
      ),
    );
  }

  List<EventItem> get _official =>
      _events.where((e) => e.eventType == 'official').toList();
  List<EventItem> get _community =>
      _events.where((e) => e.eventType == 'community').toList();
  List<EventItem> get _filteredOfficial => _selectedCategory == 'All'
      ? _official
      : _official.where((e) => e.category == _selectedCategory).toList();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final visible = _tab == 0 ? _filteredOfficial : _community;

    return Scaffold(
      backgroundColor: isLight ? const Color(0xfff3f4f6) : const Color(0xff0f0f10),
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xff0f0f10),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xff171717),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isLight ? const Color(0xffd9dee6) : const Color(0xff262626)),
              ),
              child: Icon(Icons.event_outlined, color: isLight ? Colors.black : Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'Events',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isLight ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _createEvent,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(
              children: [
                _TabPill(
                  label: 'Official',
                  selected: _tab == 0,
                  onTap: () => setState(() {
                    _tab = 0;
                    _selectedCategory = 'All';
                  }),
                ),
                const SizedBox(width: 8),
                _TabPill(
                  label: 'Community',
                  selected: _tab == 1,
                  onTap: () => setState(() {
                    _tab = 1;
                    _selectedCategory = 'All';
                  }),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isLight ? const Color(0xffd9dee6) : const Color(0x1fffffff)),
          if (!_loading && _tab == 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 0, 0),
              child: SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: _kEventCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _kEventCategories[index];
                    final sel = cat == _selectedCategory;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? (isLight ? Colors.black : Colors.white)
                              : (isLight ? Colors.white : const Color(0xff1e1e1e)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? Colors.transparent
                                : (isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                          ),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: sel
                                ? (isLight ? Colors.white : Colors.black)
                                : (isLight ? Colors.black : Colors.white),
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? Center(
                        child: Text(
                          'No events yet.',
                          style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xff9c9c9c)),
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(14, 12, 0, 24),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final event = visible[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: SizedBox(
                              width: MediaQuery.sizeOf(context).width - 80,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: _EventCard(
                                  event: event,
                                  currentUsername: widget.currentUser.username,
                                  onAttend: () => _attend(event),
                                  onDelete: () => _deleteEvent(event),
                                  onTap: () => _showEventDetail(event),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

String _formatEventDate(String date) {
  final d = DateTime.tryParse(date);
  if (d == null) return date;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
}

const _kEventCategories = [
  'All',
  'Music Concert',
  'Live Concert',
  'Sports',
  'Art & Culture',
  'Food & Drinks',
  'Tech',
  'Comedy',
  'Networking',
];

class EventItem {
  const EventItem({
    required this.id,
    required this.city,
    required this.eventType,
    required this.category,
    required this.title,
    required this.description,
    required this.location,
    required this.imageUrl,
    required this.creator,
    required this.organizer,
    required this.hasTickets,
    required this.ticketsUrl,
    required this.attendees,
    required this.isAttending,
    required this.date,
  });

  final int id;
  final String city;
  final String eventType;
  final String category;
  final String title;
  final String description;
  final String location;
  final String imageUrl;
  final String creator;
  final String organizer;
  final bool hasTickets;
  final String ticketsUrl;
  final int attendees;
  final bool isAttending;
  final String date;

  factory EventItem.fromJson(Map<String, dynamic> json) {
    int p(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    return EventItem(
      id: p(json['id']),
      city: json['city']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? 'community',
      category: json['category']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      creator: json['creator']?.toString() ?? '',
      organizer: json['organizer']?.toString() ?? '',
      hasTickets: json['hasTickets'] == true,
      ticketsUrl: json['ticketsUrl']?.toString() ?? '',
      attendees: p(json['attendees']),
      isAttending: json['isAttending'] == true,
      date: json['date']?.toString() ?? '',
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.currentUsername,
    required this.onAttend,
    required this.onDelete,
    required this.onTap,
  });

  final EventItem event;
  final String currentUsername;
  final VoidCallback onAttend;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final official = event.eventType == 'official';
    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xff151516),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isLight ? const Color(0xffd9dee6) : const Color(0xff262626)),
        boxShadow: [
          BoxShadow(
            color: isLight ? const Color(0x14000000) : Colors.black54,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (event.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              child: Stack(
                children: [
                  SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: _EventMedia(url: event.imageUrl),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.58),
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
                        shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (official) ...[
                  if (event.imageUrl.isEmpty) ...[
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
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
                  if (event.date.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatEventDate(event.date),
                      style: const TextStyle(
                        color: Color(0xff8f8f8f),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    event.description.isEmpty ? event.title : event.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
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
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
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
                  if (event.date.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatEventDate(event.date),
                      style: const TextStyle(
                        color: Color(0xff8f8f8f),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (event.imageUrl.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        height: 1.35,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${event.attendees} people attending',
                      style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xffb3b3b3)),
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
                  ],
                ),
                Row(
                  children: [
                    if (official && event.hasTickets)
                      Expanded(
                        child: TextButton(
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
                          style: TextButton.styleFrom(
                          backgroundColor: isLight ? const Color(0xffeef1f5) : const Color(0xff1d1d1d),
                          foregroundColor: isLight ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                            ),
                          ),
                          child: const Text('Buy Tickets'),
                        ),
                      ),
                    if (official && event.hasTickets) const SizedBox(width: 10),
                    Expanded(
                      child: event.isAttending
                          ? OutlinedButton(
                              onPressed: onAttend,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isLight ? Colors.black : Colors.white,
                                side: BorderSide(
                                  color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text("Don't Attend"),
                            )
                          : FilledButton(
                              onPressed: onAttend,
                              style: FilledButton.styleFrom(
                                backgroundColor: isLight ? Colors.black : Colors.white,
                                foregroundColor: isLight ? Colors.white : Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Attend'),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: selected ? 44 : 0,
              color: isLight ? Colors.black : Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateEventSheet extends StatefulWidget {
  const _CreateEventSheet({required this.picker});

  final ImagePicker picker;

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  bool _official = false;
  bool _tickets = false;
  String _category = _kEventCategories[1];
  String _imageUrl = '';
  bool _showPhotoError = false;
  DateTime? _date;
  bool _showDateError = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await widget.picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final mime = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    setState(() {
      _imageUrl = 'data:image/$mime;base64,${base64Encode(bytes)}';
      _showPhotoError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                Text(
                  'Create event',
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    if (_title.text.trim().isEmpty || _desc.text.trim().isEmpty) return;
                    if (_date == null) {
                      setState(() => _showDateError = true);
                      return;
                    }
                    if (_official && _imageUrl.isEmpty) {
                      setState(() => _showPhotoError = true);
                      return;
                    }
                    Navigator.of(context).pop({
                      'title': _title.text.trim(),
                      'description': _desc.text.trim(),
                      'eventType': _official ? 'official' : 'community',
                      'hasTickets': _tickets,
                      'date': _date!.toIso8601String().substring(0, 10),
                      if (_official) 'category': _category,
                      if (_imageUrl.isNotEmpty) 'imageUrl': _imageUrl,
                    });
                  },
                  child: const Text('Publish'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              style: TextStyle(color: isLight ? Colors.black : Colors.white),
              decoration: _dec('Title', isLight),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              style: TextStyle(color: isLight ? Colors.black : Colors.white),
              maxLines: 4,
              maxLength: 500,
              decoration: _dec('Description', isLight),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CompactToggle(
                    label: 'Official event',
                    value: _official,
                    onChanged: (v) => setState(() => _official = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactToggle(
                    label: 'Has tickets',
                    value: _tickets,
                    onChanged: (v) => setState(() => _tickets = v),
                  ),
                ),
              ],
            ),
            if (_official) ...[
              const SizedBox(height: 10),
              Text(
                'Category',
                style: TextStyle(
                  color: isLight ? const Color(0xff616161) : const Color(0xff8f8f8f),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: _kEventCategories.length - 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = _kEventCategories[index + 1];
                    final sel = cat == _category;
                    return GestureDetector(
                      onTap: () => setState(() => _category = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? (isLight ? Colors.black : Colors.white)
                              : (isLight ? Colors.white : const Color(0xff1e1e1e)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? Colors.transparent
                                : (isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                          ),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: sel
                                ? (isLight ? Colors.white : Colors.black)
                                : (isLight ? Colors.black : Colors.white),
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                );
                if (picked != null) setState(() { _date = picked; _showDateError = false; });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xff1a1a1b),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _showDateError
                        ? const Color(0xfff66c6c)
                        : (isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 16,
                        color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      _date == null
                          ? 'Choose date'
                          : _formatEventDate(_date!.toIso8601String().substring(0, 10)),
                      style: TextStyle(
                        color: _date == null
                            ? (isLight ? const Color(0xff616161) : const Color(0xff8f8f8f))
                            : (isLight ? Colors.black : Colors.white),
                      ),
                    ),
                    if (_showDateError) ...[
                      const Spacer(),
                      const Text('Required',
                          style: TextStyle(color: Color(0xfff66c6c), fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 1.25,
                  child: _EventMedia(url: _imageUrl),
                ),
              ),
            const SizedBox(height: 10),
            if (_showPhotoError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 15, color: Color(0xfff66c6c)),
                    const SizedBox(width: 6),
                    const Text(
                      'Photo is required for official events',
                      style: TextStyle(color: Color(0xfff66c6c), fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                _ComposerAction(
                  icon: Icons.image_outlined,
                  onTap: _pickImage,
                ),
                const Spacer(),
                Text(
                  'Photos make events feel real',
                  style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xff8f8f8f), fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, bool isLight) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xff8f8f8f)),
        filled: true,
        fillColor: isLight ? Colors.white : const Color(0xff1a1a1b),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isLight ? const Color(0xffd9dee6) : Colors.transparent,
          ),
        ),
      );
}

class _CompactToggle extends StatelessWidget {
  const _CompactToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value ? Colors.white : const Color(0xff1a1a1b),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? Colors.white : const Color(0xff2a2a2a),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: value ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff171717),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

class _EventMedia extends StatelessWidget {
  const _EventMedia({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma > -1) {
        try {
          return Image.memory(
            base64Decode(url.substring(comma + 1)),
            fit: BoxFit.cover,
          );
        } catch (_) {}
      }
    }
    return Image.network(url, fit: BoxFit.cover);
  }
}

class _EventDetailSheet extends StatefulWidget {
  const _EventDetailSheet({
    required this.event,
    required this.currentUsername,
    required this.onAttend,
    required this.onDelete,
  });

  final EventItem event;
  final String currentUsername;
  final VoidCallback onAttend;
  final VoidCallback onDelete;

  @override
  State<_EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<_EventDetailSheet> {
  late bool _isAttending = widget.event.isAttending;
  late int _attendees = widget.event.attendees;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final event = widget.event;
    final official = event.eventType == 'official';

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (event.imageUrl.isNotEmpty)
                  Stack(
                    children: [
                      SizedBox(
                        height: 240,
                        width: double.infinity,
                        child: _EventMedia(url: event.imageUrl),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.65),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20, right: 20, bottom: 18,
                        child: Text(
                          event.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                          ),
                        ),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (event.imageUrl.isEmpty) ...[
                        Text(
                          event.title,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (event.date.isNotEmpty) ...[
                        _DetailRow(icon: Icons.calendar_today_outlined, text: _formatEventDate(event.date)),
                        const SizedBox(height: 8),
                      ],
                      if (event.location.isNotEmpty || event.city.isNotEmpty) ...[
                        _DetailRow(
                          icon: Icons.location_on_outlined,
                          text: event.location.isNotEmpty ? event.location : event.city,
                        ),
                        const SizedBox(height: 8),
                      ],
                      _DetailRow(
                        icon: official ? Icons.verified_outlined : Icons.people_outline,
                        text: '${event.organizer.isEmpty ? (official ? event.city : 'Community') : event.organizer} • ${official ? 'Official' : 'Community'}',
                      ),
                      if (official && event.category.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _DetailRow(icon: Icons.category_outlined, text: event.category),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        '$_attendees people attending',
                        style: TextStyle(
                          color: isLight ? const Color(0xff616161) : const Color(0xffb3b3b3),
                          fontSize: 13,
                        ),
                      ),
                      if (event.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          event.description,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            height: 1.5,
                            fontSize: 15,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          if (official && event.hasTickets) ...[
                            Expanded(
                              child: TextButton(
                                onPressed: event.ticketsUrl.isEmpty
                                    ? null
                                    : () async {
                                        final uri = Uri.tryParse(event.ticketsUrl);
                                        if (uri == null) return;
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      },
                                style: TextButton.styleFrom(
                                  backgroundColor: isLight ? const Color(0xffeef1f5) : const Color(0xff1d1d1d),
                                  foregroundColor: isLight ? Colors.black : Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                                  ),
                                ),
                                child: const Text('Buy Tickets'),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: _isAttending
                                ? OutlinedButton(
                                    onPressed: () {
                                      setState(() { _isAttending = false; _attendees--; });
                                      widget.onAttend();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: isLight ? Colors.black : Colors.white,
                                      side: BorderSide(color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: const Text("Don't Attend"),
                                  )
                                : FilledButton(
                                    onPressed: () {
                                      setState(() { _isAttending = true; _attendees++; });
                                      widget.onAttend();
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: isLight ? Colors.black : Colors.white,
                                      foregroundColor: isLight ? Colors.white : Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: const Text('Attend'),
                                  ),
                          ),
                        ],
                      ),
                      if (event.creator == widget.currentUsername) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: widget.onDelete,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xfff66c6c),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Delete event'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xff8f8f8f)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xff8f8f8f), fontSize: 12),
          ),
        ),
      ],
    );
  }
}
