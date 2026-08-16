import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// The recorder is the one place a secret could reach a world-readable file, and the one place a
/// killed run's events either are or are not.
void main() {
  late Directory temp;
  late RunDirectory directory;
  final FakeClock clock = FakeClock();
  const RunId id = RunId('20260807T120000Z-1');
  const StepName step = StepName('writes_a_thing');

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ansiwise-recorder-');
    directory = RunDirectory(temp.path);
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows can hold a handle open for a moment after a file is closed.
    }
  });

  Future<FileRecorder> open({Iterable<String> secrets = const <String>[]}) =>
      FileRecorder.open(id: id, directory: directory, clock: clock, redactor: Redactor(secrets));

  List<String> linesOf() =>
      File(directory.events(id)).readAsLinesSync().where((String l) => l.isNotEmpty).toList();

  Map<String, Object?> lineOf(int index) => jsonDecode(linesOf()[index]) as Map<String, Object?>;

  RunRecord header() => RunRecord(
    id: id,
    program: const ProgramName('deploy-something'),
    mode: Mode.dry,
    argv: const <String>['ansiwise', 'deploy-something'],
    start: clock.now(),
    stage: const Stage('prod'),
    role: const Role('master'),
    fqdn: const Fqdn('m1.example.com'),
    commit: 'abc1234',
    fingerprint: 'a-digest',
  );

  group('what lands in events.jsonl', () {
    test('one event is one line, and the sequence numbers are dense', () async {
      final FileRecorder recorder = await open();

      expect(recorder.nextSequence, 0);
      recorder.record(
        (int s, DateTime at) =>
            RunStarted(sequence: s, at: at, program: const ProgramName('p'), mode: 'dry'),
      );
      recorder.record(
        (int s, DateTime at) =>
            Log(sequence: s, at: at, step: step, level: LogLevel.info, message: 'first'),
      );
      recorder.record(
        (int s, DateTime at) =>
            Log(sequence: s, at: at, step: step, level: LogLevel.info, message: 'second'),
      );
      expect(recorder.nextSequence, 3);
      await recorder.close();

      expect(linesOf(), hasLength(3));
      expect(<Object?>[for (int i = 0; i < 3; i++) lineOf(i)['sequence']], <int>[0, 1, 2]);
      expect(lineOf(1)['message'], 'first');
      expect(lineOf(2)['message'], 'second');
    });

    test('a line is on disk before record returns, so a kill keeps it', () async {
      final FileRecorder recorder = await open();
      recorder.record(
        (int s, DateTime at) =>
            Log(sequence: s, at: at, step: step, level: LogLevel.info, message: 'written'),
      );

      // Read without closing the recorder: nothing of ours is holding the line back.
      expect(linesOf(), hasLength(1));
      await recorder.close();
    });

    test('closing twice is not an error, and recording after it is', () async {
      final FileRecorder recorder = await open();
      await recorder.close();
      await recorder.close();

      expect(
        () => recorder.record(
          (int s, DateTime at) =>
              Log(sequence: s, at: at, step: step, level: LogLevel.info, message: 'too late'),
        ),
        throwsStateError,
      );
    });
  });

  group('what the recorder takes out on the way in', () {
    const String secret = 's3cret-value-here';

    test("a plan's diff is the whole content of a file, and no port has redacted it", () async {
      final FileRecorder recorder = await open(secrets: const <String>[secret]);
      recorder.record(
        (int s, DateTime at) => Planned(
          sequence: s,
          at: at,
          step: step,
          plan: const DiffPlan('/etc/thing', before: '', after: 'token: $secret'),
        ),
      );
      await recorder.close();

      final String written = File(directory.events(id)).readAsStringSync();
      expect(written, isNot(contains(secret)));
      expect(written, contains('token: ${Redactor.marker}'));
    });

    test('a verdict quotes an exception message, which can quote a command line', () async {
      final FileRecorder recorder = await open(secrets: const <String>[secret]);
      recorder.record(
        (int s, DateTime at) => StepFinished(
          sequence: s,
          at: at,
          step: step,
          verdict: const Failed('login $secret returned 1', policy: OnFailure.exit),
          elapsed: Duration.zero,
        ),
      );
      await recorder.close();

      expect(File(directory.events(id)).readAsStringSync(), isNot(contains(secret)));
    });

    test('what a predicate found, and the issues repeated at the end of the run', () async {
      final FileRecorder recorder = await open(secrets: const <String>[secret]);
      recorder.record(
        (int s, DateTime at) => PredicateEvaluated(
          sequence: s,
          at: at,
          predicate: const PredicateName('is_logged_in'),
          held: true,
          because: 'the token is $secret',
        ),
      );
      recorder.record(
        (int s, DateTime at) =>
            RunFinished(sequence: s, at: at, exitCode: 2, issues: <String>['x: $secret']),
      );
      await recorder.close();

      expect(File(directory.events(id)).readAsStringSync(), isNot(contains(secret)));
    });
  });

  group('run.json', () {
    test('it is written when the run begins and rewritten when it ends', () async {
      final FileRecorder recorder = await open();
      await recorder.save(header());

      final Map<String, Object?> begun =
          jsonDecode(File(directory.header(id)).readAsStringSync()) as Map<String, Object?>;
      expect(begun['id'], id.value);
      expect(begun.containsKey('end'), isFalse);
      expect(begun.containsKey('exit_code'), isFalse);

      await recorder.save(
        header().closed(
          end: clock.now(),
          exitCode: 0,
          steps: <StepRecord>[
            StepRecord(
              step: step,
              source: 'x:1',
              start: clock.now(),
              end: clock.now(),
              verdict: const Succeeded(),
              standing: StepStanding.proven,
              firstEvent: 0,
              lastEvent: 2,
            ),
          ],
          issues: const <String>[],
        ),
      );
      await recorder.close();

      final Map<String, Object?> ended =
          jsonDecode(File(directory.header(id)).readAsStringSync()) as Map<String, Object?>;
      expect(ended['exit_code'], 0);
      expect(ended['end'], isNotNull);
      expect(ended['steps'], hasLength(1));
      expect(
        File(directory.pendingHeader(id)).existsSync(),
        isFalse,
        reason: 'the header is renamed into place, not left beside itself',
      );
    });

    test('a credential typed on the command line is not left in the header', () async {
      const String secret = 'ghp-averylongcredential';
      final FileRecorder recorder = await open(secrets: const <String>[secret]);

      final RunRecord given = header();
      await recorder.save(
        RunRecord(
          id: given.id,
          program: given.program,
          mode: given.mode,
          argv: <String>['ansiwise', 'onboard-thing', '--pat', secret],
          start: given.start,
          stage: given.stage,
          role: given.role,
          fqdn: given.fqdn,
          commit: given.commit,
          fingerprint: given.fingerprint,
        ),
      );
      await recorder.close();

      expect(File(directory.header(id)).readAsStringSync(), isNot(contains(secret)));
    });
  });

  test('the record is world-readable, which is what redaction is paying for', () async {
    final FileRecorder recorder = await open();
    await recorder.save(header());
    recorder.record(
      (int s, DateTime at) =>
          Log(sequence: s, at: at, step: step, level: LogLevel.info, message: 'x'),
    );
    await recorder.close();

    expect(Directory(directory.of(id)).statSync().mode & 511, 493, reason: '0755');
    expect(File(directory.events(id)).statSync().mode & 511, 420, reason: '0644');
    expect(File(directory.header(id)).statSync().mode & 511, 420, reason: '0644');
  }, skip: Platform.isWindows ? 'Windows has no POSIX permission bits' : null);
}
