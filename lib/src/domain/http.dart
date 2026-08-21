import 'package:meta/meta.dart';

/// Sending a request is one of the three ways this framework reaches outside.
///
/// A step never opens a connection itself, for the same reasons it never starts a process: a dry
/// run must be able to refuse what would change something at the other end, and every request must
/// reach the record whether or not anyone thought to write it down.
abstract interface class Http {
  /// Sends [request] and returns the answer.
  ///
  /// Does not throw on a status the caller did not want — the status is data. It throws when the
  /// request could not be sent at all, or when the mode forbids it.
  Future<HttpAnswer> send(HttpRequest request);
}

/// A request, described rather than sent.
@immutable
final class HttpRequest {
  /// Describes a request.
  const HttpRequest(
    this.method,
    this.url, {
    this.headers = const <String, String>{},
    this.body,
    this.timeout,
    this.socketPath,
    bool? observes,
  }) : observes = observes ?? (method == 'GET' || method == 'HEAD' || method == 'OPTIONS');

  /// The request method, upper case.
  final String method;

  /// Where the request goes.
  ///
  /// Parsed regardless of [socketPath]: the path and the `Host` header a server sees come from
  /// here even when the connection itself does not go over the network.
  final String url;

  /// The headers to send. A credential in here is redacted before the request reaches the record.
  final Map<String, String> headers;

  /// The body, or null when there is none.
  final String? body;

  /// How long to wait before giving up.
  final Duration? timeout;

  /// The filesystem path of a unix domain socket to connect to instead of the network, or null to
  /// resolve [url] and connect over the network exactly as before.
  ///
  /// Nothing else about the request changes: [url] still parses and still supplies the request path
  /// and the `Host` header, and this only moves where the bytes go.
  final String? socketPath;

  /// Whether this request only reads.
  ///
  /// Derived from the method, because that is what a method means: `GET`, `HEAD` and `OPTIONS`
  /// read, everything else may change something at the other end. A caller can say otherwise for
  /// the case where an interface does not follow its own methods.
  ///
  /// The method is compared upper case and not folded, so a request written `get` is treated as
  /// changing something. That is the safe direction: it is refused by a dry run rather than let
  /// through by one.
  final bool observes;
}

/// What came back.
@immutable
final class HttpAnswer {
  /// Records an answer.
  const HttpAnswer({
    required this.status,
    required this.body,
    required this.headers,
    required this.elapsed,
  });

  /// The status code.
  final int status;

  /// The body as text.
  final String body;

  /// The headers that came back.
  final Map<String, String> headers;

  /// How long it took.
  final Duration elapsed;

  /// Whether the status is in the two hundreds.
  bool get ok => status >= 200 && status < 300;
}
