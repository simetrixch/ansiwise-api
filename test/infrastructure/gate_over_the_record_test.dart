import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// The gate, over the record that is actually on disk.
///
/// Every other test of the gate hands it a store built in memory. This one writes real files and
/// reads them back, because the gap it exists to catch is exactly there: a run whose header never
/// reached disk answers nothing to `GET /runs`, and the gate can never find the dry run it is
/// looking for — while every in-memory test still passes.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ansiwise-gate-');
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  /// Writes one finished run, the way the command line does: a header before the first step and the
  /// closed record afterwards.
  Future<RunRecord> recordOneRun({
    required String id,
    required Mode mode,
    required String fingerprint,
    required int exitCode,
  }) async {
    final RunDirectory directory = RunDirectory(root.path);
    final FakeClock clock = FakeClock();
    final RunRecord header = RunRecord(
      id: RunId(id),
      program: const ProgramName('deploy-host'),
      mode: mode,
      argv: const <String>['ansiwise-api', 'deploy-host'],
      start: clock.now(),
      stage: const Stage('dev'),
      role: const Role('master'),
      fqdn: const Fqdn('m1.example.com'),
      commit: 'abc1234',
      fingerprint: fingerprint,
    );

    final FileRecorder recorder = await FileRecorder.open(
      id: RunId(id),
      directory: directory,
      clock: clock,
      redactor: Redactor.none,
    );
    await recorder.save(header);
    await recorder.close();
    final RunRecord closed = header.closed(
      end: clock.now(),
      exitCode: exitCode,
      steps: const <StepRecord>[],
      issues: const <String>[],
    );
    await recorder.save(closed);
    return closed;
  }

  test('a header written before the first step is on disk and readable', () async {
    await recordOneRun(id: 'r1', mode: Mode.dry, fingerprint: 'f', exitCode: 0);

    final RunRecord? back = await FileRunStore(
      directory: RunDirectory(root.path),
    ).read(const RunId('r1'));

    expect(back, isNotNull);
    expect(back?.program, const ProgramName('deploy-host'));
    expect(back?.fingerprint, 'f');
  });

  test('a clean dry run on disk admits a real run', () async {
    await recordOneRun(id: 'the-dry-one', mode: Mode.dry, fingerprint: 'f', exitCode: 0);
    final Gate gate = Gate(FileRunStore(directory: RunDirectory(root.path)));

    final RunRecord? admitted = await gate.admit(
      mode: Mode.run,
      program: const ProgramName('deploy-host'),
      fingerprint: 'f',
    );

    expect(admitted?.id, const RunId('the-dry-one'));
  });

  test('a dry run of a different input does not admit it', () async {
    await recordOneRun(id: 'other-input', mode: Mode.dry, fingerprint: 'g', exitCode: 0);
    final Gate gate = Gate(FileRunStore(directory: RunDirectory(root.path)));

    await expectLater(
      gate.admit(mode: Mode.run, program: const ProgramName('deploy-host'), fingerprint: 'f'),
      throwsA(isA<GateNotMet>()),
    );
  });

  test('a dry run that failed does not admit it', () async {
    await recordOneRun(id: 'the-failed-one', mode: Mode.dry, fingerprint: 'f', exitCode: 1);
    final Gate gate = Gate(FileRunStore(directory: RunDirectory(root.path)));

    await expectLater(
      gate.admit(mode: Mode.run, program: const ProgramName('deploy-host'), fingerprint: 'f'),
      throwsA(isA<GateNotMet>()),
    );
  });

  test('nothing on disk admits nothing', () async {
    final Gate gate = Gate(FileRunStore(directory: RunDirectory(root.path)));
    await expectLater(
      gate.admit(mode: Mode.run, program: const ProgramName('deploy-host'), fingerprint: 'f'),
      throwsA(isA<GateNotMet>()),
    );
  });

  test('a resumed run names the run it continues, and carries the same fingerprint', () async {
    final RunRecord first = await recordOneRun(
      id: 'first',
      mode: Mode.test,
      fingerprint: 'f',
      exitCode: 1,
    );

    final RunDirectory directory = RunDirectory(root.path);
    final FakeClock clock = FakeClock();
    final FileRecorder recorder = await FileRecorder.open(
      id: const RunId('second'),
      directory: directory,
      clock: clock,
      redactor: Redactor.none,
    );
    await recorder.save(
      RunRecord(
        id: const RunId('second'),
        program: first.program,
        mode: first.mode,
        argv: first.argv,
        start: clock.now(),
        stage: first.stage,
        role: first.role,
        fqdn: first.fqdn,
        commit: first.commit,
        fingerprint: first.fingerprint,
        resumes: first.id,
      ),
    );
    await recorder.close();

    final RunRecord? back = await FileRunStore(directory: directory).read(const RunId('second'));
    expect(back?.resumes, const RunId('first'));
    expect(
      back?.fingerprint,
      first.fingerprint,
      reason: 'a run that continues another must be the same input, or it is not continuing it',
    );
  });
}
