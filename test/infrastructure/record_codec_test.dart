import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

/// A run's record is written on one machine and read back on another, weeks later, by a client that
/// was not running when it happened. Anything the codec loses on the way through is a fact about a
/// failed deployment that nobody can get back.
void main() {
  const RecordCodec codec = RecordCodec();
  final DateTime at = DateTime.utc(2026, 8, 7, 12, 30, 15, 250, 375);
  const StepName step = StepName('installs_the_thing');

  /// Encodes, decodes, and insists the two are the same object written down.
  T reread<T extends RunEvent>(RunEvent event) {
    final RunEvent back = codec.eventFrom(asObject(jsonDecode(jsonEncode(codec.event(event)))));

    expect(back, isA<T>());
    expect(codec.event(back), codec.event(event), reason: 'nothing may be lost or added');
    expect(back.sequence, event.sequence);
    expect(back.at, event.at);
    expect(back.at.isUtc, isTrue, reason: 'the record is in UTC and stays in UTC');
    expect(back.step, event.step);
    return back as T;
  }

  group('every kind of event survives the round trip', () {
    test('run-started', () {
      final RunStarted back = reread<RunStarted>(
        RunStarted(sequence: 0, at: at, program: const ProgramName('deploy'), mode: 'dry'),
      );
      expect(back.program, const ProgramName('deploy'));
      expect(back.mode, 'dry');
    });

    test('predicate-evaluated', () {
      final PredicateEvaluated back = reread<PredicateEvaluated>(
        PredicateEvaluated(
          sequence: 1,
          at: at,
          predicate: const PredicateName('cluster_is_up'),
          held: false,
          because: 'nothing answers on 6443',
        ),
      );
      expect(back.predicate, const PredicateName('cluster_is_up'));
      expect(back.held, isFalse);
      expect(back.because, 'nothing answers on 6443');
    });

    test('step-started', () {
      final StepStarted back = reread<StepStarted>(
        StepStarted(sequence: 2, at: at, step: step, source: 'lib/src/steps/thing.dart:14'),
      );
      expect(back.source, 'lib/src/steps/thing.dart:14');
    });

    test('command-started, with and without a working directory', () {
      final CommandStarted back = reread<CommandStarted>(
        CommandStarted(
          sequence: 3,
          at: at,
          step: step,
          argv: const <String>['a-tool', 'upgrade', r'--set=value=$literal'],
          workingDirectory: '/opt/somewhere',
        ),
      );
      expect(back.argv, <String>['a-tool', 'upgrade', r'--set=value=$literal']);
      expect(back.workingDirectory, '/opt/somewhere');

      final CommandStarted bare = reread<CommandStarted>(
        CommandStarted(sequence: 4, at: at, step: step, argv: const <String>['true']),
      );
      expect(bare.workingDirectory, isNull);
    });

    test('output, from either stream', () {
      final Output back = reread<Output>(
        Output(
          sequence: 5,
          at: at,
          step: step,
          stream: OutputStream.stderr,
          text: 'Error: release not found',
        ),
      );
      expect(back.stream, OutputStream.stderr);
      expect(back.text, 'Error: release not found');

      expect(
        reread<Output>(
          Output(sequence: 6, at: at, step: step, stream: OutputStream.stdout, text: 'ok'),
        ).stream,
        OutputStream.stdout,
      );
    });

    test('command-finished, to the microsecond', () {
      final CommandFinished back = reread<CommandFinished>(
        CommandFinished(
          sequence: 7,
          at: at,
          step: step,
          exitCode: 137,
          elapsed: const Duration(minutes: 2, seconds: 3, microseconds: 7),
        ),
      );
      expect(back.exitCode, 137);
      expect(back.elapsed, const Duration(minutes: 2, seconds: 3, microseconds: 7));
    });

    test('file-written', () {
      final FileWritten back = reread<FileWritten>(
        FileWritten(
          sequence: 8,
          at: at,
          step: step,
          path: '/etc/thing.yaml',
          bytes: 91,
          created: true,
        ),
      );
      expect(back.path, '/etc/thing.yaml');
      expect(back.bytes, 91);
      expect(back.created, isTrue);
    });

    test('request-sent', () {
      final RequestSent back = reread<RequestSent>(
        RequestSent(
          sequence: 9,
          at: at,
          step: step,
          method: 'PUT',
          url: 'https://secrets.example.com/v1/secret',
          status: 204,
        ),
      );
      expect(back.method, 'PUT');
      expect(back.url, 'https://secrets.example.com/v1/secret');
      expect(back.status, 204);
    });

    test('a log line, at every level', () {
      final Log back = reread<Log>(
        Log(sequence: 10, at: at, step: step, level: LogLevel.warn, message: 'two of three'),
      );
      expect(back.level, LogLevel.warn);
      expect(back.message, 'two of three');

      expect(
        reread<Log>(
          Log(sequence: 11, at: at, step: step, level: LogLevel.info, message: 'here'),
        ).level,
        LogLevel.info,
      );
    });

    test('step-finished', () {
      final StepFinished back = reread<StepFinished>(
        StepFinished(
          sequence: 12,
          at: at,
          step: step,
          verdict: const Failed('the postcondition does not hold', policy: OnFailure.exit),
          elapsed: const Duration(milliseconds: 1500),
        ),
      );
      expect(back.verdict, isA<Failed>());
      expect((back.verdict as Failed).reason, 'the postcondition does not hold');
      expect(back.elapsed, const Duration(milliseconds: 1500));
    });

    test('run-finished', () {
      final RunFinished back = reread<RunFinished>(
        RunFinished(
          sequence: 13,
          at: at,
          exitCode: 2,
          issues: const <String>['issuer: no certificate', 'dns: not delegated'],
        ),
      );
      expect(back.exitCode, 2);
      expect(back.issues, <String>['issuer: no certificate', 'dns: not delegated']);
      expect(back.step, isNull, reason: 'the end of a run belongs to no step');
    });

    test('planned, carrying each kind of plan', () {
      final Planned diff = reread<Planned>(
        Planned(
          sequence: 14,
          at: at,
          step: step,
          plan: const DiffPlan('/etc/thing.yaml', before: 'a: 1', after: 'a: 2'),
        ),
      );
      expect((diff.plan as DiffPlan).after, 'a: 2');

      final Planned argv = reread<Planned>(
        Planned(
          sequence: 15,
          at: at,
          step: step,
          plan: const ArgvPlan(
            <String>['a-tool', 'apply'],
            workingDirectory: '/opt',
            serverVerified: true,
          ),
        ),
      );
      expect((argv.plan as ArgvPlan).serverVerified, isTrue);
      expect((argv.plan as ArgvPlan).workingDirectory, '/opt');
    });
  });

  group('the sealed families under an event', () {
    test('every verdict survives', () {
      Verdict back(Verdict verdict) => codec.verdictFrom(codec.verdict(verdict));

      expect(back(const Succeeded()), isA<Succeeded>());
      expect((back(const Skipped('cluster_is_up')) as Skipped).predicate, 'cluster_is_up');
      expect((back(const Failed('slow', policy: OnFailure.continueRun)) as Failed).reason, 'slow');
      expect(
        (back(const Failed('no issuer', policy: OnFailure.continueRun)) as Failed).reason,
        'no issuer',
      );
      expect((back(const Failed('gone', policy: OnFailure.exit)) as Failed).reason, 'gone');
    });

    test('every plan survives', () {
      StepPlan back(StepPlan plan) => codec.stepPlanFrom(codec.stepPlan(plan));

      expect((back(const ArgvPlan(<String>['a', 'b'])) as ArgvPlan).argv, <String>['a', 'b']);
      expect((back(const ArgvPlan(<String>['a'])) as ArgvPlan).workingDirectory, isNull);
      expect((back(const DiffPlan('/p', before: '', after: 'x')) as DiffPlan).creates, isTrue);
      expect(
        (back(const RequestPlan('POST', 'https://h/x', body: '{}')) as RequestPlan).body,
        '{}',
      );
      expect((back(const RequestPlan('GET', 'https://h/x')) as RequestPlan).body, isNull);
      expect((back(const NothingPlan('already there')) as NothingPlan).because, 'already there');
    });

    test('every check result survives', () {
      CheckResult back(CheckResult result) => codec.checkResultFrom(codec.checkResult(result));

      expect(back(const Ready()), isA<Ready>());
      expect((back(const Satisfied('it is there')) as Satisfied).because, 'it is there');
      expect((back(const Blocked('no disk')) as Blocked).reason, 'no disk');
    });
  });

  group('the run header', () {
    RunRecord open() => RunRecord(
      id: const RunId('20260807T123015Z-1'),
      program: const ProgramName('deploy-cluster'),
      mode: Mode.dry,
      argv: const <String>['ansiwise', 'deploy-something', '--mode', 'dry'],
      start: at,
      stage: const Stage('prod'),
      role: const Role('master'),
      fqdn: const Fqdn('m1.example.com'),
      commit: 'abc1234',
      fingerprint: 'a-digest',
    );

    test('a run that is still going has no end and no exit code', () {
      final RunRecord back = codec.runFrom(codec.run(open()));

      expect(back.id, const RunId('20260807T123015Z-1'));
      expect(back.program, const ProgramName('deploy-cluster'));
      expect(back.mode, Mode.dry);
      expect(back.argv, <String>['ansiwise', 'deploy-something', '--mode', 'dry']);
      expect(back.start, at);
      expect(back.start.isUtc, isTrue);
      expect(back.stage, const Stage('prod'));
      expect(back.role, const Role('master'));
      expect(back.fqdn, const Fqdn('m1.example.com'));
      expect(back.commit, 'abc1234');
      expect(back.fingerprint, 'a-digest');
      expect(back.end, isNull);
      expect(back.exitCode, isNull);
      expect(back.finished, isFalse);
    });

    test('a run that ended carries its steps back with it', () {
      final RunRecord closed = open().closed(
        end: at.add(const Duration(minutes: 4)),
        exitCode: 2,
        steps: <StepRecord>[
          StepRecord(
            step: step,
            source: 'lib/src/steps/thing.dart:14',
            start: at,
            end: at.add(const Duration(seconds: 30)),
            verdict: const Failed('no certificate', policy: OnFailure.continueRun),
            standing: StepStanding.proven,
            firstEvent: 3,
            lastEvent: 11,
            plan: const DiffPlan('/etc/thing.yaml', before: '', after: 'a: 1'),
            issues: const <String>['no certificate'],
          ),
        ],
        issues: const <String>['installs_the_thing: no certificate'],
      );

      final RunRecord back = codec.runFrom(asObject(jsonDecode(jsonEncode(codec.run(closed)))));

      expect(back.end, at.add(const Duration(minutes: 4)));
      expect(back.exitCode, 2);
      expect(back.finished, isTrue);
      expect(back.clean, isFalse);
      expect(back.issues, <String>['installs_the_thing: no certificate']);

      final StepRecord row = back.steps.single;
      expect(row.step, step);
      expect(row.source, 'lib/src/steps/thing.dart:14');
      expect(row.start, at);
      expect(row.elapsed, const Duration(seconds: 30));
      expect(row.firstEvent, 3);
      expect(row.lastEvent, 11);
      expect(row.verdict, isA<Failed>());
      expect(row.plan, isA<DiffPlan>());
      expect((row.plan as DiffPlan?)?.after, 'a: 1');
      expect(row.issues, <String>['no certificate']);
    });

    test('what a run went without survives being written down', () {
      // A waiver that did not round-trip would be gone from every record read back off disk, and
      // what is left then reads exactly like a run that was gated normally. Written even when the
      // list is empty, so an absent key cannot be mistaken for "this run waived nothing".
      final RunRecord waived = RunRecord(
        id: const RunId('20260807T123015Z-2'),
        program: const ProgramName('deploy-cluster'),
        mode: Mode.run,
        argv: const <String>['ansiwise', 'deploy-cluster', '--mode', 'run'],
        start: at,
        stage: const Stage('prod'),
        role: const Role('master'),
        fqdn: const Fqdn('m1.example.com'),
        commit: 'abc1234',
        fingerprint: 'a-digest',
        waived: const <Mode>[Mode.dry],
      );

      final RunRecord back = codec.runFrom(asObject(jsonDecode(jsonEncode(codec.run(waived)))));

      expect(back.waived, <Mode>[Mode.dry]);
      expect(
        back.fullyProven,
        isFalse,
        reason: 'a run with no proof behind it never reports as one',
      );
      expect(codec.runFrom(codec.run(open())).waived, isEmpty);
    });

    test('how much of each row was measured survives being written down', () {
      // The standing is what the three numbers are counted from. Lost in the codec, every run read
      // back off disk would count as fully measured — the one answer that must never be wrong by
      // default.
      final RunRecord closed = open().closed(
        end: at,
        exitCode: 0,
        steps: <StepRecord>[
          for (final StepStanding standing in StepStanding.values)
            StepRecord(
              step: step,
              source: 'x:1',
              start: at,
              end: at,
              verdict: const Succeeded(),
              standing: standing,
              firstEvent: 0,
              lastEvent: 1,
            ),
        ],
        issues: const <String>[],
      );

      final RunRecord back = codec.runFrom(asObject(jsonDecode(jsonEncode(codec.run(closed)))));

      expect(back.steps.map((StepRecord each) => each.standing), StepStanding.values);
      expect(back.standings, const Standings(proven: 1, declared: 1, skipped: 1));
    });

    test('a step with no plan reads back with no plan', () {
      final RunRecord closed = open().closed(
        end: at,
        exitCode: 0,
        steps: <StepRecord>[
          StepRecord(
            step: step,
            source: 'x:1',
            start: at,
            end: at,
            verdict: const Succeeded(),
            standing: StepStanding.proven,
            firstEvent: 0,
            lastEvent: 1,
          ),
        ],
        issues: const <String>[],
      );

      expect(codec.runFrom(codec.run(closed)).steps.single.plan, isNull);
    });
  });

  group('what is not a record', () {
    test('an event kind nobody wrote is refused', () {
      expect(
        () => codec.eventFrom(<String, Object?>{
          'kind': 'invented',
          'sequence': 0,
          'at': at.toIso8601String(),
        }),
        throwsFormatException,
      );
    });

    test('a field of the wrong shape is refused rather than guessed at', () {
      expect(
        () => codec.eventFrom(<String, Object?>{
          'kind': 'run-started',
          'sequence': 'not a number',
          'at': at.toIso8601String(),
          'program': 'deploy',
          'mode': 'dry',
        }),
        throwsFormatException,
      );
    });
  });
}

/// Reads a decoded JSON value as an object, without a cast the analyzer has to be argued with.
Map<String, Object?> asObject(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw StateError('that is not a JSON object');
}
