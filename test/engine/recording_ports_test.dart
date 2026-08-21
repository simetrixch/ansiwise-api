import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

/// The record is the only place a reader learns a request went over a unix socket rather than the
/// network — [HttpRequest.socketPath] is not part of [HttpRequest.url], so nothing about the answer
/// itself says which transport carried it. If [RecordingHttp] dropped the field on its way into
/// [RequestSent], the record would look exactly like a network request that happened to answer the
/// same way, and there would be no way to tell the two apart afterwards.
void main() {
  group('RecordingHttp', () {
    test('carries the socket path from the request into the record', () async {
      final MemoryRecorder recorder = MemoryRecorder(FakeClock());
      const StepName step = StepName('talks_to_the_daemon');
      final RecordingHttp http = RecordingHttp(
        FakeHttp(),
        recorder: recorder,
        redactor: Redactor.none,
        step: step,
      );

      await http.send(
        const HttpRequest(
          'GET',
          'http://on-a-socket.invalid/health',
          socketPath: '/run/daemon.sock',
        ),
      );

      final RequestSent sent = recorder.only<RequestSent>().single;
      expect(sent.socketPath, '/run/daemon.sock');
      expect(sent.url, 'http://on-a-socket.invalid/health');
    });

    test('leaves the field null for a request that went over the network', () async {
      final MemoryRecorder recorder = MemoryRecorder(FakeClock());
      const StepName step = StepName('talks_over_the_network');
      final RecordingHttp http = RecordingHttp(
        FakeHttp(),
        recorder: recorder,
        redactor: Redactor.none,
        step: step,
      );

      await http.send(const HttpRequest('GET', 'https://example.com/health'));

      final RequestSent sent = recorder.only<RequestSent>().single;
      expect(sent.socketPath, isNull);
    });
  });
}
