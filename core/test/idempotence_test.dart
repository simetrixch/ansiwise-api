import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// A second run changes nothing.
///
/// This is what Ansible sells and rarely proves. Here it is a test per step, and a step without one
/// does not count as finished — because a program that is not idempotent is a program nobody dares
/// run twice, and every real deployment is run twice.
void main() {
  ResolvedProgram fileProgram() =>
      ProgramResolver(
        registryOf(
          steps: <String, (String, Step Function(Arguments))>{
            'writes_a_file': (
              'x:1',
              (Arguments a) => WritesAFile(path: '/etc/thing', content: 'the content'),
            ),
          },
        ),
      ).resolve(
        programOf('p', <(String, OnFailure, List<String>)>[
          ('writes_a_file', OnFailure.exit, <String>[]),
        ]),
      );

  test('the second run writes nothing and still succeeds', () async {
    final Harness first = Harness();
    await first.runner.run(program: fileProgram(), mode: Mode.run, header: first.header());
    expect(first.files.written, <String>['/etc/thing']);

    final Harness second = Harness(files: FakeFiles(first.files.contents));
    final RunRecord record = await second.runner.run(
      program: fileProgram(),
      mode: Mode.run,
      header: second.header(),
    );

    expect(second.files.written, isEmpty, reason: 'nothing may be written the second time');
    expect(record.steps.single.verdict, isA<Succeeded>());
    expect(record.exitCode, 0);
  });

  test('the second run says why there was nothing to do', () async {
    final Harness h = Harness(files: FakeFiles(<String, String>{'/etc/thing': 'the content'}));
    await h.runner.run(program: fileProgram(), mode: Mode.run, header: h.header());

    expect(
      h.recorder.logLines,
      contains('nothing to do: /etc/thing already holds what this step writes'),
    );
  });

  test('a dry run of an already-done step plans nothing at all', () async {
    final Harness h = Harness(files: FakeFiles(<String, String>{'/etc/thing': 'the content'}));
    final RunRecord record = await h.runner.run(
      program: fileProgram(),
      mode: Mode.dry,
      header: h.header(mode: Mode.dry),
    );

    switch (record.steps.single.plan) {
      case final NothingPlan plan:
        expect(plan.because, contains('already holds'));
      default:
        fail('a step with nothing to do must plan nothing');
    }
  });

  test('a command step is idempotent when its postcondition is what it checks', () async {
    final Harness h = Harness();
    ResolvedProgram program() =>
        ProgramResolver(
          registryOf(
            steps: <String, (String, Step Function(Arguments))>{
              'runs': (
                'x:1',
                (Arguments a) =>
                    RunsACommand(argv: const <String>['touch', '/marker'], leaves: '/marker'),
              ),
            },
          ),
        ).resolve(
          programOf('p', <(String, OnFailure, List<String>)>[('runs', OnFailure.exit, <String>[])]),
        );

    // The fake shell does not create files, so the postcondition is arranged the way the machine
    // would have left it. What is being tested is the check, not the command.
    await h.runner.run(program: program(), mode: Mode.run, header: h.header());
    expect(h.shell.ran, hasLength(1));

    h.files.contents['/marker'] = '';
    final Harness again = Harness(files: FakeFiles(h.files.contents));
    await again.runner.run(program: program(), mode: Mode.run, header: again.header());
    expect(again.shell.ran, isEmpty, reason: 'the command must not run a second time');
  });
}
