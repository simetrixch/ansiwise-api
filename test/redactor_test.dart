import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// The record is exported and pasted into messages when something has gone wrong.
///
/// That is only safe if a secret cannot be in it, and the only way to be sure is to have one place
/// everything passes through. These tests are about that place.
void main() {
  group('what is hidden', () {
    test('a secret is replaced wherever it appears, and the line stays', () {
      final Redactor redactor = Redactor(<String>['hunter2-and-then-some']);
      expect(
        redactor.hide('login failed for user with hunter2-and-then-some at 10:04'),
        'login failed for user with [redacted] at 10:04',
      );
    });

    test('the marker is fixed, so the length of the value is not readable either', () {
      final Redactor redactor = Redactor(<String>['short-secret', 'a-much-longer-secret-value']);
      expect(redactor.hide('short-secret'), Redactor.marker);
      expect(redactor.hide('a-much-longer-secret-value'), Redactor.marker);
    });

    test('a secret containing another is replaced whole', () {
      final Redactor redactor = Redactor(<String>['abcdefgh', 'abcdefghijklmnop']);
      expect(redactor.hide('value=abcdefghijklmnop'), 'value=[redacted]');
    });

    test('a value too short to be worth hiding is left alone', () {
      final Redactor redactor = Redactor(<String>['abc']);
      expect(
        redactor.hide('abc appears in ordinary words like abcess'),
        'abc appears in ordinary words like abcess',
        reason: 'a page of markers is worse than the risk it removes',
      );
    });

    test('a header that names a credential is hidden by its name', () {
      final Redactor redactor = Redactor(const <String>[]);
      expect(
        redactor.hideHeaders(<String, String>{
          'Authorization': 'Basic abcdef',
          'X-Api-Key': 'whatever',
          'Accept': 'application/json',
        }),
        <String, String>{
          'Authorization': Redactor.marker,
          'X-Api-Key': Redactor.marker,
          'Accept': 'application/json',
        },
      );
    });
  });

  group('what reaches the record', () {
    test("a command's output is redacted on the way in", () async {
      final Harness h = Harness(secrets: <String>['s3cret-value-here']);
      h.shell.answers('cat /etc/app/credentials', 'value: s3cret-value-here\nlease: 1h');

      final RecordingShell shell = RecordingShell(
        h.shell,
        recorder: h.recorder,
        redactor: h.redactor,
        step: const StepName('reads'),
      );
      await shell.run(const Command('cat', <String>['/etc/app/credentials']));

      expect(h.recorder.output, <String>['value: [redacted]', 'lease: 1h']);
      expect(
        h.recorder.output.join('\n'),
        isNot(contains('s3cret-value-here')),
        reason: 'nothing in the record may carry the value',
      );
    });

    test('a log line a step writes is redacted too', () async {
      final Harness h = Harness(secrets: <String>['s3cret-value-here']);
      RecordingLogger(
        recorder: h.recorder,
        redactor: h.redactor,
        step: const StepName('reads'),
      ).info('using s3cret-value-here to authenticate');

      expect(h.recorder.logLines.single, 'using [redacted] to authenticate');
    });

    test('a command is recorded unjoined, so a value can never become syntax', () async {
      final Harness h = Harness();
      final RecordingShell shell = RecordingShell(
        h.shell,
        recorder: h.recorder,
        redactor: h.redactor,
        step: const StepName('writes'),
      );
      await shell.run(const Command('sh', <String>[r'a value with $signs and "quotes"']));

      expect(h.recorder.only<CommandStarted>().single.argv, <String>[
        'sh',
        r'a value with $signs and "quotes"',
      ]);
    });
  });
}
