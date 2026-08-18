import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

import '../support/example_steps.dart';
import '../support/harness.dart';

/// A condition that is TOLD what to look at, and where it is told.
///
/// A plugin brings the generic condition and cannot name the fact it is pointed at — the file, the
/// key, the interface — because a package that named one installation's facts would be useless to
/// anybody else with the same tool. A program row cannot name it either: `when:` is a list of bare
/// names, and a structure there is the first line of a configuration language. So the installation's
/// own configuration says it, once, and what a program row then writes is the name that
/// configuration chose.
void main() {
  const PredicateName generic = PredicateName('answers_as_told');
  const PredicateName fixed = PredicateName('always_holds');
  const PredicateName chosen = PredicateName('subject_enabled');

  Registry registry() => Registry(
    steps: <StepName, RegisteredStep>{
      const StepName('alpha_step'): RegisteredStep(
        name: const StepName('alpha_step'),
        source: 'test/config/condition_binding_test.dart:1',
        create: (Arguments arguments) =>
            RunsACommand(argv: const <String>['true'], leaves: '/tmp/alpha'),
      ),
    },
    predicates: <PredicateName, RegisteredPredicate>{
      generic: const RegisteredPredicate.taking(
        name: generic,
        source: 'test/config/condition_binding_test.dart:1',
        create: _AnswersAsTold.fromValues,
        describes: 'answers what it was told to answer',
        arguments: _AnswersAsTold.values,
      ),
      fixed: const RegisteredPredicate(
        name: fixed,
        source: 'test/config/condition_binding_test.dart:1',
        predicate: Says(answer: true, because: 'always'),
        describes: 'always holds',
      ),
    },
  );

  Registry bind(Map<String, ConditionBinding> named) =>
      bindConditions(registry: registry(), named: named, where: 'ansiwise.yaml');

  group('binding a condition to what it looks at', () {
    test('puts it in the registry under the name the configuration chose', () {
      final Registry bound = bind(<String, ConditionBinding>{
        chosen.value: const ConditionBinding(
          predicate: 'answers_as_told',
          values: <String, Object>{'holds': true, 'because': 'the subject is turned on'},
        ),
      });

      // The innocent case of this whole file. A binder that refused everything would be caught
      // here, and every refusal below would otherwise prove nothing.
      expect(bound.predicate(chosen), isNotNull);
      expect(bound.predicate(chosen)!.takesArguments, isFalse);
    });

    test('a run reads the answer the bound values produce, in their own words', () async {
      final Registry bound = bind(<String, ConditionBinding>{
        chosen.value: const ConditionBinding(
          predicate: 'answers_as_told',
          values: <String, Object>{'holds': false, 'because': 'the subject is turned off'},
        ),
      });

      final Harness harness = Harness();
      final RunRecord record = await harness.runner.run(
        program: ProgramResolver(bound).resolve(
          programOf('example', <(String, OnFailure, List<String>)>[
            ('alpha_step', OnFailure.exit, <String>[chosen.value]),
          ]),
        ),
        mode: Mode.run,
        header: harness.header(),
      );

      // The whole chain in one measurement: the configuration named it, the binding built it, the
      // resolver bound the row to it, and the record says what it found under the name the
      // installation chose rather than the name the plugin registered.
      final PredicateEvaluated measured = harness.recorder.only<PredicateEvaluated>().single;
      expect(measured.predicate, chosen);
      expect(measured.held, isFalse);
      expect(measured.because, 'the subject is turned off');
      expect(record.steps.single.verdict, isA<Skipped>());
    });

    test('a value nobody wrote is filled from what the condition declares', () {
      final Registry bound = bind(<String, ConditionBinding>{
        chosen.value: const ConditionBinding(
          predicate: 'answers_as_told',
          values: <String, Object>{'holds': true},
        ),
      });

      expect(bound.predicate(chosen), isNotNull);
    });

    test('the generic condition stays in the registry it came from', () {
      final Registry bound = bind(<String, ConditionBinding>{
        chosen.value: const ConditionBinding(
          predicate: 'answers_as_told',
          values: <String, Object>{'holds': true},
        ),
      });

      expect(bound.predicate(generic), isNotNull);
      expect(bound.predicate(generic)!.takesArguments, isTrue);
    });

    test('a configuration that names no condition changes nothing', () {
      expect(bind(const <String, ConditionBinding>{}).predicates.keys, registry().predicates.keys);
    });
  });

  group('what the binding refuses', () {
    test('a generic condition nothing is registered under, saying what there is', () {
      expect(
        () => bind(<String, ConditionBinding>{
          chosen.value: const ConditionBinding(
            predicate: 'nothing_registers_this',
            values: <String, Object>{},
          ),
        }),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            allOf(
              contains('"subject_enabled"'),
              contains('nothing_registers_this'),
              contains('this binary carries: answers_as_told'),
            ),
          ),
        ),
      );
    });

    test('a required value nobody gave, naming the value', () {
      expect(
        () => bind(<String, ConditionBinding>{
          chosen.value: const ConditionBinding(
            predicate: 'answers_as_told',
            values: <String, Object>{},
          ),
        }),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            allOf(contains('needs the value "holds"'), contains('subject_enabled')),
          ),
        ),
      );
    });

    test('a value of the wrong kind', () {
      expect(
        () => bind(<String, ConditionBinding>{
          chosen.value: const ConditionBinding(
            predicate: 'answers_as_told',
            values: <String, Object>{'holds': 'yes'},
          ),
        }),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            allOf(contains('"holds" holds flag'), contains('String')),
          ),
        ),
      );
    });

    test('a value the condition does not declare', () {
      expect(
        () => bind(<String, ConditionBinding>{
          chosen.value: const ConditionBinding(
            predicate: 'answers_as_told',
            values: <String, Object>{'holds': true, 'nobody_declares_this': 'x'},
          ),
        }),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('has no value "nobody_declares_this"'),
          ),
        ),
      );
    });

    test('a name a plugin already registered, rather than deciding it by order', () {
      expect(
        () => bind(<String, ConditionBinding>{
          fixed.value: const ConditionBinding(
            predicate: 'answers_as_told',
            values: <String, Object>{'holds': true},
          ),
        }),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            allOf(contains('already registered by a plugin'), contains('always_holds')),
          ),
        ),
      );
    });

    test('a condition that is told nothing, because it is already one a row may write', () {
      expect(
        () => bind(<String, ConditionBinding>{
          chosen.value: const ConditionBinding(
            predicate: 'always_holds',
            values: <String, Object>{},
          ),
        }),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('name it directly'),
          ),
        ),
      );
    });

    test('every problem at once, so one run teaches everything', () {
      expect(
        () => bind(<String, ConditionBinding>{
          'first_one': const ConditionBinding(
            predicate: 'nothing_registers_this',
            values: <String, Object>{},
          ),
          'second_one': const ConditionBinding(
            predicate: 'answers_as_told',
            values: <String, Object>{},
          ),
        }),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            allOf(contains('first_one'), contains('second_one')),
          ),
        ),
      );
    });
  });

  group('what a program row may write', () {
    test('the bound name resolves', () {
      final Registry bound = bind(<String, ConditionBinding>{
        chosen.value: const ConditionBinding(
          predicate: 'answers_as_told',
          values: <String, Object>{'holds': true},
        ),
      });

      final ResolvedProgram resolved = ProgramResolver(bound).resolve(
        programOf('example', <(String, OnFailure, List<String>)>[
          ('alpha_step', OnFailure.exit, <String>[chosen.value]),
        ]),
      );

      expect(resolved.steps.single.when.single.name, chosen);
    });

    test('the generic name is refused, and the refusal says where to name it', () {
      expect(
        () => ProgramResolver(registry()).resolve(
          programOf('example', <(String, OnFailure, List<String>)>[
            ('alpha_step', OnFailure.exit, <String>[generic.value]),
          ]),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid invalid) => invalid.message,
            'message',
            allOf(contains('has to be told what to look at'), contains('configuration')),
          ),
        ),
        reason:
            'a row naming it directly would leave the condition reading nothing, which is a '
            'condition that cannot answer',
      );
    });
  });

  group('what the run is gated against', () {
    String fingerprintUnder(String because) {
      final Registry bound = bind(<String, ConditionBinding>{
        chosen.value: ConditionBinding(
          predicate: 'answers_as_told',
          values: <String, Object>{'holds': true, 'because': because},
        ),
      });
      return fingerprintOf(
        program: ProgramResolver(bound).resolve(
          programOf('example', <(String, OnFailure, List<String>)>[
            ('alpha_step', OnFailure.exit, <String>[chosen.value]),
          ]),
        ),
        commit: '0000000',
        answers: Arguments.none,
      );
    }

    test('a condition pointed at something else is a different input', () {
      expect(
        fingerprintUnder('one fact'),
        isNot(fingerprintUnder('another fact')),
        reason:
            'the name alone says half of what decides whether a row runs, and a dry run of one '
            'installation would otherwise admit a real run of another',
      );
    });

    test('the same binding twice is the same input', () {
      // Without this the case above would pass on a fingerprint that simply never repeats.
      expect(fingerprintUnder('one fact'), fingerprintUnder('one fact'));
    });
  });

  group('what the configuration file says', () {
    Future<Configuration> read(String yaml) {
      final FakeFiles files = FakeFiles(<String, String>{'ansiwise.yaml': yaml});
      return Configuration.load(files: files, path: 'ansiwise.yaml');
    }

    test('names the condition and every value under it', () async {
      final Configuration configuration = await read('''
plugins:
  - one
conditions:
  subject_enabled:
    predicate: key_is_true
    file: settings/one
    key: SUBJECT_ENABLED
''');

      expect(configuration.conditions.keys, <String>['subject_enabled']);
      expect(configuration.conditions['subject_enabled']!.predicate, 'key_is_true');
      expect(configuration.conditions['subject_enabled']!.values, <String, Object>{
        'file': 'settings/one',
        'key': 'SUBJECT_ENABLED',
      });
    });

    test('carries a whole number, a flag and a list as themselves', () async {
      final Configuration configuration = await read('''
plugins:
  - one
conditions:
  subject_enabled:
    predicate: whatever
    count: 2
    strict: true
    names: [one, other]
''');

      expect(configuration.conditions['subject_enabled']!.values, <String, Object>{
        'count': 2,
        'strict': true,
        'names': <String>['one', 'other'],
      });
    });

    test('a file that names none carries none', () async {
      expect((await read('plugins:\n  - one\n')).conditions, isEmpty);
    });

    test('refuses a conditions block that is not a mapping', () {
      expect(
        read('plugins:\n  - one\nconditions:\n  - subject_enabled\n'),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('"conditions" has to be a mapping'),
          ),
        ),
      );
    });

    test('refuses a name a program row could not write', () {
      expect(
        read('plugins:\n  - one\nconditions:\n  Subject-Enabled:\n    predicate: one\n'),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('is not a condition name'),
          ),
        ),
      );
    });

    test('refuses a condition that says which condition it is nowhere', () {
      expect(
        read('plugins:\n  - one\nconditions:\n  subject_enabled:\n    key: SOMETHING\n'),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('says no "predicate:"'),
          ),
        ),
      );
    });

    test('refuses a value nested deeper than the file can show', () {
      expect(
        read('''
plugins:
  - one
conditions:
  subject_enabled:
    predicate: one
    where:
      deeper: value
'''),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('a value is text, a whole number, true or false, or a list of text'),
          ),
        ),
        reason: 'a value nobody can see the shape of in the file is a value nobody can predict',
      );
    });
  });
}

/// A condition that answers whatever the installation told it to answer.
///
/// Stands in for a real generic condition so that what these tests measure is the BINDING and not
/// what some particular condition reads. Real ones are brought by plugins; the framework has none of
/// its own and must not grow one.
final class _AnswersAsTold implements Predicate {
  const _AnswersAsTold({required this.answer, required this.because});

  /// Builds it from the values the installation bound to its name.
  factory _AnswersAsTold.fromValues(Arguments values) =>
      _AnswersAsTold(answer: values.flag('holds'), because: values.text('because'));

  /// What it has to be told, and what stands in where it is told nothing.
  static const List<ArgumentSpec> values = <ArgumentSpec>[
    ArgumentSpec(name: 'holds', kind: ArgumentKind.flag, describes: 'what this condition answers'),
    ArgumentSpec(
      name: 'because',
      kind: ArgumentKind.text,
      describes: 'what it says it saw',
      required: false,
      defaultValue: 'it was told so',
    ),
  ];

  final bool answer;
  final String because;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async =>
      answer ? PredicateResult.holds(because) : PredicateResult.doesNotHold(because);
}
