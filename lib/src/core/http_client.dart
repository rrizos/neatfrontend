// Drop-in replacement for `package:http/http.dart`'s top-level get/post/
// patch/delete functions. Those each spin up a brand-new Client, make one
// request, and close it — meaning every call pays a fresh TCP+TLS handshake.
// That was cheap over plain HTTP; now that the backend is HTTPS (see
// pinned_http.dart), the handshake is real cost, and this app makes ~100
// such calls across its screens. Reusing one Client lets keep-alive actually
// reuse connections instead of re-handshaking every time.
//
// Import this instead of 'package:http/http.dart' wherever the app used the
// top-level functions — everything else (Response, Client, MultipartRequest,
// ...) is re-exported unchanged.
import 'dart:convert';

import 'package:http/http.dart' as http;

export 'package:http/http.dart' hide get, post, patch, delete, put, head;

final http.Client sharedHttpClient = http.Client();

Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
    sharedHttpClient.get(url, headers: headers);

Future<http.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) =>
    sharedHttpClient.post(url, headers: headers, body: body, encoding: encoding);

Future<http.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) =>
    sharedHttpClient.patch(url, headers: headers, body: body, encoding: encoding);

Future<http.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) =>
    sharedHttpClient.delete(url, headers: headers, body: body, encoding: encoding);

Future<http.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) =>
    sharedHttpClient.put(url, headers: headers, body: body, encoding: encoding);

Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
    sharedHttpClient.head(url, headers: headers);
