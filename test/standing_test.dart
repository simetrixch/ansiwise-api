import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// A run never claims more than it has.
///
/// A record that says "succeeded" answers a different question from the one an operator is asking
/// after a real run. They can see it did not fail. What they cannot see, and what this file makes
/// the record say, is HOW MUCH OF IT ANYTHING LOOKED AT — because a run that skipped half its steps
/// and a run that measured every one of them return the same zero.
///
/// THREE STATES, and the point is that they never mix. Proven is what the framework measured;
/// declared is what something claimed and nothing verified; skipped did not run. **Skipped is not
/// passed**, and a waived gate is not a proof.
void main() {
  /// A registry holding one of each kind of row this file is about.
  Registry registry() => registryOf(
    steps: <String, (String, Step Function(Arguments))>{
      'measures': ('x:1', (Arguments a) => const Measures('the machine is as it should be')),
      'verifies': ('x:2', (Arguments a) => const VerifiesWhatRanBefore()),
    },
    predicates: <String, Predicate>{
      'never': const Says(answer: false, because: 'this machine is not that kind'),
    },
  );

  ResolvedProgram resolve(List<(String, OnFailure, List<String>)> entries) =>
      ProgramResolver(registry()).resolve(programOf('p', entries));

  group('a row the framework measured', () {
    test('is proven', () async {
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: resolve(<(String, OnFailure, List<String>)>[
          ('measures', OnFailure.exit, <String>[]),
        ]),
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(record.steps.single.standing, StepStanding.proven);
      expect(record.standings, const Standings(proven: 1));
      expect(record.fullyProven, isTrue);
    });
  });

  group('a row nothing measured', () {
    test('is declared, not proven', () async {
      // The gate verifies an earlier step, and in a dry run that step has not run — so its check
      // cannot hold and the engine carries the run past it on what it SAYS it would check.
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: resolve(<(String, OnFailure, List<String>)>[
          ('verifies', OnFailure.exit, <String>[]),
        ]),
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(record.steps.single.verdict, isA<Succeeded>());
      expect(
        record.steps.single.standing,
        StepStanding.declared,
        reason: 'the row came back a success, and nothing verified it',
      );
    });

    test('keeps the whole run from reporting as fully proven', () async {
      // THE PROPERTY THIS TICKET EXISTS FOR, and the reason the assertion is on a run with a
      // measured row beside the declared one: a run that was declared THROUGHOUT would fail this
      // too, and would not show that one bad row is enough.
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: resolve(<(String, OnFailure, List<String>)>[
          ('measures', OnFailure.exit, <String>[]),
          ('verifies', OnFailure.exit, <String>[]),
        ]),
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(record.exitCode, 0, reason: 'nothing failed, which is exactly the trap');
      expect(record.standings, const Standings(proven: 1, declared: 1));
      expect(
        record.fullyProven,
        isFalse,
        reason: 'a green run holding one row nothing looked at is not a proven run',
      );
    });
  });

  group('a row that did not run', () {
    test('is skipped, and is never added to the proven ones', () async {
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: resolve(<(String, OnFailure, List<String>)>[
          ('measures', OnFailure.exit, <String>[]),
          ('measures', OnFailure.exit, <String>['never']),
        ]),
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(record.standings, const Standings(proven: 1, skipped: 1));
      expect(
        record.standings.proven,
        1,
        reason:
            'skipped is not passed — the second row ran nothing and must not be counted as if '
            'it had',
      );
      expect(record.fullyProven, isFalse);
    });
  });

  group('a row that failed', () {
    test('is proven, because the framework watched it fail', () async {
      // Standing is not the verdict. A failure the framework measured is a measurement, and reading
      // one off the other is what would let a run report a row nothing looked at as green.
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: resolve(<(String, OnFailure, List<String>)>[
          ('measures', OnFailure.exit, <String>[]),
        ]),
        mode: Mode.run,
        header: h.header(),
      );

      expect(record.steps.single.standing, StepStanding.proven);
    });
  });

  group('the closing line', () {
    test('states the three separately, including the zeroes', () async {
      final Harness h = Harness();
      await h.runner.run(
        program: resolve(<(String, OnFailure, List<String>)>[
          ('measures', OnFailure.exit, <String>[]),
          ('verifies', OnFailure.exit, <String>[]),
          ('measures', OnFailure.exit, <String>['never']),
        ]),
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      final RunFinished closing = h.recorder.events.whereType<RunFinished>().single;
      expect(closing.standings, const Standings(proven: 1, declared: 1, skipped: 1));
      expect(closing.standings.summary, '1 proven, 1 declared, 1 skipped');
    });

    test('says every state even where one is empty', () {
      // A line that dropped the zeroes would read as though those states did not exist, and the
      // reader could not tell "nothing was skipped" from "skipping is not counted here".
      expect(const Standings(proven: 4).summary, '4 proven, 0 declared, 0 skipped');
    });

    test('is what the record says too', () async {
      // Two places state these numbers — the event somebody tails and the record they open
      // afterwards — and a disagreement between them is a disagreement about what a run proved.
      final Harness h = Harness();
      final RunRecord record = await h.runner.run(
        program: resolve(<(String, OnFailure, List<String>)>[
          ('measures', OnFailure.exit, <String>[]),
          ('verifies', OnFailure.exit, <String>[]),
        ]),
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      final RunFinished closing = h.recorder.events.whereType<RunFinished>().single;
      expect(closing.standings, record.standings);
    });
  });
}
