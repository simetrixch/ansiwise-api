import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// A program that does not add up is refused before anything is looked at.
///
/// This is where the safety a compiler cannot give across a configuration boundary is restored. A
/// program file hands a step some values and nothing about that is checked at build time; it is
/// checked here instead, and everything wrong with it is said at once.
void main() {
  Registry registry() => registryOf(
    steps: <String, (String, Step Function(Arguments))>{
      'writes_a_file': (
        'x:1',
        (Arguments a) => WritesAFile(path: a.text('path'), content: a.text('content')),
      ),
    },
    arguments: <String, List<ArgumentSpec>>{
      'writes_a_file': const <ArgumentSpec>[
        ArgumentSpec(name: 'path', kind: ArgumentKind.text, describes: 'the file to write'),
        ArgumentSpec(
          name: 'content',
          kind: ArgumentKind.text,
          describes: 'what goes in it',
          required: false,
          defaultValue: '',
        ),
      ],
    },
    predicates: <String, Predicate>{
      'is_master': const Says(answer: true, because: 'the role is master'),
    },
  );

  test('an unknown step name is refused', () {
    expect(
      () => ProgramResolver(registry()).resolve(
        programOf('p', <(String, OnFailure, List<String>)>[
          ('no_such_step', OnFailure.die, <String>[]),
        ]),
      ),
      throwsA(
        isA<ProgramInvalid>().having(
          (ProgramInvalid e) => e.message,
          'message',
          contains('no step is registered under that name'),
        ),
      ),
    );
  });

  test('an unknown predicate name is refused', () {
    expect(
      () => ProgramResolver(registry()).resolve(
        programOf(
          'p',
          <(String, OnFailure, List<String>)>[
            ('writes_a_file', OnFailure.die, <String>['no_such_condition']),
          ],
          arguments: <String, Arguments>{
            'writes_a_file': const Arguments(<String, Object>{'path': '/x'}),
          },
        ),
      ),
      throwsA(
        isA<ProgramInvalid>().having(
          (ProgramInvalid e) => e.message,
          'message',
          contains('no predicate is registered under "no_such_condition"'),
        ),
      ),
    );
  });

  test('a missing required argument is refused, and the message says what it is for', () {
    expect(
      () => ProgramResolver(registry()).resolve(
        programOf('p', <(String, OnFailure, List<String>)>[
          ('writes_a_file', OnFailure.die, <String>[]),
        ]),
      ),
      throwsA(
        isA<ProgramInvalid>().having(
          (ProgramInvalid e) => e.message,
          'message',
          contains('needs the argument "path" — the file to write'),
        ),
      ),
    );
  });

  test('an argument the step does not have is refused', () {
    expect(
      () => ProgramResolver(registry()).resolve(
        programOf(
          'p',
          <(String, OnFailure, List<String>)>[('writes_a_file', OnFailure.die, <String>[])],
          arguments: <String, Arguments>{
            'writes_a_file': const Arguments(<String, Object>{'path': '/x', 'colour': 'blue'}),
          },
        ),
      ),
      throwsA(
        isA<ProgramInvalid>().having(
          (ProgramInvalid e) => e.message,
          'message',
          contains('has no argument "colour"'),
        ),
      ),
    );
  });

  test('a value of the wrong kind is refused', () {
    expect(
      () => ProgramResolver(registry()).resolve(
        programOf(
          'p',
          <(String, OnFailure, List<String>)>[('writes_a_file', OnFailure.die, <String>[])],
          arguments: <String, Arguments>{
            'writes_a_file': const Arguments(<String, Object>{'path': 7}),
          },
        ),
      ),
      throwsA(
        isA<ProgramInvalid>().having(
          (ProgramInvalid e) => e.message,
          'message',
          contains('"path" holds text, and was given int'),
        ),
      ),
    );
  });

  test('every problem is reported at once, not one run at a time', () {
    try {
      ProgramResolver(registry()).resolve(
        programOf('p', <(String, OnFailure, List<String>)>[
          ('no_such_step', OnFailure.die, <String>[]),
          ('writes_a_file', OnFailure.die, <String>['no_such_condition']),
        ]),
      );
      fail('the program must be refused');
    } on ProgramInvalid catch (refusal) {
      expect(refusal.message, contains('no step is registered'));
      expect(refusal.message, contains('needs the argument "path"'));
      expect(refusal.message, contains('no predicate is registered'));
      expect(refusal.message.split('\n'), hasLength(3));
    }
  });

  test('a program that adds up resolves, and a default fills in', () async {
    final ResolvedProgram program = ProgramResolver(registry()).resolve(
      programOf(
        'p',
        <(String, OnFailure, List<String>)>[
          ('writes_a_file', OnFailure.die, <String>['is_master']),
        ],
        arguments: <String, Arguments>{
          'writes_a_file': const Arguments(<String, Object>{'path': '/x'}),
        },
      ),
    );

    expect(program.steps.single.registered.source, 'x:1');
    expect(program.steps.single.when.single.name.value, 'is_master');

    final Harness h = Harness();
    await h.runner.run(program: program, mode: Mode.run, header: h.header());
    expect(h.files.contents['/x'], '', reason: 'the declared default stood in');
  });
}
