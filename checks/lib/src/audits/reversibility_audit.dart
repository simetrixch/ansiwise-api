/// The suite that drives [Reversibility] over one registry and tree, with its counter-probe.
library;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import '../finding.dart';
import '../registry_completeness.dart';
import '../registry_reading.dart';
import '../reversibility.dart';
import '../source_tree.dart';

/// Runs the reversibility audit over [registry] and [tree].
///
/// WHAT IT STATES: how many entries were read, and how many of them cannot be taken back. The second
/// is the denominator of the half that has teeth — a reading in which nothing is irreversible holds
/// the placeholder rule against nothing.
void auditReversibility(Registry registry, {SourceTree? tree}) {
  final SourceTree judged = tree ?? SourceTree.on(repositoryRoot());
  final RegistryReading reading = RegistryReading.of(registry);
  final Reversibility check = Reversibility(tree: judged, reading: reading);
  final int entries = reading.entries.length;
  final int irreversible = check.irreversibleEntries.length;

  test('$entries entry/entries were read, $irreversible of which cannot be taken back', () {
    expect(
      reading.entries,
      isNotEmpty,
      reason: "no registry entry was read at all, so no step's kind was measured",
    );
  });

  test('every registered step is reversible, irreversible or observing', () {
    expect(
      check.findings,
      isEmpty,
      reason:
          'a step that answers neither leaves a dry run unable to say whether it has passed the '
          'point of no return, and an irreversible one has to say what is lost',
    );
  });

  group('counter-probe', () {
    // The placeholder judgement, from both sides. Only the second half has teeth in a tree whose
    // reasons are all good: a rule that called everything a placeholder would turn every
    // irreversible step red, and a rule that called nothing one is the state this check would rot
    // into.

    for (final String planted in <String>[
      'todo',
      'TODO',
      'n/a',
      'none',
      'not implemented',
      'No undo implemented',
      'undo not implemented',
      'cannot be undone.',
      'irreversible',
      '   ',
    ]) {
      test('"$planted" is not accepted as a reason', () {
        expect(
          reasonIsAPlaceholder(planted),
          isTrue,
          reason: 'a step that says nothing about what is lost would pass',
        );
      });
    }

    for (final String planted in _reasonsThatSayWhatIsLost) {
      test('a reason that says what is lost is left alone', () {
        expect(
          reasonIsAPlaceholder(planted),
          isFalse,
          reason: 'this check refuses a real reason, so every irreversible step would be red',
        );
      });
    }

    // The direct-extension scan, over a tree this audit plants: the violation must be reported and
    // the three kinds must not, or the scan would turn the framework's own step.dart red.
    final SourceTree planted = SourceTree.planted(<String, String>{
      'pubspec.yaml': 'name: planted_package\n',
      'lib/src/domain/step.dart': _plantedKinds,
    });
    final Iterable<String> reported = classesExtendingStepItself(
      planted,
    ).map((DeclaredStepClass declared) => declared.className);

    test('a planted class extending Step itself is reported', () {
      expect(reported, contains('PlantedDirect'), reason: 'this scan cannot go red');
    });

    for (final String allowed in <String>[...theThreeKinds, 'PlantedProper']) {
      test('$allowed is not reported', () {
        expect(
          reported,
          isNot(contains(allowed)),
          reason: 'this scan refuses the very shape every step has',
        );
      });
    }

    test('an irreversible step whose reason says nothing is reported', () {
      final Reversibility onPlanted = Reversibility(
        tree: planted,
        reading: RegistryReading.of(_registryOf(const _SaysNothingIsLost())),
      );
      expect(
        about(onPlanted.findings, 'planted'),
        isNotEmpty,
        reason: 'a placeholder compiles and reads like an answer, which is why it needs a check',
      );
    });

    test('an irreversible step that says what is lost is left alone', () {
      final Reversibility onPlanted = Reversibility(
        tree: planted,
        reading: RegistryReading.of(_registryOf(const _SaysWhatIsLost())),
      );
      expect(
        about(onPlanted.findings, 'planted'),
        isEmpty,
        reason: 'this check reports every irreversible step, so its silence means nothing',
      );
    });
  });
}

/// Three reasons that really say what an operator loses, written without naming any one tool.
///
/// A probe made of one product's sentences proves the rule on that product's wording; these are the
/// three shapes an honest reason has — the old value is not recorded, the previous one was not kept,
/// and what a thing held is gone with it.
const List<String> _reasonsThatSayWhatIsLost = <String>[
  'the target now runs the new revision, and what the old one had written is not recorded anywhere',
  'the values it was running with are replaced, and nothing kept the previous ones',
  'the objects it created are deleted, and what they held is gone with them',
];

/// The three kinds and two planted classes, as the lines of one file.
///
/// Written as a list of lines rather than as one multi-line string, because this file is itself
/// scanned by the check it holds wherever it is resolved from: a line reading `class X extends Step`
/// at column zero would be a declaration as far as that scan is concerned, and the tree holding this
/// file would go red.
final String _plantedKinds = <String>[
  'abstract base class ReversibleStep extends Step {',
  'abstract base class IrreversibleStep extends Step {',
  'abstract base class ObservingStep extends Step {',
  'final class PlantedDirect extends Step {',
  'final class PlantedProper extends ObservingStep {',
].join('\n');

/// A registry holding [step] under the name `planted` and nothing else.
Registry _registryOf(Step step) => Registry(
  steps: <StepName, RegisteredStep>{
    const StepName('planted'): RegisteredStep(
      name: const StepName('planted'),
      source: 'lib/src/steps/planted.dart:1',
      create: (Arguments arguments) => step,
    ),
  },
  predicates: const <PredicateName, RegisteredPredicate>{},
);

/// A step that cannot be taken back and says so with a word instead of a reason.
final class _SaysNothingIsLost extends IrreversibleStep {
  const _SaysNothingIsLost();

  @override
  String get irreversibleReason => 'not implemented';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.nothing('nothing to do');

  @override
  Future<void> apply(StepContext context) async {}
}

/// A step that cannot be taken back and says what an operator loses by going on.
final class _SaysWhatIsLost extends IrreversibleStep {
  const _SaysWhatIsLost();

  @override
  String get irreversibleReason => _reasonsThatSayWhatIsLost.first;

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.nothing('nothing to do');

  @override
  Future<void> apply(StepContext context) async {}
}
