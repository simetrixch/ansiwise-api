/// The suite that drives [DirectiveCase] over one tree, with the counter-probe beside it.
library;

import 'package:test/test.dart';

import '../directive_case.dart';
import '../finding.dart';
import '../source_tree.dart';

/// Runs the case-sensitivity audit over [tree], or over the repository this suite sits in.
///
/// WHAT IT STATES: how many directives of this tree it resolved. That count is the denominator — a
/// tree in which no directive names a file of the tree is a tree this audit decided nothing about,
/// and its silence must not read as agreement.
///
/// THE TREE IS THE PACKAGE'S OWN. A scan rooted at the product that composes several packages would
/// not see one file of them: their sources are a dependency there, resolved from a pin or a
/// checkout, and neither is a path of that tree. So every package runs this over the tree it is.
void auditCaseSensitivity({SourceTree? tree}) {
  final DirectiveCase check = DirectiveCase(tree ?? SourceTree.on(repositoryRoot()));
  final int judged = check.directivesJudged.length;

  test('$judged directive(s) of this tree were resolved and compared', () {
    expect(
      check.directivesJudged,
      isNotEmpty,
      reason: 'no directive names a file of this tree, so this check measured nothing',
    );
  });

  test('every directive spells the on-disk name byte for byte', () {
    expect(
      check.findings,
      isEmpty,
      reason:
          'each finding reads <file>:<line> — <uri> — on disk it is <path>; the fix is to spell the '
          'directive exactly as the listing does, because on Linux the wrong case does not open',
    );
  });

  group('counter-probe', () {
    // A check that cannot go red proves nothing, so the same scan runs over planted trees carrying
    // the mismatch it must report and the exact spelling it must leave alone.

    test('an import whose case differs from the on-disk name is reported', () {
      final List<Finding> reported = _reportedIn(<String, String>{
        'lib/src/steps/planted.dart': 'const int x = 1;',
        'lib/wrong.dart': "import 'src/steps/Planted.dart';",
      });
      expect(reported, hasLength(1), reason: 'this scan cannot go red on the defect it exists for');
      expect(
        reported.single.what,
        contains('lib/src/steps/planted.dart'),
        reason: 'a finding that does not name the on-disk spelling leaves the fix to a guess',
      );
    });

    test('an import that matches byte for byte is not reported', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/steps/planted.dart': 'const int x = 1;',
          'lib/right.dart': "import 'src/steps/planted.dart';",
        }),
        isEmpty,
        reason: 'this scan refuses correct code',
      );
    });

    test('a directory segment with the wrong case is reported', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/steps/planted.dart': 'const int x = 1;',
          'lib/wrong.dart': "import 'src/Steps/planted.dart';",
        }),
        hasLength(1),
        reason:
            'the whole resolved path is compared, not the file name alone; a directory opened under '
            'the wrong case fails on Linux exactly like a file',
      );
    });

    test('a relative path that climbs is resolved before it is compared', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/steps/planted.dart': 'const int x = 1;',
          'lib/src/other/wrong.dart': "import '../steps/Planted.dart';",
        }),
        hasLength(1),
      );
    });

    test('a package: import of a package of this tree is judged like a relative one', () {
      final List<Finding> reported = _reportedIn(<String, String>{
        'pubspec.yaml': 'name: planted\n',
        'lib/src/registry.dart': 'const int x = 1;',
        'lib/wrong.dart': "import 'package:planted/src/Registry.dart';",
        'lib/right.dart': "import 'package:planted/src/registry.dart';",
      });
      expect(reported, hasLength(1));
      expect(reported.single.subject, 'lib/wrong.dart');
    });

    test('an export and a part are judged like an import', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/planted.dart': 'const int x = 1;',
          'lib/exports.dart': "export 'src/Planted.dart';",
          'lib/parent.dart': "part 'src/Planted.dart';",
        }),
        hasLength(2),
        reason: 'an export and a part resolve a file exactly as an import does',
      );
    });

    test('a part of naming its parent with the wrong case is reported', () {
      expect(
        _reportedIn(<String, String>{
          'lib/parent.dart': "part 'child.dart';",
          'lib/child.dart': "part of 'Parent.dart';",
        }),
        hasLength(1),
        reason: 'the child names its parent on its own, so the parent directive does not cover it',
      );
    });

    test('a finding names the line the directive sits on', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/planted.dart': 'const int x = 1;',
          'lib/wrong.dart': "// a first line\nimport 'src/Planted.dart';",
        }).single.line,
        2,
        reason: 'a finding without a line names a file of unknown length',
      );
    });

    test('an import of a file that is on disk under no spelling is not a finding here', () {
      expect(
        _reportedIn(<String, String>{'lib/broken.dart': "import 'src/steps/not_there.dart';"}),
        isEmpty,
        reason: 'that import is broken on every platform, and the analyzer reports it',
      );
    });

    test('dart: and third-party package: imports are not judged', () {
      final DirectiveCase planted = DirectiveCase(
        SourceTree.planted(<String, String>{
          'lib/uses_others.dart':
              "import 'dart:io';\n"
              "import 'package:ansiwise_api/ansiwise_api.dart';",
        }),
      );
      expect(planted.directivesJudged, isEmpty);
      expect(planted.findings, isEmpty);
    });

    test('a file that is not text carries no directive to resolve', () {
      expect(
        DirectiveCase(
          SourceTree.planted(<String, String?>{
            'lib/src/planted.dart': 'const int x = 1;',
            'assets/logo.png': null,
          }),
        ).findings,
        isEmpty,
      );
    });
  });
}

List<Finding> _reportedIn(Map<String, String> files) =>
    DirectiveCase(SourceTree.planted(files)).findings;
