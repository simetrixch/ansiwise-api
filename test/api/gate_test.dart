import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import '../support/example_steps.dart';
import '../support/harness.dart';
import 'doubles.dart';

/// The feature the whole rebuild exists for: three modes, each unlocking the next.
///
/// The gate is in the engine and not in a user interface, so these tests go through the API the way
/// a client would — and the same rule holds for the command line and for any other caller, because
/// all three go through this one door.
void main() {
  const String commit = 'abc1234';

  ResolvedProgram deployCluster({String path = '/etc/thing'}) =>
      ProgramResolver(
        registryOf(
          steps: <String, (String, Step Function(Arguments))>{
            'writes_a_file': (
              'deployment/lib/steps/writes_a_file.dart:12',
              (Arguments a) => WritesAFile(path: a.text('path'), content: 'the content'),
            ),
          },
          arguments: <String, List<ArgumentSpec>>{
            'writes_a_file': const <ArgumentSpec>[
              ArgumentSpec(
                name: 'path',
                kind: ArgumentKind.text,
                describes: 'the file to write',
                defaultValue: '/etc/thing',
              ),
              ArgumentSpec(
                name: 'credential',
                kind: ArgumentKind.text,
                describes: 'what it authenticates with',
                required: false,
                secret: true,
              ),
            ],
          },
        ),
      ).resolve(
        programOf(
          'deploy-cluster',
          <(String, OnFailure, List<String>)>[('writes_a_file', OnFailure.die, <String>[])],
          arguments: <String, Arguments>{
            'writes_a_file': Arguments(<String, Object>{'path': path}),
          },
        ),
      );

  ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) build(
    ResolvedProgram program,
  ) {
    final MemoryRunStore store = MemoryRunStore();
    final RecordingLauncher launcher = RecordingLauncher();
    final FixedCatalogue catalogue = FixedCatalogue(<ResolvedProgram>[program]);
    return (
      api: DeploymentApi(
        programs: ProgramsEndpoint(catalogue),
        runs: RunsEndpoint(
          store: store,
          launcher: launcher,
          catalogue: catalogue,
          gate: Gate(store),
          json: const PlainRecordJson(),
          commit: commit,
        ),
        events: EventsEndpoint(store: store, json: const PlainRecordJson()),
      ),
      store: store,
      launcher: launcher,
    );
  }

  ApiRequest post(String path, Map<String, Object?> body) =>
      ApiRequest('POST', Uri.parse(path), body: jsonEncode(body));

  group('a real run needs a clean dry run for the same input', () {
    test('without one it is refused, and nothing is started', () async {
      final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
        deployCluster(),
      );

      final ApiResponse answer = await it.api.call(
        post('/runs', <String, Object?>{'program': 'deploy-cluster', 'mode': 'run'}),
      );

      expect(answer, isA<Refused>());
      expect((answer as Refused).status, 409);
      expect(answer.reason, contains('needs a successful dry'));
      expect(it.launcher.started, isEmpty, reason: 'the run must not have been started');
    });

    test('with one it is admitted, and it says which dry run let it through', () async {
      final ResolvedProgram program = deployCluster();
      final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
        program,
      );
      it.store.runs.add(
        runRecord(
          id: 'the-dry-one',
          program: 'deploy-cluster',
          mode: Mode.dry,
          fingerprint: fingerprintOf(program: program, commit: commit),
          exitCode: 0,
        ),
      );

      final ApiResponse answer = await it.api.call(
        post('/runs', <String, Object?>{'program': 'deploy-cluster', 'mode': 'run'}),
      );

      expect(answer, isA<Answered>());
      expect((answer as Answered).status, 202);
      expect(switch (answer.payload) {
        final Map<String, Object?> body => body['admitted_by'],
        final Object other => throw StateError('answered with $other'),
      }, 'the-dry-one');
      expect(it.launcher.started, <(ProgramName, Mode)>[
        (const ProgramName('deploy-cluster'), Mode.run),
      ]);
    });

    test('a dry run of a DIFFERENT input does not admit it', () async {
      final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
        deployCluster(),
      );
      // A clean dry run of the same program, at the same commit, with one answer changed.
      it.store.runs.add(
        runRecord(
          id: 'the-other-one',
          program: 'deploy-cluster',
          mode: Mode.dry,
          fingerprint: fingerprintOf(
            program: deployCluster(path: '/etc/somewhere-else'),
            commit: commit,
          ),
          exitCode: 0,
        ),
      );

      final ApiResponse answer = await it.api.call(
        post('/runs', <String, Object?>{'program': 'deploy-cluster', 'mode': 'run'}),
      );

      expect(answer, isA<Refused>());
      expect(it.launcher.started, isEmpty);
    });

    test('a dry run that FAILED does not admit it', () async {
      final ResolvedProgram program = deployCluster();
      final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
        program,
      );
      it.store.runs.add(
        runRecord(
          id: 'the-failed-one',
          program: 'deploy-cluster',
          mode: Mode.dry,
          fingerprint: fingerprintOf(program: program, commit: commit),
          exitCode: 1,
        ),
      );

      final ApiResponse answer = await it.api.call(
        post('/runs', <String, Object?>{'program': 'deploy-cluster', 'mode': 'run'}),
      );

      expect(answer, isA<Refused>());
      expect(it.launcher.started, isEmpty);
    });
  });

  group('the first two modes are not gated', () {
    test('a test run starts with nothing before it', () async {
      final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
        deployCluster(),
      );
      final ApiResponse answer = await it.api.call(
        post('/runs', <String, Object?>{'program': 'deploy-cluster', 'mode': 'test'}),
      );
      expect(answer, isA<Answered>());
      expect(it.launcher.started.single.$2, Mode.test);
    });

    test('a dry run starts with nothing before it', () async {
      final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
        deployCluster(),
      );
      final ApiResponse answer = await it.api.call(
        post('/runs', <String, Object?>{'program': 'deploy-cluster', 'mode': 'dry'}),
      );
      expect(answer, isA<Answered>());
      expect(it.launcher.started.single.$2, Mode.dry);
    });
  });

  group('what makes two runs the same input', () {
    test('the same program at the same commit fingerprints the same', () {
      expect(
        fingerprintOf(program: deployCluster(), commit: commit),
        fingerprintOf(program: deployCluster(), commit: commit),
      );
    });

    test('a different commit is a different input', () {
      expect(
        fingerprintOf(program: deployCluster(), commit: commit),
        isNot(fingerprintOf(program: deployCluster(), commit: 'def5678')),
      );
    });
  });
}
