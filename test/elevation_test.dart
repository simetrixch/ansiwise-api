import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// Raising a command to root: where the password comes from, and what the record says about it.
///
/// Treat every line here as security work. A password on a command line stands in the process
/// listing for every account on the machine; a password read from a path written into the framework
/// is a path nobody could change and one that failed as the command underneath it, sending the
/// operator to read a tool's output for a problem that was never in it.
void main() {
  group('where the password comes from', () {
    test('is the first line of the file the installation named', () async {
      final Elevation elevation = await Elevation.read(
        files: FakeFiles(<String, String>{'/somewhere/.pass': 'the password\n'}),
        path: '/somewhere/.pass',
      );

      expect(elevation.password, 'the password');
      expect(elevation.from, '/somewhere/.pass');
    });

    test('keeps a password exactly as it stands, spaces and all', () async {
      // Not trimmed. A password quietly stripped is a run that fails to elevate with a file that
      // looks correct, and nothing in the failure would point at the trimming.
      final Elevation elevation = await Elevation.read(
        files: FakeFiles(<String, String>{'/p': ' two words \n'}),
        path: '/p',
      );

      expect(elevation.password, ' two words ');
    });

    test('reads a file an editor ended with a carriage return', () async {
      final Elevation elevation = await Elevation.read(
        files: FakeFiles(<String, String>{'/p': 'the password\r\n'}),
        path: '/p',
      );

      expect(elevation.password, 'the password');
    });

    test('a file that is not there refuses, and the refusal is about the password', () {
      expect(
        Elevation.read(files: FakeFiles(<String, String>{}), path: '/gone/.pass'),
        throwsA(
          isA<ElevationUnavailable>().having(
            (ElevationUnavailable refused) => refused.message,
            'message',
            allOf(contains('elevation password file'), contains('/gone/.pass')),
          ),
        ),
        reason:
            'this used to fail inside a shell and come back as a non-zero exit of the step\'s own '
            'command, which sends the operator to look at the wrong thing',
      );
    });

    test('a file whose first line is empty refuses rather than elevating with nothing', () {
      expect(
        Elevation.read(files: FakeFiles(<String, String>{'/p': '\nsomething\n'}), path: '/p'),
        throwsA(
          isA<ElevationUnavailable>().having(
            (ElevationUnavailable refused) => refused.message,
            'message',
            contains('holds no password'),
          ),
        ),
      );
    });

    test('nothing configured is a state, not a password', () {
      expect(const Elevation.unconfigured().password, isNull);
    });
  });

  group('what the configuration file says about it', () {
    Future<Configuration> read(String yaml) => Configuration.load(
      files: FakeFiles(<String, String>{'ansiwise.yaml': yaml}),
      path: 'ansiwise.yaml',
    );

    test('names the file, and there is no path anywhere to fall back to', () async {
      expect(
        (await read(
          'plugins:\n  - one\nelevation:\n  password_file: /home/op/.pass\n',
        )).elevationPasswordFile,
        '/home/op/.pass',
      );
    });

    test('a file that says nothing about it names nothing', () async {
      expect((await read('plugins:\n  - one\n')).elevationPasswordFile, isNull);
    });

    test('an elevation block with no file is refused rather than read past', () {
      // Somebody who wrote the word meant to configure elevation, and a key silently ignored leaves
      // them believing they did.
      expect(
        read('plugins:\n  - one\nelevation:\n  something_else: /x\n'),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('says no "password_file:"'),
          ),
        ),
      );
    });

    test('an elevation that is not a mapping is refused', () {
      expect(
        read('plugins:\n  - one\nelevation: /home/op/.pass\n'),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('"elevation" has to be a mapping'),
          ),
        ),
      );
    });
  });

  group('a command that has to run as root', () {
    test('is refused before the process starts when nothing says how', () {
      // The executable named here exists on no machine this suite runs on. A shell that started the
      // process first would come back with a failure to start it; getting the refusal instead is
      // what proves nothing was started.
      expect(
        const RealShell(
          elevation: Elevation.unconfigured(),
        ).run(const Command.detailed('no-such-executable-anywhere', elevated: true)),
        throwsA(
          isA<ElevationUnavailable>().having(
            (ElevationUnavailable refused) => refused.message,
            'message',
            allOf(contains('no-such-executable-anywhere'), contains('has to run as root')),
          ),
        ),
      );
    });

    test('may also be one that only looks at the machine', () {
      // The pair the shorthand cannot write. A check that needs root to see what it is looking at
      // stays observing, so a dry run still performs it.
      const Command looking = Command.detailed('a-tool', observes: true, elevated: true);

      expect(looking.observes, isTrue);
      expect(looking.elevated, isTrue);
    });

    test('is let through by a dry run exactly because it observes', () async {
      final FakeShell inner = FakeShell();

      await PlanningShell(inner, step: const StepName('a_step')).run(
        const Command.detailed(
          'a-tool',
          arguments: <String>['status'],
          observes: true,
          elevated: true,
        ),
      );

      expect(inner.ran, <String>['a-tool status']);
    });

    test('is refused by a dry run when it changes something, root or not', () {
      // The counter-probe of the case above: elevation is not what the dry run decides on, so a
      // shell that let the observing one through because it was elevated would pass this too.
      final FakeShell inner = FakeShell();

      expect(
        () => PlanningShell(
          inner,
          step: const StepName('a_step'),
        ).run(const Command.detailed('a-tool', arguments: <String>['apply'], elevated: true)),
        throwsA(isA<MutationRefused>()),
      );
      expect(inner.ran, isEmpty);
    });
  });

  group('what the record says about it', () {
    test('a command that ran as root says so', () async {
      final Harness harness = Harness();
      await RecordingShell(
        harness.shell,
        recorder: harness.recorder,
        redactor: harness.redactor,
        step: const StepName('a_step'),
      ).run(const Command.detailed('a-tool', elevated: true));

      expect(harness.recorder.only<CommandStarted>().single.elevated, isTrue);
    });

    test('a command that did not says so too', () async {
      // The innocent case. A writer that hardcoded either answer would pass one of these two and
      // fail the other, and neither alone would notice.
      final Harness harness = Harness();
      await RecordingShell(
        harness.shell,
        recorder: harness.recorder,
        redactor: harness.redactor,
        step: const StepName('a_step'),
      ).run(const Command('a-tool'));

      expect(harness.recorder.only<CommandStarted>().single.elevated, isFalse);
    });

    test('the command it records is the one the step wrote', () async {
      // Not the elevating tool and its options. Those are the same every time and say nothing about
      // this run, while the command a step meant is what a reader is looking for.
      final Harness harness = Harness();
      await RecordingShell(
        harness.shell,
        recorder: harness.recorder,
        redactor: harness.redactor,
        step: const StepName('a_step'),
      ).run(const Command.detailed('a-tool', arguments: <String>['upgrade'], elevated: true));

      expect(harness.recorder.only<CommandStarted>().single.argv, <String>['a-tool', 'upgrade']);
    });
  });
}
