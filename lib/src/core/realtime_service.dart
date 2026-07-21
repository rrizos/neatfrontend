import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart' show apiBaseUrl;

/// A single push event from the DM WebSocket — `type` matches one of the
/// `event` names the backend's MessagingConsumer sends (message.new,
/// message.edited, message.deleted, message.reaction, conversation.new,
/// conversation.deleted, typing, read_receipt, presence, block, unblock),
/// plus the client-only synthetic `resynced` fired after every successful
/// (re)connect so screens know to force a one-off refetch.
class RealtimeEvent {
  const RealtimeEvent(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;
}

/// One WebSocket connection for the whole logged-in session, owned by
/// HomePage and handed down to the messaging screens rather than recreated
/// per screen — it needs to survive navigating in and out of conversations
/// and keep presence/typing/read-receipts flowing even while just sitting on
/// the inbox or home feed.
///
/// Native (mobile) only. The backend has no domain name — just a bare IP
/// with a self-signed cert that the mobile app already trusts via
/// certificate pinning (see pinned_http.dart) — and a browser has no
/// equivalent override for a wss:// handshake, so the web build keeps its
/// existing HTTP-polling behavior entirely untouched (see messages_page.dart
/// and home_page.dart's `if (!kIsWeb)` guards around anything that touches
/// this class).
class RealtimeService with WidgetsBindingObserver {
  RealtimeService({required this.token});

  final String token;

  static const _reconnectDelaysSeconds = [1, 2, 5, 10, 20, 30];

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _controller = StreamController<RealtimeEvent>.broadcast();
  Timer? _reconnectTimer;
  bool _authenticated = false;
  bool _disposed = false;
  int _retryAttempt = 0;

  Stream<RealtimeEvent> get events => _controller.stream;
  bool get isConnected => _authenticated;

  void start() {
    if (kIsWeb || _disposed) return;
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    unawaited(_channel?.sink.close());
    _controller.close();
  }

  /// Send a client-originated action (`typing` or `mark_read`) — a no-op
  /// while disconnected/unauthenticated, since these are ephemeral signals
  /// not worth queuing or retrying.
  void send(Map<String, dynamic> action) {
    if (!_authenticated) return;
    _sendRaw(action);
  }

  void _connect() {
    if (_disposed) return;
    _authenticated = false;
    final wsUrl = apiBaseUrl.replaceFirst(RegExp(r'^https?://'), 'wss://');
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse('$wsUrl/ws/messages/'));
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _subscription = _channel!.stream.listen(
      _onMessage,
      onDone: _onDisconnected,
      onError: (_) => _onDisconnected(),
      cancelOnError: true,
    );
    _sendRaw({'action': 'auth', 'token': token});
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final event = decoded['event']?.toString() ?? '';
    if (event.isEmpty || event == 'auth_error') return;
    if (event == 'authenticated') {
      _authenticated = true;
      _retryAttempt = 0;
      // A drop mid-conversation (backgrounding, network switch) can leave a
      // screen's local state stale for however long the reconnect took —
      // force every listener to do one fresh REST refetch on top of resuming
      // the live event stream, so nothing is silently missed.
      _controller.add(const RealtimeEvent('resynced', {}));
      return;
    }
    final payload = (decoded['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    _controller.add(RealtimeEvent(event, payload));
  }

  void _onDisconnected() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _authenticated = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final index = _retryAttempt.clamp(0, _reconnectDelaysSeconds.length - 1);
    _retryAttempt++;
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelaysSeconds[index]), _connect);
  }

  void _sendRaw(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _channel == null && !_disposed) {
      _retryAttempt = 0;
      _reconnectTimer?.cancel();
      _connect();
    }
  }
}
