import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// What a failed run takes back, and what it deliberately does not.
///
/// A machine cannot be rolled back — there is no transaction around installing a package. What is
/// achievable is compensation, and it is only safe if it is narrow: only steps that actually ran,
/// only steps that said how, in reverse.
void main() {
  ResolvedProgram twoWritesThenAFailure() =>
      ProgramResolver(
        registryOf(
          steps: <String, (String, Step Function(Arguments))>{
            'first': ('x:1', (Arguments a) => WritesAFile(path: '/one', content: '1')),
            'second': ('x:2', (Arguments a) => WritesAFile(path: '/two', content: '2')),
            'fails': ('x:3', (Arguments a) => const Blocks('the disk went away')),
          },
        ),
      ).resolve(
        programOf('p', <(String, OnFailure, List<String>)>[
          ('first', OnFailure.die, <String>[]),
          ('second', OnFailure.die, <String>[]),
          ('fails', OnFailure.die, <String>[]),
        ]),
      );

  test('what was applied is taken back, newest first', () async {
    final Harness h = Harness();
    await h.runner.run(program: twoWritesThenAFailure(), mode: Mode.run, header: h.header());

    expect(h.files.deleted, <String>['/two', '/one'], reason: 'in reverse, not in order');
    expect(h.files.contents, isEmpty);
  });

  test('a step that never ran is not taken back', () async {
    final Harness h = Harness();
    final ResolvedProgram program =
        ProgramResolver(
          registryOf(
            steps: <String, (String, Step Function(Arguments))>{
              'fails': ('x:1', (Arguments a) => const Blocks('nothing here')),
              'never': ('x:2', (Arguments a) => WritesAFile(path: '/never', content: 'x')),
            },
          ),
        ).resolve(
          programOf('p', <(String, OnFailure, List<String>)>[
            ('fails', OnFailure.die, <String>[]),
            ('never', OnFailure.die, <String>[]),
          ]),
        );

    await h.runner.run(program: program, mode: Mode.run, header: h.header());

    expect(
      h.files.deleted,
      isEmpty,
      reason: 'undoing a step that never ran would be a change nobody asked for',
    );
  });

  test('a step with nothing to do is not taken back either', () async {
    final Harness h = Harness(files: FakeFiles(<String, String>{'/one': '1'}));
    final ResolvedProgram program =
        ProgramResolver(
          registryOf(
            steps: <String, (String, Step Function(Arguments))>{
              'first': ('x:1', (Arguments a) => WritesAFile(path: '/one', content: '1')),
              'fails': ('x:2', (Arguments a) => const Blocks('the disk went away')),
            },
          ),
        ).resolve(
          programOf('p', <(String, OnFailure, List<String>)>[
            ('first', OnFailure.die, <String>[]),
            ('fails', OnFailure.die, <String>[]),
          ]),
        );

    await h.runner.run(program: program, mode: Mode.run, header: h.header());

    expect(h.files.deleted, isEmpty);
    expect(h.files.contents['/one'], '1', reason: 'the file was already there and stays');
  });

  test('an irreversible step is passed over and says why', () async {
    final Harness h = Harness();
    final ResolvedProgram program =
        ProgramResolver(
          registryOf(
            steps: <String, (String, Step Function(Arguments))>{
              'irreversible': (
                'x:1',
                (Arguments a) => RunsACommand(argv: const <String>['touch', '/m'], leaves: '/m'),
              ),
              'fails': ('x:2', (Arguments a) => const Blocks('the disk went away')),
            },
          ),
        ).resolve(
          programOf('p', <(String, OnFailure, List<String>)>[
            ('irreversible', OnFailure.warn, <String>[]),
            ('fails', OnFailure.die, <String>[]),
          ]),
        );

    // The command leaves the file behind, the way the real one would, so the step actually applies
    // and is a candidate for being taken back.
    h.shell.changes('touch /m', () => h.files.contents['/m'] = '');
    await h.runner.run(program: program, mode: Mode.run, header: h.header());

    expect(
      h.recorder.notes,
      contains('not taken back: the command it runs does not come with a way back'),
    );
  });

  test('nothing is taken back after a dry run, because nothing was done', () async {
    final Harness h = Harness();
    await h.runner.run(
      program: twoWritesThenAFailure(),
      mode: Mode.dry,
      header: h.header(mode: Mode.dry),
    );

    expect(h.files.written, isEmpty);
    expect(h.files.deleted, isEmpty);
  });
}
