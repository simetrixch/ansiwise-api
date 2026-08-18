/// The SSH channel, dressed as the socket `HttpServer` expects.
///
/// `HttpServer.listenOn` takes a `ServerSocket`, and a `ServerSocket` hands out `Socket`s. Neither
/// of those has to come from the network: everything the HTTP server uses is the byte stream on one
/// side and the sink on the other, and an SSH exec channel gives exactly those as its standard
/// input and output.
///
/// So this is how a REST endpoint is served with nothing listening anywhere. There is no port and no
/// socket file; the client starts the process inside a session it already opened, and the session is
/// the connection. When it closes, no process is left.
///
/// The two classes here are the whole of that trick, and both are thin on purpose — everything
/// interesting is the real `HttpServer` above them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A `Socket` whose bytes come from one stream and go to one sink.
///
/// Nothing here talks to a network, so the address and port answers are placeholders. They exist
/// because the interface has them; the HTTP server does not read them, and a caller that did would
/// be asking the wrong object.
final class ChannelSocket extends Stream<Uint8List> implements Socket {
  /// Wraps the channel's input and output as one connection.
  ChannelSocket({required Stream<List<int>> incoming, required this.outgoing})
    : _incoming = incoming.map(Uint8List.fromList);

  final Stream<Uint8List> _incoming;

  /// Where the answer's bytes go — the channel's standard output.
  final StreamSink<List<int>> outgoing;

  @override
  Encoding encoding = utf8;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void add(List<int> data) => outgoing.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) => outgoing.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => outgoing.addStream(stream);

  @override
  Future<void> close() => outgoing.close();

  @override
  Future<void> get done => outgoing.done;

  @override
  Future<void> flush() async {
    // The channel's own sink decides when bytes leave; there is nothing held back here to push.
  }

  @override
  void write(Object? object) => add(encoding.encode('$object'));

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void destroy() {
    unawaited(outgoing.close());
  }

  @override
  bool setOption(SocketOption option, bool enabled) => false;

  @override
  Uint8List getRawOption(RawSocketOption option) => Uint8List(0);

  @override
  void setRawOption(RawSocketOption option) {}

  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;

  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;

  @override
  int get port => 0;

  @override
  int get remotePort => 0;
}

/// A `ServerSocket` that hands out one connection: the channel.
///
/// One and not many, because a session is one connection. A client that wants a second opens a
/// second session, which SSH multiplexes over the same transport — so watching four machines at
/// once is four channels, not a listening port.
final class ChannelServerSocket extends Stream<Socket> implements ServerSocket {
  /// Offers the given connection as the only one this server will ever accept.
  ChannelServerSocket(this._connection);

  final Socket _connection;

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<Socket>.value(
    _connection,
  ).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;

  @override
  int get port => 0;

  @override
  Future<ServerSocket> close() async => this;
}
