import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
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
          ('first', OnFailure.exit, <String>[]),
          ('second', OnFailure.exit, <String>[]),
          ('fails', OnFailure.exit, <String>[]),
        ]),
      );

  test('what was applied is taken back, newest first', () async {
    final Harness h = Harness();
    await h.runner.run(program: twoWritesThenAFailure(), mode: Mode.run, header: h.header());

    expect(h.files.deleted, <String>['/two', '/one'], reason: 'in reverse, not in order');
    expect(h.files.contents, isEmpty);
  });

  group('an unwind that was deliberately not performed', () {
    Runner refusingToUnwind(Harness h, {required String by}) => Runner(
      machine: h.machine,
      recorder: h.recorder,
      redactor: h.redactor,
      unwindDisabledBy: by,
    );

    test('leaves the changes where they are, which is the whole point of asking for it', () async {
      final Harness h = Harness();
      await refusingToUnwind(
        h,
        by: 'the --no-unwind option',
      ).run(program: twoWritesThenAFailure(), mode: Mode.run, header: h.header());

      expect(h.files.deleted, isEmpty);
      expect(h.files.contents.keys, containsAll(<String>['/one', '/two']));
    });

    test('the RECORD names every step still standing, not a log line', () async {
      // A warning among the log entries is not where somebody decides what to do to a machine
      // next. This is what that decision is read off, so it is a field of the outcome.
      final Harness h = Harness();
      final RunRecord closed = await refusingToUnwind(
        h,
        by: 'the --no-unwind option',
      ).run(program: twoWritesThenAFailure(), mode: Mode.run, header: h.header());

      expect(closed.leftStanding, <String>['first', 'second']);
      expect(closed.exitCode, 1);
    });

    test('it survives being written down and read back', () async {
      // The record on disk is what anybody looks at afterwards, and a field that only exists in
      // memory tells nobody anything.
      final Harness h = Harness();
      final RunRecord closed = await refusingToUnwind(
        h,
        by: 'the --no-unwind option',
      ).run(program: twoWritesThenAFailure(), mode: Mode.run, header: h.header());

      const RecordCodec codec = RecordCodec();
      final Map<String, Object?> written = codec.run(closed);
      expect(written['left_standing'], <String>['first', 'second']);
      expect(codec.runFrom(written).leftStanding, <String>['first', 'second']);
    });

    test('the message names the surface the decision came from', () async {
      // It used to say "--no-unwind was given" whatever had decided it, so an operator who set a
      // key in a configuration file was told about a command-line option they never typed.
      final Harness h = Harness();
      await refusingToUnwind(
        h,
        by: 'no_unwind: true in ansiwise.yaml',
      ).run(program: twoWritesThenAFailure(), mode: Mode.run, header: h.header());

      expect(
        h.recorder.events.whereType<Log>().map((Log e) => e.message).join('\n'),
        allOf(contains('no_unwind: true in ansiwise.yaml'), contains('first, second')),
      );
    });

    test('the innocent neighbour: a run that DID unwind carries nothing standing', () async {
      // Without this, a version that filled the field on every failed run would pass every test
      // above and say the machine was dirty after a clean rollback.
      final Harness h = Harness();
      final RunRecord closed = await h.runner.run(
        program: twoWritesThenAFailure(),
        mode: Mode.run,
        header: h.header(),
      );

      expect(closed.leftStanding, isEmpty);
      expect(const RecordCodec().run(closed).containsKey('left_standing'), isFalse);
    });
  });

  test('a step whose apply THREW is taken back, which is where it matters most', () async {
    // The contract on Step.undo says it must tolerate being called after a partial apply, "and that
    // is exactly when it matters". It used to be the one path where it was never called: an apply
    // that threw left the step's own branch entirely, and the answer that came back carried no
    // applied step — so the unwind never reached it, the capture was discarded, and what the step
    // changed before it threw stood while its kind still said it could be taken back.
    final Harness h = Harness();
    final ResolvedProgram program =
        ProgramResolver(
          registryOf(
            steps: <String, (String, Step Function(Arguments))>{
              'half': ('x:1', (Arguments a) => ChangesThenThrows(path: '/half')),
            },
          ),
        ).resolve(
          programOf('p', <(String, OnFailure, List<String>)>[('half', OnFailure.exit, <String>[])]),
        );

    await h.runner.run(program: program, mode: Mode.run, header: h.header());

    expect(h.files.written, contains('/half'), reason: 'the apply really did change something');
    expect(
      h.files.contents.containsKey('/half'),
      isFalse,
      reason: 'and the throw did not stop it being taken back',
    );
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
            ('fails', OnFailure.exit, <String>[]),
            ('never', OnFailure.exit, <String>[]),
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
            ('first', OnFailure.exit, <String>[]),
            ('fails', OnFailure.exit, <String>[]),
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
            ('irreversible', OnFailure.continueRun, <String>[]),
            ('fails', OnFailure.exit, <String>[]),
          ]),
        );

    // The command leaves the file behind, the way the real one would, so the step actually applies
    // and is a candidate for being taken back.
    h.shell.changes('touch /m', () => h.files.contents['/m'] = '');
    await h.runner.run(program: program, mode: Mode.run, header: h.header());

    expect(
      h.recorder.logLines,
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

  group('a step the program says not to take back', () {
    // The operator's own decision, and the reason it exists: a step that CAN be undone is not always
    // one that SHOULD be. Putting a configuration back over one a person has edited since is a
    // correct undo doing damage, and whether that is right here is a question about one installation
    // rather than about the step.

    ResolvedProgram withTheSecondLeftStanding() =>
        ProgramResolver(
          registryOf(
            steps: <String, (String, Step Function(Arguments))>{
              'first': ('x:1', (Arguments a) => WritesAFile(path: '/one', content: '1')),
              'second': ('x:2', (Arguments a) => WritesAFile(path: '/two', content: '2')),
              'fails': ('x:3', (Arguments a) => const Blocks('the disk went away')),
            },
          ),
        ).resolve(
          programOf(
            'p',
            <(String, OnFailure, List<String>)>[
              ('first', OnFailure.exit, <String>[]),
              ('second', OnFailure.exit, <String>[]),
              ('fails', OnFailure.exit, <String>[]),
            ],
            undoOff: <String>{'second'},
          ),
        );

    test('stands, while the steps around it are still taken back', () async {
      final Harness h = Harness();
      await h.runner.run(program: withTheSecondLeftStanding(), mode: Mode.run, header: h.header());

      expect(
        h.files.deleted,
        <String>['/one'],
        reason:
            'the switch is about ONE step; a run that stopped unwinding at it would leave behind '
            'everything before it as well, which nobody asked for',
      );
      expect(h.files.contents.keys, contains('/two'));
    });

    test('and this run says before it starts that it cannot take that step back', () {
      final NoWayBack? boundary = pointOfNoReturn(withTheSecondLeftStanding());
      expect(boundary?.step, const StepName('second'));
      expect(
        boundary?.because,
        Irreversibility.byDecision,
        reason:
            'learning at the moment an unwind reaches the step that it will not be undone is '
            'learning it too late',
      );
    });
  });
}
