import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// A verdict comes from a checked postcondition, never from an exit code.
///
/// The shell this replaces had eleven phases that reported success over a real failure, every one of
/// them by trusting what a command returned: a wait whose bar was "more than zero pods running", a
/// version reader that printed `not installed` and returned zero, an upgrade that fell back to an
/// unpinned install. These tests are the general answer to all eleven.
void main() {
  ResolvedProgram programWith(
    Step Function(Arguments) step,
    OnFailure onFailure, {
    String name = 'the_step',
  }) => ProgramResolver(
    registryOf(steps: <String, (String, Step Function(Arguments))>{name: ('x:1', step)}),
  ).resolve(programOf('p', <(String, OnFailure, List<String>)>[(name, onFailure, <String>[])]));

  test('a step whose command succeeds but whose postcondition does not holds fails', () async {
    final Harness h = Harness();
    final RunRecord record = await h.runner.run(
      program: programWith((Arguments a) => const ClaimsSuccessWithout(), OnFailure.die),
      mode: Mode.run,
      header: h.header(),
    );

    expect(h.shell.ran, <String>['true'], reason: 'the command ran and returned zero');
    expect(record.steps.single.verdict, isA<Died>());
    expect((record.steps.single.verdict as Died).reason, contains('still not in the state'));
    expect(record.exitCode, 1);
  });

  test('a step whose postcondition holds afterwards succeeds', () async {
    final Harness h = Harness();
    final RunRecord record = await h.runner.run(
      program: programWith(
        (Arguments a) => WritesAFile(path: '/etc/thing', content: 'x'),
        OnFailure.die,
      ),
      mode: Mode.run,
      header: h.header(),
    );

    expect(record.steps.single.verdict, isA<Succeeded>());
    expect(h.files.contents['/etc/thing'], 'x');
    expect(record.exitCode, 0);
  });

  group('what a failure costs is what the program declared', () {
    test('die ends the run', () async {
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: programWith((Arguments a) => const Blocks('no disk'), OnFailure.die),
        mode: Mode.run,
        header: h.header(),
      );
      expect(record.steps.single.verdict, isA<Died>());
      expect(record.exitCode, 1);
      expect(record.issues, isEmpty);
    });

    test('issue carries the reason to the end of the run', () async {
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: programWith((Arguments a) => const Blocks('no disk'), OnFailure.issue),
        mode: Mode.run,
        header: h.header(),
      );
      expect(record.steps.single.verdict, isA<Issued>());
      expect(record.issues, <String>['the_step: no disk']);
      expect(record.exitCode, 2, reason: 'a run that finished with problems must not look clean');
      expect(record.clean, isFalse);
    });

    test('warn is recorded and costs nothing', () async {
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: programWith((Arguments a) => const Blocks('no disk'), OnFailure.warn),
        mode: Mode.run,
        header: h.header(),
      );
      expect(record.steps.single.verdict, isA<Warned>());
      expect(record.issues, isEmpty);
      expect(record.exitCode, 0);
    });
  });

  test('a run that dies does not reach the steps after it', () async {
    final Harness h = Harness();
    final ResolvedProgram program =
        ProgramResolver(
          registryOf(
            steps: <String, (String, Step Function(Arguments))>{
              'blocks': ('x:1', (Arguments a) => const Blocks('no disk')),
              'writes': ('x:2', (Arguments a) => WritesAFile(path: '/late', content: 'x')),
            },
          ),
        ).resolve(
          programOf('p', <(String, OnFailure, List<String>)>[
            ('blocks', OnFailure.die, <String>[]),
            ('writes', OnFailure.die, <String>[]),
          ]),
        );

    final RunRecord record = await h.runner.run(
      program: program,
      mode: Mode.run,
      header: h.header(),
    );

    expect(record.steps, hasLength(1));
    expect(h.files.contents.containsKey('/late'), isFalse);
  });
}
