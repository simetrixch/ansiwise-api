import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// A skipped step names the condition that skipped it.
///
/// A run that quietly does less on one machine than on another is a run nobody can reason about.
/// Every condition is measured once, before the first step, and the answer is in the record — so
/// the plan printed before anything happens is the plan that is followed.
void main() {
  ResolvedProgram programGuardedBy({required bool holds, required String because}) =>
      ProgramResolver(
        registryOf(
          steps: <String, (String, Step Function(Arguments))>{
            'writes': ('x:1', (Arguments a) => WritesAFile(path: '/x', content: 'x')),
          },
          predicates: <String, Predicate>{'has_two_nics': Says(answer: holds, because: because)},
        ),
      ).resolve(
        programOf('p', <(String, OnFailure, List<String>)>[
          ('writes', OnFailure.exit, <String>['has_two_nics']),
        ]),
      );

  test('a step whose condition does not hold is skipped, and the record says which', () async {
    final Harness h = Harness();
    final RunRecord record = await h.runner.run(
      program: programGuardedBy(holds: false, because: 'this machine has one network interface'),
      mode: Mode.run,
      header: h.header(),
    );

    expect(record.steps.single.verdict, isA<Skipped>());
    expect((record.steps.single.verdict as Skipped).predicate, 'has_two_nics');
    expect(h.files.written, isEmpty);
    expect(record.exitCode, 0, reason: 'a skipped step is not a failure');
  });

  test('a step whose condition holds runs', () async {
    final Harness h = Harness();
    final RunRecord record = await h.runner.run(
      program: programGuardedBy(holds: true, because: 'two interfaces are up'),
      mode: Mode.run,
      header: h.header(),
    );

    expect(record.steps.single.verdict, isA<Succeeded>());
    expect(h.files.written, <String>['/x']);
  });

  test('what a condition found is in the record, in its own words', () async {
    final Harness h = Harness();
    await h.runner.run(
      program: programGuardedBy(holds: false, because: 'this machine has one network interface'),
      mode: Mode.run,
      header: h.header(),
    );

    final List<PredicateEvaluated> measured = h.recorder.only<PredicateEvaluated>();
    expect(measured, hasLength(1));
    expect(measured.single.predicate.value, 'has_two_nics');
    expect(measured.single.held, isFalse);
    expect(measured.single.because, 'this machine has one network interface');
  });

  test('a condition is measured once even when several steps use it', () async {
    final Harness h = Harness();
    int asked = 0;
    final ResolvedProgram program =
        ProgramResolver(
          registryOf(
            steps: <String, (String, Step Function(Arguments))>{
              'a': ('x:1', (Arguments _) => WritesAFile(path: '/a', content: 'a')),
              'b': ('x:2', (Arguments _) => WritesAFile(path: '/b', content: 'b')),
            },
            predicates: <String, Predicate>{'counted': Counting(() => asked++)},
          ),
        ).resolve(
          programOf('p', <(String, OnFailure, List<String>)>[
            ('a', OnFailure.exit, <String>['counted']),
            ('b', OnFailure.exit, <String>['counted']),
          ]),
        );

    await h.runner.run(program: program, mode: Mode.run, header: h.header());
    expect(asked, 1, reason: 'a machine measured twice can answer twice');
  });

  test(
    'a program that does not apply to this role is refused before anything is measured',
    () async {
      final Harness h = Harness();
      await expectLater(
        h.runner.run(
          program: programGuardedBy(holds: true, because: 'x'),
          mode: Mode.run,
          header: h.header(role: 'slave'),
        ),
        throwsA(isA<RoleMismatch>()),
      );
      expect(h.recorder.events, isEmpty);
    },
  );
}

final class Counting implements Predicate {
  const Counting(this.onAsk);

  final void Function() onAsk;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    onAsk();
    return const PredicateResult.holds('counted');
  }
}
