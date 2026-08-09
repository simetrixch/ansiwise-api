import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import '../support/example_steps.dart';
import '../support/harness.dart';

/// A directory of program files is taken whole or not at all.
///
/// A deployment with one broken program is not half-usable: the program an operator reaches for is
/// the one that is missing, and nothing says so until they reach for it. So one bad file refuses
/// the directory, and the refusal names every bad file.
void main() {
  const String directory = 'deployment/programs';

  Registry registry() => registryOf(
    steps: <String, (String, Step Function(Arguments))>{
      'writes_a_file': (
        'lib/src/steps/file_step.dart:1',
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

  String program(String name, {String step = 'writes_a_file', String path = '/x'}) =>
      '''
name: $name
roles: [master]
steps:
  - step: $step
    path: $path
    on_failure: die
''';

  FakeFiles filesWith(Map<String, String> entries) => FakeFiles(<String, String>{
    for (final MapEntry<String, String> entry in entries.entries)
      '$directory/${entry.key}': entry.value,
  });

  Future<LoadedCatalogue> load(FakeFiles files) =>
      LoadedCatalogue.load(files: files, directory: directory, registry: registry());

  test('every file in the directory becomes a resolved program', () async {
    final LoadedCatalogue catalogue = await load(
      filesWith(<String, String>{
        'deploy-cluster.yaml': program('deploy-cluster'),
        'add-node.yaml': program('add-node'),
      }),
    );

    expect(catalogue.programs, hasLength(2));
    expect(
      catalogue.programs.map((ResolvedProgram p) => p.declared.name.value),
      <String>['add-node', 'deploy-cluster'],
      reason: 'the directory is read in a stable order, whatever order the port lists it in',
    );
  });

  test('a program is found by name, and an unknown name is null', () async {
    final LoadedCatalogue catalogue = await load(
      filesWith(<String, String>{'deploy-cluster.yaml': program('deploy-cluster')}),
    );

    final ResolvedProgram? found = catalogue.byName(const ProgramName('deploy-cluster'));
    expect(found?.steps.single.registered.source, 'lib/src/steps/file_step.dart:1');
    expect(catalogue.byName(const ProgramName('no-such-program')), isNull);
  });

  test('a file that is not YAML is left alone', () async {
    final LoadedCatalogue catalogue = await load(
      filesWith(<String, String>{
        'deploy-cluster.yaml': program('deploy-cluster'),
        'README.txt': 'this is not a program',
      }),
    );

    expect(catalogue.programs, hasLength(1));
  });

  test('an empty directory is an empty catalogue', () async {
    final LoadedCatalogue catalogue = await load(FakeFiles());

    expect(catalogue.programs, isEmpty);
  });

  test('one bad file refuses the whole directory, and the refusal names it', () async {
    expect(
      load(
        filesWith(<String, String>{
          'deploy-cluster.yaml': program('deploy-cluster'),
          'add-node.yaml': 'name: add-node\nroles: [master]\n',
        }),
      ),
      throwsA(
        isA<ProgramInvalid>()
            .having((ProgramInvalid e) => e.message, 'message', contains('add-node.yaml:'))
            .having((ProgramInvalid e) => e.message, 'message', contains('the file has no "steps"'))
            .having((ProgramInvalid e) => e.where, 'where', directory),
      ),
    );
  });

  test('every bad file is named, not just the first', () async {
    try {
      await load(
        filesWith(<String, String>{
          'a.yaml': 'name: a\nroles: [master]\n',
          'b.yaml': program('b', step: 'no_such_step'),
          'c.yaml': program('c'),
        }),
      );
      fail('the directory must be refused');
    } on ProgramInvalid catch (refused) {
      expect(refused.message, contains('a.yaml:'));
      expect(refused.message, contains('b.yaml:'));
      expect(refused.message, isNot(contains('c.yaml:')));
    }
  });

  test('a file the resolver refuses is reported under its own name', () async {
    try {
      await load(filesWith(<String, String>{'add-node.yaml': program('add-node', step: 'ghost')}));
      fail('the directory must be refused');
    } on ProgramInvalid catch (refused) {
      expect(refused.message, startsWith('add-node.yaml:'));
      expect(refused.message, contains('no step is registered under that name'));
    }
  });

  test(
    'two files claiming one program name are refused, because byName could not choose',
    () async {
      try {
        await load(
          filesWith(<String, String>{
            'first.yaml': program('deploy-cluster'),
            'second.yaml': program('deploy-cluster'),
          }),
        );
        fail('the directory must be refused');
      } on ProgramInvalid catch (refused) {
        expect(
          refused.message,
          contains('second.yaml: declares "deploy-cluster", and so does first.yaml'),
        );
      }
    },
  );
}
