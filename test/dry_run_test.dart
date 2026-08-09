import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// The property this whole framework was chosen for.
///
/// The shell it replaces held 580 places that could change a machine, and no amount of review could
/// prove that none of them fires when somebody asks for a dry run. These tests are what proves it
/// here, and they prove it against steps deliberately written to break it.
void main() {
  group('a dry run cannot change anything', () {
    test('a step that writes from inside its check is refused', () async {
      final Harness h = Harness();
      final ResolvedProgram program =
          ProgramResolver(
            registryOf(
              steps: <String, (String, Step Function(Arguments))>{
                'mutates_while_checking': ('x:1', (Arguments a) => const MutatesWhileChecking()),
              },
            ),
          ).resolve(
            programOf('p', <(String, OnFailure, List<String>)>[
              ('mutates_while_checking', OnFailure.exit, <String>[]),
            ]),
          );

      final RunRecord record = await h.runner.run(
        program: program,
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(h.files.written, isEmpty, reason: 'the write must never have reached the machine');
      expect(record.steps.single.verdict, isA<Failed>());
      expect((record.steps.single.verdict as Failed).reason, contains('refused while planning'));
    });

    test('a step that runs a changing command from inside its plan is refused', () async {
      final Harness h = Harness();
      final ResolvedProgram program =
          ProgramResolver(
            registryOf(
              steps: <String, (String, Step Function(Arguments))>{
                'mutates_while_planning': ('x:1', (Arguments a) => const MutatesWhilePlanning()),
              },
            ),
          ).resolve(
            programOf('p', <(String, OnFailure, List<String>)>[
              ('mutates_while_planning', OnFailure.exit, <String>[]),
            ]),
          );

      await h.runner.run(
        program: program,
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(h.shell.ran, isEmpty, reason: 'the command must never have been started');
    });

    test('an observing command is allowed through, because a plan has to look', () async {
      final Harness h = Harness();
      final ResolvedProgram program =
          ProgramResolver(
            registryOf(
              steps: <String, (String, Step Function(Arguments))>{
                'writes_a_file': (
                  'x:1',
                  (Arguments a) => WritesAFile(path: '/etc/thing', content: 'new'),
                ),
              },
            ),
          ).resolve(
            programOf('p', <(String, OnFailure, List<String>)>[
              ('writes_a_file', OnFailure.exit, <String>[]),
            ]),
          );

      final RunRecord record = await h.runner.run(
        program: program,
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(h.files.written, isEmpty);
      expect(record.steps.single.verdict, isA<Succeeded>());
      expect(record.steps.single.plan, isA<DiffPlan>());
      switch (record.steps.single.plan) {
        case final DiffPlan plan:
          expect(plan.after, 'new');
        default:
          fail('a dry run of a file step must produce a diff');
      }
    });

    test('the plan a dry run produces names the file and what would go in it', () async {
      final Harness h = Harness();
      h.files.contents['/etc/thing'] = 'old';
      final ResolvedProgram program =
          ProgramResolver(
            registryOf(
              steps: <String, (String, Step Function(Arguments))>{
                'writes_a_file': (
                  'deployment/lib/steps/writes_a_file.dart:12',
                  (Arguments a) => WritesAFile(path: '/etc/thing', content: 'new'),
                ),
              },
            ),
          ).resolve(
            programOf('p', <(String, OnFailure, List<String>)>[
              ('writes_a_file', OnFailure.exit, <String>[]),
            ]),
          );

      final RunRecord record = await h.runner.run(
        program: program,
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      switch (record.steps.single.plan) {
        case final DiffPlan plan:
          expect(plan.path, '/etc/thing');
          expect(plan.before, 'old');
          expect(plan.after, 'new');
          expect(plan.creates, isFalse);
        default:
          fail('a dry run of a file step must produce a diff');
      }
      expect(
        record.steps.single.source,
        'deployment/lib/steps/writes_a_file.dart:12',
        reason: 'the row points at the file that defines the step',
      );
    });
  });
}
