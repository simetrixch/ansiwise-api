import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// What an argument reader says when a row wrote a value of another kind under the name.
///
/// The reader a step reaches for while it is being built is the last thing between a misspelled
/// argument name and the sentence an operator reads. `--mode test` is the gate a person meets FIRST
/// — before a machine is touched — so a reader that faults where the others refuse describes the
/// operator's mistake as an engine fault, and sends them into the framework to debug their own typo.
void main() {
  const MeasurementName backend = MeasurementName('host.backend');

  group('optionalText', () {
    test('is null where the row gave nothing', () {
      expect(const Arguments(<String, Object>{}).optionalText('bearer'), isNull);
    });

    test('is the text where the row gave text', () {
      expect(
        const Arguments(<String, Object>{'bearer': 'a-token'}).optionalText('bearer'),
        'a-token',
      );
    });

    test('refuses by name where the row gave a value of another kind', () {
      // What the operator wrote is `bearer: { answer: stage }`, where the grammar wants
      // `bearer_answer: stage`. The mapping reaches the reader whole.
      const Arguments given = Arguments(<String, Object>{
        'bearer': <String, Object?>{'answer': 'stage'},
      });

      expect(
        () => given.optionalText('bearer'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError refusal) => refusal.toString(),
            'the refusal',
            allOf(
              contains('bearer'),
              contains('declared as String but the program gave'),
              isNot(contains('is not a subtype of type')),
            ),
          ),
        ),
      );
    });

    test('refuses in the words text() uses, because it is the same event', () {
      const Arguments given = Arguments(<String, Object>{
        'bearer': <String, Object?>{'answer': 'stage'},
      });

      String refusalOf(void Function() read) {
        try {
          read();
        } on Object catch (refusal) {
          return refusal.toString();
        }
        return 'nothing was refused';
      }

      expect(refusalOf(() => given.optionalText('bearer')), refusalOf(() => given.text('bearer')));
    });
  });

  group('the sentence the gate gives an operator', () {
    Registry registry() => registryOf(
      steps: <String, (String, Step Function(Arguments))>{
        'measures': (
          'x:1',
          (Arguments a) => const MeasuresAndPublishes(file: '/etc/measured', publishes: backend),
        ),
        'writes': ('x:2', WritesWhatItWasGiven.fromArguments),
      },
      arguments: <String, List<ArgumentSpec>>{
        'writes': const <ArgumentSpec>[
          ArgumentSpec(name: 'path', kind: ArgumentKind.text, describes: 'the file it writes'),
          ArgumentSpec(
            name: 'content',
            kind: ArgumentKind.text,
            required: false,
            describes: 'what goes in it',
          ),
          ArgumentSpec(
            name: 'note',
            kind: ArgumentKind.text,
            required: false,
            describes: 'a second value the row fills from a measurement',
          ),
        ],
      },
      publishes: <String, List<MeasurementSpec>>{
        'measures': const <MeasurementSpec>[
          MeasurementSpec(
            name: backend,
            describes: 'what the machine says it filters packets with',
          ),
        ],
      },
    );

    test('a mis-wired row is named by its argument, not by a Dart cast', () {
      expect(
        () => ProgramResolver(registry()).resolve(
          programOf(
            'p',
            const <(String, OnFailure, List<String>)>[
              ('measures', OnFailure.exit, <String>[]),
              ('writes', OnFailure.exit, <String>[]),
            ],
            arguments: const <String, Arguments>{
              'writes': Arguments(<String, Object>{
                'path': '/etc/thing',
                'content': <String, Object?>{'answer': 'stage'},
              }),
            },
            reads: const <String, Map<String, MeasurementName>>{
              'writes': <String, MeasurementName>{'note': backend},
            },
          ),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid refusal) => refusal.message,
            'the refusal',
            allOf(
              contains('"content" holds text, and was given'),
              contains('declared as String but the program gave'),
              isNot(contains('is not a subtype of type')),
            ),
          ),
        ),
      );
    });
  });
}
