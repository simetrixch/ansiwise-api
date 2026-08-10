/// The suite that holds one package's declaration against its own disk, counter-probe beside it.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../declared_checks.dart';
import '../finding.dart';

/// Where a package that also holds the ordinary tests of its own code keeps the files that judge it
/// as a package.
const String checksDirectory = 'test/checks';

/// Runs the declared-checks audit for the package the suite is running in.
///
/// `dart test` discovers whatever is on disk and reports whether any of it failed. Delete a check
/// file and NOTHING fails — the check is not there to fail — and the run goes on to say that every
/// check is green. It is worse than a missing test: a check and its counter-probe live in the same
/// file, so the thing that would have noticed goes with the thing it was watching.
///
/// WHAT IS DECLARED IS THE CHECKS AND NOT THE WHOLE SUITE. The ordinary tests of a package's own
/// code sit directly under `test/`; what judges the package as a package sits under [directory], and
/// that is what the declaration is held against.
///
/// WHAT IT STATES: how many checks the declaration names. An empty declaration agrees with an empty
/// suite, and both are green for nothing — so the count stands in the name of the test that asserts
/// the declaration is there at all.
///
/// The repository gate asks the one thing this cannot: whether the declaration and this reader are
/// there at all. It reads no declaration — nothing under a gate's tool/ may import a package — and
/// refuses to start when either file is missing.
void auditDeclaredChecks({String directory = checksDirectory}) {
  final File declaration = File('${Directory.current.path}/$checksFileName');
  // Read here rather than in a set-up, so the number of checks can stand in a test name. An absent
  // file reads as no checks at all, and the first assertion below is what says which of the two a
  // count of zero means.
  final List<DeclaredCheck> declared = declaration.existsSync()
      ? parseChecks(declaration.readAsStringSync())
      : const <DeclaredCheck>[];

  group('the declaration this package really carries', () {
    test('${declared.length} check(s) are declared, and the declaration is there', () {
      expect(
        declaration.existsSync(),
        isTrue,
        reason:
            'without it this package cannot say what it checks, and neither can anybody reading it',
      );
      expect(
        declared,
        isNotEmpty,
        reason: 'an empty declaration agrees with an empty suite, and both are green for nothing',
      );
    });

    test('agrees with the files on disk, in both directions', () {
      expect(
        disagreements(
          declared: declared,
          checkFilesOnDisk: checkFilesUnder(Directory.current, directory),
        ),
        isEmpty,
      );
    });

    test('gives every check a name and a file', () {
      for (final DeclaredCheck check in declared) {
        expect(check.name, isNotEmpty, reason: 'a refusal has to be able to name what vanished');
        expect(
          check.file,
          startsWith('$directory/'),
          reason: '$check does not name a file of the checks of this package',
        );
      }
    });
  });

  group('counter-probe', () {
    // The three shapes, or a green answer here means nothing: a check that vanished must be
    // reported, a check nobody agreed to must be reported, and a declaration that matches must be
    // left alone. Without the third, a reader that reported everything would pass the first two.

    const DeclaredCheck naming = DeclaredCheck(
      name: 'naming',
      file: '$checksDirectory/naming_test.dart',
    );

    test('a declared check whose file is gone is reported, by name', () {
      final List<Finding> found = disagreements(
        declared: <DeclaredCheck>[naming],
        checkFilesOnDisk: const <String>[],
      );
      expect(found, hasLength(1));
      expect(found.single.subject, '$checksDirectory/naming_test.dart');
      expect(
        found.single.what,
        contains('naming'),
        reason:
            'the name is what a person looks for; a count of missing files says something is wrong '
            'and not what',
      );
    });

    test('a check file nothing declares is reported too', () {
      final List<Finding> found = disagreements(
        declared: const <DeclaredCheck>[],
        checkFilesOnDisk: <String>['$checksDirectory/unagreed_test.dart'],
      );
      expect(found, hasLength(1));
      expect(found.single.subject, '$checksDirectory/unagreed_test.dart');
    });

    test('a declaration agreeing with the disk reports nothing', () {
      expect(
        disagreements(
          declared: <DeclaredCheck>[naming],
          checkFilesOnDisk: <String>['$checksDirectory/naming_test.dart'],
        ),
        isEmpty,
        reason: 'a reader that reported everything would pass the two probes above',
      );
    });

    test('a rename is reported from both sides rather than as one silent swap', () {
      expect(
        disagreements(
          declared: <DeclaredCheck>[naming],
          checkFilesOnDisk: <String>['$checksDirectory/name_test.dart'],
        ),
        hasLength(2),
        reason:
            'one half missing and the other unaccounted for; a single finding would let the reader '
            'think one file simply moved',
      );
    });
  });

  group('reading the declaration', () {
    test('comments and blank lines are not checks', () {
      expect(
        parseChecks('# a comment\n\n  # an indented comment\nnaming: test/naming_test.dart\n'),
        hasLength(1),
      );
    });

    test('the name and the file come off either side of the colon, trimmed', () {
      final DeclaredCheck check = parseChecks('  naming :  test/naming_test.dart  \n').single;
      expect(check.name, 'naming');
      expect(check.file, 'test/naming_test.dart');
    });

    test('a line with no colon is not half a check', () {
      expect(
        parseChecks('naming\n'),
        isEmpty,
        reason: 'a check with no file to point at would be declared and unfindable at once',
      );
    });
  });
}
