import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/api.dart';
import '../core/media_cache.dart';
import '../core/models.dart';
import '../core/post_card.dart' show decodeAvatarUrl;
import '../core/report_post_sheet.dart';

const _kMapToken =
    'eyJraWQiOiIySDdDRjVUOVRSIiwidHlwIjoiSldUIiwiYWxnIjoiRVMyNTYifQ'
    '.eyJpc3MiOiJSWjM2UE5XUzgyIiwiaWF0IjoxNzUyMDkwNjM2LCJvcmlnaW4iO'
    'iJuZXRuZXN0Lm5ldCJ9.r9qHYkpSBP65h1O9HkVJcxiYN4rHgtwdHgLyhbS0f'
    'FnbZOlvx5LcYZELtt4Q7MBQEGDFICKLp-9nUpsMlA-ZuQ';
const _kMapKitCdn = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js';

String? _eventMapkitJs;

// Strips the "lat,lon|" coordinate prefix that gets stored when a Nominatim
// suggestion is selected. Returns the human-readable part for display.
String _locationDisplay(String loc) {
  final pipe = loc.indexOf('|');
  return pipe >= 0 ? loc.substring(pipe + 1) : loc;
}

// Persists attending state for the app session, scoped per username.
// Survives EventsPage being popped and re-pushed; isolated per account.
final _kSessionAttending = <String, Map<int, bool>>{};

String _timeAgo(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

class EventsPage extends StatefulWidget {
  const EventsPage({
    super.key,
    required this.token,
    required this.city,
    required this.currentUser,
    required this.onOpenUserProfile,
    this.preferredTab,
    this.attendEnabled = true,
  });

  final String token;
  final String city;
  final UserProfile currentUser;
  final ValueChanged<String> onOpenUserProfile;
  final int? preferredTab;
  final bool attendEnabled;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  int _tab = 0; // 0 = Official, 1 = Community
  bool _loading = true;
  bool _isOffline = false;
  List<EventItem> _events = [];
  final ImagePicker _picker = ImagePicker();
  String _selectedCategory = 'All';

  String get _cacheKey => 'neat_events_cache_${widget.city}';
  Map<int, bool> get _myAttending =>
      _kSessionAttending.putIfAbsent(widget.currentUser.username, () => {});

  @override
  void initState() {
    super.initState();
    if (widget.preferredTab != null) _tab = widget.preferredTab!;
    _loadEventsCache().then((_) => _load());
  }

  Future<void> _saveEventsCache(List<dynamic> raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(raw));
    } catch (_) {}
  }

  Future<void> _loadEventsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || !mounted) return;
      final events = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(EventItem.fromJson)
          .toList();
      events.sort((a, b) => b.attendees.compareTo(a.attendees));
      if (!mounted || events.isEmpty) return;
      setState(() { _events = events; _loading = false; });
    } catch (_) {}
  }

  @override
  void didUpdateWidget(EventsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preferredTab != null &&
        widget.preferredTab != oldWidget.preferredTab) {
      setState(() => _tab = widget.preferredTab!);
    }
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
      final rawList = (decoded['events'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      unawaited(_saveEventsCache(rawList));
      final events = rawList.map(EventItem.fromJson).toList();
      events.sort((a, b) => b.attendees.compareTo(a.attendees));
      if (!mounted) return;
      setState(() { _events = events; _loading = false; _isOffline = false; });
    } catch (e) {
      final offline = e is SocketException || e is HandshakeException || e is HttpException;
      if (mounted) setState(() { _loading = false; _isOffline = offline; });
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
      body: jsonEncode({...result, 'city': widget.city}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await _load();
      if (mounted) {
        final isOfficial = (result['eventType'] as String?) == 'official';
        setState(() => _tab = isOfficial ? 0 : 1);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event published!'), duration: Duration(seconds: 3)),
        );
      }
    } else if (mounted) {
      final body = res.body.trim();
      final msg = body.length > 120 ? body.substring(0, 120) : body;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create event (${res.statusCode}): $msg'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  // Returns a copy of [e] with the session-attending override applied.
  // The session map survives EventsPage being popped/re-pushed (like FeedPost.liked).
  EventItem _effective(EventItem e) {
    final ia = _myAttending[e.id];
    if (ia == null) return e;
    return EventItem(
      id: e.id, city: e.city, eventType: e.eventType,
      category: e.category, title: e.title, description: e.description,
      location: e.location, imageUrl: e.imageUrl, creator: e.creator,
      organizer: e.organizer, hasTickets: e.hasTickets,
      ticketsUrl: e.ticketsUrl,
      attendees: e.attendees,
      isAttending: ia,
      date: e.date,
    );
  }

  Future<void> _attend(EventItem event) async {
    final cur = _myAttending[event.id] ?? event.isAttending;
    final next = !cur;
    setState(() {
      _myAttending[event.id] = next;
      _events = _events.map((e) {
        if (e.id != event.id) return e;
        return EventItem(
          id: e.id, city: e.city, eventType: e.eventType,
          category: e.category, title: e.title, description: e.description,
          location: e.location, imageUrl: e.imageUrl, creator: e.creator,
          organizer: e.organizer, hasTickets: e.hasTickets,
          ticketsUrl: e.ticketsUrl,
          attendees: next ? e.attendees + 1 : e.attendees - 1,
          isAttending: next,
          date: e.date,
        );
      }).toList();
    });
    final res = await http.post(eventAttendEndpoint(event.id), headers: authGetHeaders(widget.token));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      setState(() {
        _myAttending[event.id] = cur;
        _events = _events.map((e) {
          if (e.id != event.id) return e;
          return EventItem(
            id: e.id, city: e.city, eventType: e.eventType,
            category: e.category, title: e.title, description: e.description,
            location: e.location, imageUrl: e.imageUrl, creator: e.creator,
            organizer: e.organizer, hasTickets: e.hasTickets,
            ticketsUrl: e.ticketsUrl,
            attendees: cur ? e.attendees + 1 : e.attendees - 1,
            isAttending: cur,
            date: e.date,
          );
        }).toList();
      });
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

  void _reportEvent(EventItem event) {
    showReportEventSheet(context, eventId: event.id, token: widget.token);
  }

  Future<void> _editEvent(EventItem event) async {
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
      builder: (_) => _EditEventSheet(event: event, picker: _picker),
    );
    if (result == null) return;
    final payload = jsonEncode({...result, 'city': widget.city});

    // Try the most common REST patterns in order until one succeeds
    http.Response res;
    res = await http.patch(eventDetailEndpoint(event.id),
        headers: authJsonHeaders(widget.token), body: payload);
    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.put(eventDetailEndpoint(event.id),
          headers: authJsonHeaders(widget.token), body: payload);
    }
    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.post(eventUpdateEndpoint(event.id),
          headers: authJsonHeaders(widget.token), body: payload);
    }
    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.patch(eventUpdateEndpoint(event.id),
          headers: authJsonHeaders(widget.token), body: payload);
    }

    if (!mounted) return;

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Optimistically reflect the edited fields in local state immediately
      final updated = EventItem(
        id: event.id,
        city: widget.city,
        eventType: (result['eventType'] as String?) ?? event.eventType,
        category: (result['category'] as String?) ?? event.category,
        title: (result['title'] as String?) ?? event.title,
        description: (result['description'] as String?) ?? event.description,
        location: (result['location'] as String?) ?? event.location,
        imageUrl: (result['imageUrl'] as String?) ?? event.imageUrl,
        creator: event.creator,
        organizer: event.organizer,
        hasTickets: (result['hasTickets'] as bool?) ?? event.hasTickets,
        ticketsUrl: (result['ticketsUrl'] as String?) ?? event.ticketsUrl,
        attendees: event.attendees,
        isAttending: event.isAttending,
        date: (result['date'] as String?) ?? event.date,
      );
      setState(() {
        _events = _events.map((e) => e.id == event.id ? updated : e).toList();
      });
      unawaited(_load());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save event (${res.statusCode})')),
      );
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
        token: widget.token,
        currentUsername: widget.currentUser.username,
        currentUserAvatar: widget.currentUser.avatarUrl,
        onAttend: () => _attend(event),
        onDelete: () {
          Navigator.of(context).pop();
          _deleteEvent(event);
        },
        onReport: () {
          Navigator.of(context).pop();
          _reportEvent(event);
        },
        onEdit: () {
          Navigator.of(context).pop();
          _editEvent(event);
        },
        attendEnabled: widget.attendEnabled,
        isAdmin: widget.currentUser.isAdmin,
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

  DateTime? _dateOnly(EventItem e) {
    if (e.date.isEmpty) return null;
    final d = DateTime.tryParse(e.date);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  Widget _buildSection(bool isLight, String title, List<EventItem> events) {
    final hasImages = events.any((e) => e.imageUrl.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
          child: Text(
            title,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: hasImages ? 430.0 : 280.0,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 0, 0, 0),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              final eff = _effective(event);
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width - 80,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _EventCard(
                      event: eff,
                      currentUsername: widget.currentUser.username,
                      onAttend: () => _attend(event),
                      onDelete: () => _deleteEvent(event),
                      onReport: () => _reportEvent(event),
                      onEdit: () => _editEvent(event),
                      onTap: () => _showEventDetail(eff),
                      attendEnabled: widget.attendEnabled,
                      isAdmin: widget.currentUser.isAdmin,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final visible = _tab == 0 ? _filteredOfficial : _community;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : const Color(0xff0f0f10),
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
          if (widget.attendEnabled)
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
          if (_isOffline) _EventsOfflineBanner(isLight: isLight),
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
                : () {
                    final now = DateTime.now();
                    final today    = DateTime(now.year, now.month, now.day);
                    final tomorrow = today.add(const Duration(days: 1));
                    final in7Days  = today.add(const Duration(days: 7));
                    final cutoff   = today.subtract(const Duration(days: 7));

                    final liveToday = visible.where((e) {
                      final d = _dateOnly(e); return d != null && d == today;
                    }).toList();
                    final upcoming = visible.where((e) {
                      final d = _dateOnly(e);
                      return d != null && !d.isBefore(tomorrow) && !d.isAfter(in7Days);
                    }).toList();
                    final other = visible.where((e) {
                      final d = _dateOnly(e); return d != null && d.isAfter(in7Days);
                    }).toList();
                    final attended = visible.where((e) {
                      final d = _dateOnly(e);
                      return d != null && d.isBefore(today) && !d.isBefore(cutoff) && _effective(e).isAttending;
                    }).toList();
                    final completed = visible.where((e) {
                      final d = _dateOnly(e);
                      return d != null && d.isBefore(today) && !d.isBefore(cutoff) && !_effective(e).isAttending;
                    }).toList();

                    if (liveToday.isEmpty && upcoming.isEmpty && other.isEmpty &&
                        attended.isEmpty && completed.isEmpty) {
                      return Center(
                        child: Text(
                          'No events yet.',
                          style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xff9c9c9c)),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        if (liveToday.isNotEmpty)  _buildSection(isLight, 'Live Today',        liveToday),
                        if (upcoming.isNotEmpty)   _buildSection(isLight, 'Upcoming Events',   upcoming),
                        if (other.isNotEmpty)      _buildSection(isLight, 'Other Events',      other),
                        if (attended.isNotEmpty)   _buildSection(isLight, 'Already Attended',  attended),
                        if (completed.isNotEmpty)  _buildSection(isLight, 'Completed Events',  completed),
                      ],
                    );
                  }(),
          ),
        ],
      ),
    );
  }
}

class _EventsOfflineBanner extends StatelessWidget {
  const _EventsOfflineBanner({required this.isLight});
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: isLight ? const Color(0xfff5f5f5) : const Color(0xff1a1a1a),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 13,
              color: isLight ? const Color(0xff888888) : const Color(0xff666666)),
          const SizedBox(width: 6),
          Text(
            'No internet connection',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isLight ? const Color(0xff888888) : const Color(0xff666666),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openUrl(String raw) async {
  var url = raw.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

String _formatEventDate(String date) {
  final d = DateTime.tryParse(date);
  if (d == null) return date;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final datePart = '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  if (d.hour != 0 || d.minute != 0) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final m = d.minute.toString().padLeft(2, '0');
    final amPm = d.hour >= 12 ? 'PM' : 'AM';
    return '$datePart at $h:$m $amPm';
  }
  return datePart;
}

String _formatTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  final amPm = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$m $amPm';
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
      category: json['category']?.toString() ?? json['eventCategory']?.toString() ?? json['event_category']?.toString() ?? '',
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
      date: json['date']?.toString() ?? json['eventDate']?.toString() ?? json['event_date']?.toString() ?? json['scheduledAt']?.toString() ?? '',
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.currentUsername,
    required this.onAttend,
    required this.onDelete,
    required this.onReport,
    required this.onEdit,
    required this.onTap,
    this.attendEnabled = true,
    this.isAdmin = false,
  });

  final EventItem event;
  final String currentUsername;
  final VoidCallback onAttend;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onEdit;
  final VoidCallback onTap;
  final bool attendEnabled;
  final bool isAdmin;

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
                    event.location.isEmpty ? event.city : _locationDisplay(event.location),
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
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white,
                      ),
                      constraints: const BoxConstraints(),
                      onSelected: (value) async {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                        if (value == 'report') onReport();
                      },
                      itemBuilder: (ctx) {
                        final isLt = Theme.of(ctx).brightness == Brightness.light;
                        return [
                          if (event.creator == currentUsername || isAdmin) ...[
                            PopupMenuItem(
                              value: 'edit',
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                              child: Text(
                                'Edit event',
                                style: TextStyle(color: isLt ? Colors.black : Colors.white),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                              child: Text(
                                'Delete event',
                                style: TextStyle(color: Color(0xfff66c6c)),
                              ),
                            ),
                          ],
                          const PopupMenuItem(
                            value: 'report',
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                            child: Text('Report event'),
                          ),
                        ];
                      },
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
                              : () => _openUrl(event.ticketsUrl),
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
                              onPressed: attendEnabled ? onAttend : null,
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
                              onPressed: attendEnabled ? onAttend : null,
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

class _PlaceSuggestion {
  const _PlaceSuggestion({
    required this.label,
    required this.sublabel,
    required this.stored,
    required this.lat,
    required this.lon,
  });
  final String label;
  final String sublabel;
  final String stored;
  final double lat;
  final double lon;
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
  final _location = TextEditingController();
  final _ticketsUrl = TextEditingController();
  final _locationFocus = FocusNode();
  bool _official = false;
  bool _tickets = false;
  String _category = _kEventCategories[1];
  String _imageUrl = '';
  bool _showPhotoError = false;
  bool _showTicketsUrlError = false;
  bool _showLocationError = false;
  bool _showTitleError = false;
  bool _showDescError = false;
  DateTime? _date;
  TimeOfDay? _time;
  bool _showDateError = false;
  bool _showTimeError = false;

  List<_PlaceSuggestion> _suggestions = [];
  bool _loadingSuggestions = false;
  Timer? _debounce;
  double? _selectedLat;
  double? _selectedLon;

  @override
  void initState() {
    super.initState();
    _locationFocus.addListener(() {
      if (!_locationFocus.hasFocus && mounted) {
        setState(() { _suggestions = []; _loadingSuggestions = false; });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _desc.dispose();
    _location.dispose();
    _ticketsUrl.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  void _onLocationChanged(String value) {
    _selectedLat = null;
    _selectedLon = null;
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() { _suggestions = []; _loadingSuggestions = false; });
      return;
    }
    setState(() => _loadingSuggestions = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _fetchSuggestions(q));
  }

  Future<void> _fetchSuggestions(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '5',
        'addressdetails': '1',
        'countrycodes': 'gr',
      });
      final res = await http.get(uri, headers: {'User-Agent': 'NeatApp/1.0'});
      if (!mounted) return;
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body) as List<dynamic>;
        final items = raw.whereType<Map<String, dynamic>>().map((j) {
          final name = j['name']?.toString() ?? '';
          final display = j['display_name']?.toString() ?? '';
          final label = name.isNotEmpty ? name : display.split(',').first.trim();
          final parts = display.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          final stored = parts.take(3).join(', ');
          final lat = double.tryParse(j['lat']?.toString() ?? '') ?? 0;
          final lon = double.tryParse(j['lon']?.toString() ?? '') ?? 0;
          return _PlaceSuggestion(
            label: label, sublabel: display,
            stored: stored.isNotEmpty ? stored : label,
            lat: lat, lon: lon,
          );
        }).toList();
        if (mounted) setState(() { _suggestions = items; _loadingSuggestions = false; });
      } else {
        if (mounted) setState(() { _suggestions = []; _loadingSuggestions = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _suggestions = []; _loadingSuggestions = false; });
    }
  }

  void _selectSuggestion(_PlaceSuggestion s) {
    _location.text = s.stored;
    _location.selection = TextSelection.collapsed(offset: s.stored.length);
    _selectedLat = s.lat;
    _selectedLon = s.lon;
    _locationFocus.unfocus();
    setState(() { _suggestions = []; _loadingSuggestions = false; });
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
                    if (_title.text.trim().isEmpty) {
                      setState(() => _showTitleError = true);
                      return;
                    }
                    if (_desc.text.trim().isEmpty) {
                      setState(() => _showDescError = true);
                      return;
                    }
                    if (_date == null) {
                      setState(() => _showDateError = true);
                      return;
                    }
                    if (_time == null) {
                      setState(() => _showTimeError = true);
                      return;
                    }
                    if (_official && _imageUrl.isEmpty) {
                      setState(() => _showPhotoError = true);
                      return;
                    }
                    if (_official && _location.text.trim().isEmpty) {
                      setState(() => _showLocationError = true);
                      return;
                    }
                    if (_official && _tickets && _ticketsUrl.text.trim().isEmpty) {
                      setState(() => _showTicketsUrlError = true);
                      return;
                    }
                    Navigator.of(context).pop({
                      'title': _title.text.trim(),
                      'description': _desc.text.trim(),
                      'eventType': _official ? 'official' : 'community',
                      'hasTickets': _tickets,
                      'date': _date!.toIso8601String().substring(0, 10),
                      if (_official) 'category': _category,
                      if (_official && _location.text.trim().isNotEmpty)
                        'location': (_selectedLat != null && _selectedLon != null)
                            ? '$_selectedLat,$_selectedLon|${_location.text.trim()}'
                            : _location.text.trim(),
                      if (_official && _tickets) 'ticketsUrl': _ticketsUrl.text.trim(),
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
              decoration: _dec('Title', isLight, error: _showTitleError),
              onChanged: (_) { if (_showTitleError) setState(() => _showTitleError = false); },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              style: TextStyle(color: isLight ? Colors.black : Colors.white),
              maxLines: 4,
              maxLength: 500,
              decoration: _dec('Description', isLight, error: _showDescError),
              onChanged: (_) { if (_showDescError) setState(() => _showDescError = false); },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CompactToggle(
                    label: 'Official event',
                    value: _official,
                    onChanged: (v) => setState(() {
                      _official = v;
                      if (!v) _tickets = false;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactToggle(
                    label: 'Has tickets',
                    value: _tickets,
                    enabled: _official,
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
            if (_official) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _location,
                focusNode: _locationFocus,
                onChanged: (v) {
                  if (_showLocationError && v.trim().isNotEmpty) setState(() => _showLocationError = false);
                  _onLocationChanged(v);
                },
                style: TextStyle(color: isLight ? Colors.black : Colors.white),
                decoration: _dec('Venue / Address (required)', isLight, error: _showLocationError),
              ),
              if (_loadingSuggestions) ...[
                const SizedBox(height: 6),
                const Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ] else if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : const Color(0xff1e1e1e),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (int i = 0; i < _suggestions.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: isLight ? const Color(0xffe8e8e8) : const Color(0xff2a2a2a),
                          ),
                        InkWell(
                          onTap: () => _selectSuggestion(_suggestions[i]),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 15, color: Color(0xff8f8f8f)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _suggestions[i].label,
                                        style: TextStyle(
                                          color: isLight ? Colors.black : Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (_suggestions[i].sublabel != _suggestions[i].label)
                                        Text(
                                          _suggestions[i].sublabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_tickets) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _ticketsUrl,
                  style: TextStyle(color: isLight ? Colors.black : Colors.white),
                  keyboardType: TextInputType.url,
                  onChanged: (_) { if (_showTicketsUrlError) setState(() => _showTicketsUrlError = false); },
                  decoration: _dec('Tickets website URL (required)', isLight, error: _showTicketsUrlError),
                ),
              ],
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
            GestureDetector(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time ?? TimeOfDay.now(),
                );
                if (picked != null) setState(() { _time = picked; _showTimeError = false; });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xff1a1a1b),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _showTimeError
                        ? const Color(0xfff66c6c)
                        : (isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 16,
                        color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      _time == null ? 'Choose time' : _formatTime(_time!),
                      style: TextStyle(
                        color: _time == null
                            ? (isLight ? const Color(0xff616161) : const Color(0xff8f8f8f))
                            : (isLight ? Colors.black : Colors.white),
                      ),
                    ),
                    if (_showTimeError) ...[
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
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 1.25,
                      child: _EventMedia(url: _imageUrl),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _imageUrl = ''),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
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

  InputDecoration _dec(String hint, bool isLight, {bool error = false}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xff8f8f8f)),
        filled: true,
        fillColor: isLight ? Colors.white : const Color(0xff1a1a1b),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: error ? const Color(0xfff66c6c) : (isLight ? const Color(0xffd9dee6) : Colors.transparent),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: error ? const Color(0xfff66c6c) : (isLight ? const Color(0xffd9dee6) : Colors.transparent),
          ),
        ),
      );
}

class _EditEventSheet extends StatefulWidget {
  const _EditEventSheet({required this.event, required this.picker});

  final EventItem event;
  final ImagePicker picker;

  @override
  State<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends State<_EditEventSheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _location;
  late final TextEditingController _ticketsUrl;
  late bool _official;
  late bool _tickets;
  late String _category;
  late String _imageUrl;
  bool _imageChanged = false;
  DateTime? _date;
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e.title);
    _desc = TextEditingController(text: e.description);
    _location = TextEditingController(text: _locationDisplay(e.location));
    _ticketsUrl = TextEditingController(text: e.ticketsUrl);
    _official = e.eventType == 'official';
    _tickets = e.hasTickets;
    _category = (_kEventCategories.contains(e.category) && e.category.isNotEmpty)
        ? e.category
        : _kEventCategories[1];
    _imageUrl = e.imageUrl;
    if (e.date.isNotEmpty) {
      final d = DateTime.tryParse(e.date);
      if (d != null) {
        _date = DateTime(d.year, d.month, d.day);
        if (d.hour != 0 || d.minute != 0) {
          _time = TimeOfDay(hour: d.hour, minute: d.minute);
        }
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _location.dispose();
    _ticketsUrl.dispose();
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
      _imageChanged = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16, 0, 16,
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
                  'Edit event',
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    if (_desc.text.trim().isEmpty) return;
                    if (_date == null) return;
                    Navigator.of(context).pop({
                      'description': _desc.text.trim(),
                      'date': _date!.toIso8601String().substring(0, 10),
                      if (_imageChanged) 'imageUrl': _imageUrl,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Title — read-only
            TextField(
              controller: _title,
              enabled: false,
              style: TextStyle(color: isLight ? Colors.black : Colors.white),
              decoration: _dec('Title', isLight),
            ),
            const SizedBox(height: 10),
            // Description — editable
            TextField(
              controller: _desc,
              style: TextStyle(color: isLight ? Colors.black : Colors.white),
              maxLines: 4,
              maxLength: 500,
              decoration: _dec('Description', isLight),
            ),
            const SizedBox(height: 10),
            // Toggles — read-only
            Opacity(
              opacity: 0.45,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Expanded(
                      child: _CompactToggle(
                        label: 'Official event',
                        value: _official,
                        onChanged: (_) {},
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CompactToggle(
                        label: 'Has tickets',
                        value: _tickets,
                        onChanged: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_official) ...[
              const SizedBox(height: 10),
              // Category — read-only
              Opacity(
                opacity: 0.45,
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                            return AnimatedContainer(
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
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Location — read-only
              TextField(
                controller: _location,
                enabled: false,
                style: TextStyle(color: isLight ? Colors.black : Colors.white),
                decoration: _dec('Venue / Address', isLight),
              ),
              if (_tickets) ...[
                const SizedBox(height: 10),
                // Tickets URL — read-only
                TextField(
                  controller: _ticketsUrl,
                  enabled: false,
                  style: TextStyle(color: isLight ? Colors.black : Colors.white),
                  keyboardType: TextInputType.url,
                  decoration: _dec('Tickets website URL', isLight),
                ),
              ],
            ],
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xff1a1a1b),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time ?? TimeOfDay.now(),
                );
                if (picked != null) setState(() => _time = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xff1a1a1b),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 16,
                        color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      _time == null ? 'Choose time (optional)' : _formatTime(_time!),
                      style: TextStyle(
                        color: _time == null
                            ? (isLight ? const Color(0xff616161) : const Color(0xff8f8f8f))
                            : (isLight ? Colors.black : Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_imageUrl.isNotEmpty)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 1.25,
                      child: _EventMedia(url: _imageUrl),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _imageUrl = '';
                        _imageChanged = true;
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                _ComposerAction(
                  icon: Icons.image_outlined,
                  onTap: _pickImage,
                ),
                const Spacer(),
                Text(
                  _imageUrl.isNotEmpty ? 'Tap photo icon to replace' : 'Photos make events feel real',
                  style: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xff8f8f8f), fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, bool isLight, {bool error = false}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isLight ? const Color(0xff616161) : const Color(0xff8f8f8f)),
        filled: true,
        fillColor: isLight ? Colors.white : const Color(0xff1a1a1b),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: error ? const Color(0xfff66c6c) : (isLight ? const Color(0xffd9dee6) : Colors.transparent),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: error ? const Color(0xfff66c6c) : (isLight ? const Color(0xffd9dee6) : Colors.transparent),
          ),
        ),
      );
}

class _CompactToggle extends StatelessWidget {
  const _CompactToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.38,
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
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: imageCacheManager,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
    );
  }
}

class _EventDetailSheet extends StatefulWidget {
  const _EventDetailSheet({
    required this.event,
    required this.token,
    required this.currentUsername,
    required this.currentUserAvatar,
    required this.onAttend,
    required this.onDelete,
    required this.onReport,
    required this.onEdit,
    this.attendEnabled = true,
    this.isAdmin = false,
  });

  final EventItem event;
  final String token;
  final String currentUsername;
  final String currentUserAvatar;
  final VoidCallback onAttend;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onEdit;
  final bool attendEnabled;
  final bool isAdmin;

  @override
  State<_EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<_EventDetailSheet> {
  late bool _isAttending = widget.event.isAttending;
  late int _attendees = widget.event.attendees;

  List<FeedComment> _comments = [];
  bool _loadingComments = true;
  final _liked = <int, bool>{};
  final _likes = <int, int>{};
  FeedComment? _replyingTo;
  String _imageUrl = '';
  bool _sending = false;
  bool _picking = false;
  bool _showInputBar = false;
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _commentSectionKey = GlobalKey();
  final _scrollViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadComments();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final commentBox = _commentSectionKey.currentContext?.findRenderObject() as RenderBox?;
    final scrollBox = _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (commentBox == null || scrollBox == null) return;
    final commentY = commentBox.localToGlobal(Offset.zero).dy;
    final scrollBottom = scrollBox.localToGlobal(Offset.zero).dy + scrollBox.size.height;
    final show = commentY < scrollBottom;
    if (show != _showInputBar) setState(() => _showInputBar = show);
  }

  ImageProvider? _avatarImage(String url) {
    if (url.isEmpty) return null;
    if (url.startsWith('data:')) {
      final bytes = decodeAvatarUrl(url);
      return bytes != null ? MemoryImage(bytes) : null;
    }
    String resolved = url;
    if (url.startsWith('/')) {
      resolved = kIsWeb ? '$webBaseUrl$url' : '$apiBaseUrl$url';
    } else if (kIsWeb && url.startsWith('http://')) {
      final uri = Uri.tryParse(url);
      if (uri != null) resolved = '$webBaseUrl${uri.path}';
    }
    return CachedNetworkImageProvider(resolved);
  }

  void _seedMaps(List<FeedComment> list) {
    for (final c in list) {
      _liked[c.id] = c.liked;
      _likes[c.id] = c.likes;
      _seedMaps(c.replies);
    }
  }

  List<FeedComment> _buildTree(List<FeedComment> flat) {
    if (flat.any((c) => c.replies.isNotEmpty)) {
      return flat.where((c) => c.parentId == null).toList();
    }
    final map = {for (final c in flat) c.id: c};
    final roots = <FeedComment>[];
    for (final c in flat) {
      if (c.parentId != null && map.containsKey(c.parentId)) {
        map[c.parentId!]!.replies.add(c);
      } else {
        roots.add(c);
      }
    }
    return roots;
  }

  Future<void> _loadComments() async {
    try {
      final res = await http.get(
        eventCommentsEndpoint(widget.event.id),
        headers: authGetHeaders(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final rawList = body is List
            ? body.whereType<Map<String, dynamic>>().toList()
            : ((body['comments'] ?? body['results']) as List? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();
        final flat = rawList.map(FeedComment.fromJson).toList();
        final comments = _buildTree(flat);
        setState(() { _comments = comments; _loadingComments = false; });
        _seedMaps(comments);
      } else {
        setState(() => _loadingComments = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _pickImage() async {
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final mime = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      setState(() => _imageUrl = 'data:image/$mime;base64,${base64Encode(bytes)}');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    final text = _commentCtrl.text.trim();
    if ((text.isEmpty && _imageUrl.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await http.post(
        eventCommentsEndpoint(widget.event.id),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({
          'text': text,
          if (_imageUrl.isNotEmpty) 'imageUrl': _imageUrl,
          if (_replyingTo != null) 'parentId': _replyingTo!.id,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        _commentCtrl.clear();
        setState(() { _replyingTo = null; _imageUrl = ''; });
        await _loadComments();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(FeedComment comment) async {
    final was = _liked[comment.id] ?? comment.liked;
    final next = (_likes[comment.id] ?? comment.likes) + (was ? -1 : 1);
    setState(() {
      _liked[comment.id] = !was;
      _likes[comment.id] = next;
    });
    try {
      await http.post(
        commentLikeEndpoint(comment.id),
        headers: authJsonHeaders(widget.token),
        body: jsonEncode({'liked': !was}),
      );
      comment.liked = !was;
      comment.likes = next;
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked[comment.id] = was;
          _likes[comment.id] = (_likes[comment.id] ?? comment.likes) + (was ? 1 : -1);
        });
      }
    }
  }

  Widget _tile(FeedComment c, bool isReply, bool isLight) {
    final avatar = _avatarImage(c.avatarUrl);
    final imgBytes = c.imageUrl.isNotEmpty ? decodeAvatarUrl(c.imageUrl) : null;
    final isLiked = _liked[c.id] ?? c.liked;
    final likeCount = _likes[c.id] ?? c.likes;
    DateTime? created;
    try { created = DateTime.parse(c.createdAt); } catch (_) {}
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 52 : 16, 10, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 14 : 18,
            backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
            foregroundImage: avatar,
            child: avatar == null
                ? Text(
                    initialFor(c.author),
                    style: TextStyle(
                      color: isLight ? const Color(0xff444444) : Colors.white,
                      fontSize: isReply ? 9 : 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(children: [
                    TextSpan(
                      text: '${c.author} ',
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: isReply ? 13.5 : 15,
                        height: 1.5,
                      ),
                    ),
                    if (c.text.isNotEmpty)
                      TextSpan(
                        text: c.text,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w400,
                          fontSize: isReply ? 13.5 : 15,
                          height: 1.5,
                        ),
                      ),
                  ]),
                ),
                if (imgBytes != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(imgBytes, width: double.infinity, fit: BoxFit.cover),
                  ),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  if (created != null)
                    Text(
                      _timeAgo(created),
                      style: TextStyle(
                        fontSize: 12,
                        color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                      ),
                    ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = c),
                    child: Text(
                      'Reply',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _toggleLike(c),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 18,
                  color: isLiked
                      ? const Color(0xfff66c6c)
                      : (isLight ? const Color(0xffa0a0a0) : const Color(0xff6a6a6a)),
                ),
                if (likeCount > 0)
                  Text(
                    '$likeCount',
                    style: TextStyle(
                      fontSize: 10,
                      color: isLight ? const Color(0xff8b95a3) : const Color(0xff7a7a7a),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final event = widget.event;
    final official = event.eventType == 'official';
    final dividerColor = isLight ? const Color(0xfff0f0f0) : const Color(0xff1e1e1e);
    final mutedColor = isLight ? const Color(0xff8f8f8f) : const Color(0xff6f6f6f);
    final userAvatar = _avatarImage(widget.currentUserAvatar);
    final previewBytes = _imageUrl.isNotEmpty ? decodeAvatarUrl(_imageUrl) : null;

    return Column(
      children: [
        // ── drag handle ──────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a),
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // ── scrollable content ───────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            key: _scrollViewKey,
            controller: _scrollCtrl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // hero image
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

                // event details
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
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
                        if (official && event.location.isNotEmpty)
                          _MapCard(location: event.location)
                        else
                          _DetailRow(
                            icon: Icons.location_on_outlined,
                            text: event.location.isNotEmpty ? _locationDisplay(event.location) : event.city,
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
                      if (event.ticketsUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _openUrl(event.ticketsUrl),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.link_rounded, size: 14, color: Color(0xff0095f6)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  event.ticketsUrl,
                                  style: const TextStyle(
                                    color: Color(0xff0095f6),
                                    fontSize: 12,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Color(0xff0095f6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            '$_attendees people attending',
                            style: TextStyle(color: mutedColor, fontSize: 13),
                          ),
                          const Spacer(),
                          if (widget.attendEnabled)
                          GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                backgroundColor: isLight ? Colors.white : const Color(0xff111111),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                ),
                                builder: (_) => _FriendsAttendingSheet(
                                  eventId: event.id,
                                  token: widget.token,
                                  currentUsername: widget.currentUsername,
                                  isLight: isLight,
                                ),
                              );
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_outline_rounded, size: 14,
                                    color: isLight ? Colors.black : Colors.white),
                                const SizedBox(width: 5),
                                Text(
                                  'See if friends are going',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.black : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                      // attend / tickets buttons
                      Row(
                        children: [
                          if (official && event.hasTickets) ...[
                            Expanded(
                              child: TextButton(
                                onPressed: event.ticketsUrl.isEmpty ? null : () => _openUrl(event.ticketsUrl),
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
                                    onPressed: widget.attendEnabled ? () {
                                      setState(() { _isAttending = false; _attendees--; });
                                      widget.onAttend();
                                    } : null,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: isLight ? Colors.black : Colors.white,
                                      side: BorderSide(color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: const Text("Don't Attend"),
                                  )
                                : FilledButton(
                                    onPressed: widget.attendEnabled ? () {
                                      setState(() { _isAttending = true; _attendees++; });
                                      widget.onAttend();
                                    } : null,
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
                      // edit / delete / report
                      if (event.creator == widget.currentUsername || widget.isAdmin) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: widget.onEdit,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isLight ? Colors.black : Colors.white,
                              side: BorderSide(color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Edit event'),
                          ),
                        ),
                        const SizedBox(height: 6),
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
                      ] else ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: widget.onReport,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xfff66c6c),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Report event'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── comments section ─────────────────────────────────
                Divider(key: _commentSectionKey, color: dividerColor, thickness: 1, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    _loadingComments
                        ? 'Comments'
                        : 'Comments${_comments.isEmpty ? '' : ' (${_comments.length})'}',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_loadingComments)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: Text(
                      widget.attendEnabled ? 'No comments yet.\nBe the first!' : 'No comments yet.',
                      style: TextStyle(
                        color: isLight ? const Color(0xff8b95a3) : const Color(0xffb3b3b3),
                        height: 1.6,
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final c in _comments) ...[
                        _tile(c, false, isLight),
                        for (final r in c.replies)
                          _tile(r, true, isLight),
                        const SizedBox(height: 4),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
              ],
            ),
          ),
        ),

        // ── comment input bar ────────────────────────────────────────
        if (_showInputBar && widget.attendEnabled)
        Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(height: 1, color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a)),
              if (previewBytes != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SizedBox(
                    height: 72,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(previewBytes, height: 72, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4, right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _imageUrl = ''),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_replyingTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.reply_rounded, size: 16,
                          color: isLight ? const Color(0xff536471) : const Color(0xff71767b)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to @${_replyingTo!.author}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isLight ? const Color(0xff536471) : const Color(0xff71767b),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _replyingTo = null),
                        child: Icon(Icons.close, size: 16,
                            color: isLight ? const Color(0xff536471) : const Color(0xff71767b)),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
                      foregroundImage: userAvatar,
                      child: userAvatar == null
                          ? Text(
                              initialFor(widget.currentUsername),
                              style: TextStyle(
                                color: isLight ? const Color(0xff444444) : Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _picking ? null : _pickImage,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.photo_outlined,
                          size: 24,
                          color: _picking
                              ? (isLight ? const Color(0xffd0d0d0) : const Color(0xff444444))
                              : (isLight ? const Color(0xff536471) : const Color(0xff71767b)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _commentCtrl,
                        builder: (context, value, _) {
                          final canSend = value.text.trim().isNotEmpty || _imageUrl.isNotEmpty;
                          return TextField(
                            controller: _commentCtrl,
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 14,
                            ),
                            cursorColor: isLight ? Colors.black : Colors.white,
                            decoration: InputDecoration(
                              hintText: _replyingTo != null
                                  ? 'Reply to @${_replyingTo!.author}...'
                                  : 'Add a comment...',
                              hintStyle: TextStyle(
                                color: isLight ? const Color(0xff8b95a3) : const Color(0xff9a9a9a),
                                fontSize: 14,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              filled: true,
                              fillColor: isLight ? const Color(0xfff0f2f5) : const Color(0xff1e1e1e),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: canSend
                                  ? _sending
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: SizedBox(
                                            width: 18, height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        )
                                      : IconButton(
                                          onPressed: _send,
                                          icon: const Icon(
                                            Icons.send_rounded,
                                            color: Color(0xff4f8cff),
                                            size: 20,
                                          ),
                                        )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

class _MapCard extends StatelessWidget {
  const _MapCard({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final display = _locationDisplay(location);
    // If we have exact coordinates, use them for more accurate deep links.
    double? lat, lon;
    final pipe = location.indexOf('|');
    if (pipe > 0) {
      final coords = location.substring(0, pipe).split(',');
      if (coords.length == 2) {
        lat = double.tryParse(coords[0]);
        lon = double.tryParse(coords[1]);
      }
    }
    final encoded = Uri.encodeComponent(display);
    final appleMapsUri = (lat != null && lon != null)
        ? Uri.parse('https://maps.apple.com/?ll=$lat,$lon&q=$encoded')
        : Uri.parse('https://maps.apple.com/?q=$encoded');
    final googleMapsUri = (lat != null && lon != null)
        ? Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 160,
            child: IgnorePointer(
              child: _EventMapView(location: location, isLight: isLight),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 14, color: Color(0xff8f8f8f)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                display,
                style: const TextStyle(color: Color(0xff8f8f8f), fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MapButton(
                label: 'Apple Maps',
                icon: Icons.map_outlined,
                onTap: () => launchUrl(appleMapsUri, mode: LaunchMode.externalApplication),
                isLight: isLight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MapButton(
                label: 'Google Maps',
                icon: Icons.map_outlined,
                onTap: () => launchUrl(googleMapsUri, mode: LaunchMode.externalApplication),
                isLight: isLight,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EventMapView extends StatefulWidget {
  const _EventMapView({required this.location, required this.isLight});
  final String location;
  final bool isLight;

  @override
  State<_EventMapView> createState() => _EventMapViewState();
}

class _EventMapViewState extends State<_EventMapView> {
  WebViewController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _init();
  }

  Future<void> _init() async {
    if (_eventMapkitJs == null) {
      try {
        _eventMapkitJs = await rootBundle.loadString('assets/mapkit.js');
      } catch (_) {}
    }
    if (!mounted) return;
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.isLight ? const Color(0xfff0f2f5) : const Color(0xff1a1a1b))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) => debugPrint('[eventmap] ${e.description}'),
      ))
      ..loadHtmlString(
        _buildMapHtml(widget.location, inlineJs: _eventMapkitJs),
        baseUrl: 'https://netnest.net',
      );
    if (mounted) setState(() => _ctrl = ctrl);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || _ctrl == null) {
      return ColoredBox(
        color: widget.isLight ? const Color(0xfff0f2f5) : const Color(0xff1a1a1b),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return WebViewWidget(controller: _ctrl!);
  }
}

String _buildMapHtml(String address, {String? inlineJs}) {
  // Parse "lat,lon|Display Name" format written by _selectSuggestion.
  double? lat, lon;
  String displayAddr = address;
  final pipe = address.indexOf('|');
  if (pipe > 0) {
    displayAddr = address.substring(pipe + 1);
    final coords = address.substring(0, pipe).split(',');
    if (coords.length == 2) {
      lat = double.tryParse(coords[0]);
      lon = double.tryParse(coords[1]);
    }
  }

  final String pinJs;
  if (lat != null && lon != null) {
    pinJs = '''
      var coord = new mapkit.Coordinate($lat, $lon);
      var pin = new mapkit.MarkerAnnotation(coord, { color: '#ff3040', calloutEnabled: false });
      map.addAnnotation(pin);
      map.setRegionAnimated(new mapkit.CoordinateRegion(coord, new mapkit.CoordinateSpan(0.008, 0.008)));''';
  } else {
    final escaped = displayAddr.replaceAll("'", "\\'");
    pinJs = '''
      var geocoder = new mapkit.Geocoder({ language: 'en-GB' });
      geocoder.lookup('$escaped', function(err, data) {
        if (err || !data.results || !data.results.length) return;
        var coord = data.results[0].coordinate;
        var pin = new mapkit.MarkerAnnotation(coord, { color: '#ff3040', calloutEnabled: false });
        map.addAnnotation(pin);
        map.setRegionAnimated(new mapkit.CoordinateRegion(coord, new mapkit.CoordinateSpan(0.008, 0.008)));
      });''';
  }

  final buf = StringBuffer();
  buf.write('''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="initial-scale=1.0,width=device-width">
  <style>
    html,body,#map{margin:0;padding:0;width:100%;height:100%;overflow:hidden;}
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    function initMap() {
      mapkit.init({ authorizationCallback: function(done) { done('$_kMapToken'); } });
      var map = new mapkit.Map('map', {
        colorScheme: mapkit.Map.ColorSchemes.Dark,
        showsCompass: mapkit.FeatureVisibility.Hidden,
        showsScale: mapkit.FeatureVisibility.Hidden,
        showsMapTypeControl: false,
        showsZoomControl: false,
        showsUserLocationControl: false,
      });
      map.isScrollEnabled = false;
      map.isZoomEnabled = false;
      map.isRotationEnabled = false;
      map.isPitchEnabled = false;
      try { map.pointOfInterestFilter = mapkit.PointOfInterestFilter.excludingAllCategories; } catch(_) {}
      $pinJs
    }
  </script>
''');

  if (inlineJs != null) {
    buf.write('<script>$inlineJs</script>\n<script>initMap();</script>\n');
  } else {
    buf.write('''<script>
(function(){
  var s=document.createElement('script');
  s.src='$_kMapKitCdn';
  s.onload=initMap;
  document.head.appendChild(s);
})();
</script>
''');
  }

  buf.write('</body></html>');
  return buf.toString();
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.label, required this.icon, required this.onTap, required this.isLight});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isLight ? const Color(0xfff0f2f5) : const Color(0xff1e1e1e),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: isLight ? Colors.black : Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Friends Attending Sheet ───────────────────────────────────────────────────

class _FriendsAttendingSheet extends StatefulWidget {
  const _FriendsAttendingSheet({
    required this.eventId,
    required this.token,
    required this.currentUsername,
    required this.isLight,
  });
  final int eventId;
  final String token;
  final String currentUsername;
  final bool isLight;

  @override
  State<_FriendsAttendingSheet> createState() => _FriendsAttendingSheetState();
}

class _FriendsAttendingSheetState extends State<_FriendsAttendingSheet> {
  List<UserProfile>? _friends;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        http.get(eventAttendeesEndpoint(widget.eventId),
            headers: authGetHeaders(widget.token)),
        http.get(followingEndpoint(widget.currentUsername),
            headers: authGetHeaders(widget.token)),
        http.get(followersEndpoint(widget.currentUsername),
            headers: authGetHeaders(widget.token)),
      ]);

      if (!mounted) return;

      final attendeesRes = results[0];
      final followingRes = results[1];
      final followersRes = results[2];

      Set<String> attendeeNames = {};
      if (attendeesRes.statusCode == 200) {
        final body = jsonDecode(attendeesRes.body);
        final list = body is List
            ? body
            : ((body['attendees'] ?? body['users'] ?? body['results'] ?? const []) as List);
        attendeeNames = list
            .whereType<Map<String, dynamic>>()
            .map((j) => j['username']?.toString() ?? '')
            .where((u) => u.isNotEmpty)
            .toSet();
      }

      List<UserProfile> parseUsers(http.Response res, List<String> keys) {
        if (res.statusCode != 200) return [];
        final body = jsonDecode(res.body);
        final list = body is List ? body : (() {
          for (final k in keys) {
            if (body[k] != null) return body[k] as List;
          }
          return const [];
        })();
        return list.whereType<Map<String, dynamic>>().map(UserProfile.fromJson).toList();
      }

      final following = parseUsers(followingRes, ['following', 'users', 'results']);
      final followers = parseUsers(followersRes, ['followers', 'users', 'results']);

      // Mutual only: a "friend" is someone you follow who also follows you back
      final followerNames = followers.map((u) => u.username).toSet();
      final mutualFriends = following
          .where((u) => u.username != widget.currentUsername && followerNames.contains(u.username))
          .toList();

      final friends = mutualFriends
          .where((u) => attendeeNames.contains(u.username))
          .toList();

      if (mounted) setState(() => _friends = friends);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Uint8List? _decodeAvatar(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    try { return base64Decode(url.substring(comma + 1)); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLight;
    final textColor = isLight ? Colors.black : Colors.white;

    Widget body;
    if (_error) {
      body = const Center(child: Text('Could not load.', style: TextStyle(color: Color(0xffb3b3b3))));
    } else if (_friends == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_friends!.isEmpty) {
      body = const Center(
        child: Text('None of your friends are going yet.',
            style: TextStyle(color: Color(0xffb3b3b3))),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        itemCount: _friends!.length,
        itemBuilder: (_, i) {
          final u = _friends![i];
          final bytes = _decodeAvatar(u.avatarUrl);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: isLight ? const Color(0xffe6e9ef) : const Color(0xff2a2a2a),
              foregroundImage: bytes != null ? MemoryImage(bytes) : null,
              child: bytes == null
                  ? Text(
                      u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                      style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
                    )
                  : null,
            ),
            title: Text(
              u.fullName.isNotEmpty ? u.fullName : u.username,
              style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
            ),
            subtitle: u.fullName.isNotEmpty
                ? Text('@${u.username}', style: const TextStyle(color: Color(0xffb3b3b3), fontSize: 13))
                : null,
          );
        },
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: isLight ? const Color(0xffd9dee6) : const Color(0xff2a2a2a),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Friends going',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textColor),
          ),
        ),
        Divider(height: 1, color: isLight ? const Color(0xffe0e0e0) : const Color(0xff242424)),
        Expanded(child: body),
      ],
    );
  }
}
