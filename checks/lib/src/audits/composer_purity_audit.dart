/// The suite that drives the composer scan over one tree, with the counter-probe beside it.
library;

import 'package:test/test.dart';

import '../composer_purity.dart';
import '../finding.dart';
import '../registry_completeness.dart';
import '../source_tree.dart';

/// Runs the composer-purity audit over [tree], or over the repository this suite sits in.
///
/// [executable] is the program name a command line starts with. The scan looks for it QUOTED, which
/// is how a Dart source writes it as the executable of a command or as a word of an argv list.
///
/// [composedIn] is the one file allowed to spell it: the composer that every other step asks. It is
/// an ARGUMENT rather than a name written here, because which file composes a tool is a property of
/// the package that owns the tool. A tree that holds no composer of its own still supplies it — the
/// rule it is held to is "every step file except the composer's own", and that sentence does not
/// change with whether the exempt file happens to sit in this tree or in the package this one
/// depends on. The counter-probe below drives the exemption over a tree it plants, so it is proven
/// either way.
///
/// WHAT IT STATES: how many step files were read. Without that number a scan that reached no step
/// at all reports exactly what a package whose steps all go through the composer reports.
void auditComposerPurity({
  required String executable,
  required String composedIn,
  SourceTree? tree,
}) {
  final SourceTree judged = tree ?? SourceTree.on(repositoryRoot());
  final List<String> read = stepFilesOf(judged);

  test('${read.length} step file(s) under $stepsDirectory/ were read', () {
    expect(
      read,
      isNotEmpty,
      reason:
          'no file under $stepsDirectory/ is in this tree, so nothing was searched for '
          "'$executable' and a pass here would mean nothing",
    );
  });

  test("no step spells the '$executable' invocation itself", () {
    expect(
      spelledInvocations(judged, executable: executable, composedIn: composedIn),
      isEmpty,
      reason:
          'each finding reads <file>:<line>, and the fix is to take the composer from the arguments '
          'and put the command line together through it, never to spell the invocation in the step',
    );
  });

  group('counter-probe', () {
    // Both directions, or the probe proves nothing: a planted invocation must be reported wherever
    // a step file can sit, and the same word in the composer, in prose, and outside the step
    // directory must be left alone.
    const String nested = '$stepsDirectory/nested';
    final SourceTree planted = SourceTree.planted(<String, String?>{
      'pubspec.yaml': 'name: planted_package\n',
      '$stepsDirectory/planted.dart': _spellsTheExecutable(executable),
      '$nested/planted.dart': _spellsTheExecutable(executable),
      '$stepsDirectory/planted_word.dart': _spellsItAmongOtherWords(executable),
      '$nested/planted_word.dart': _spellsItAmongOtherWords(executable),
      composedIn: _spellsTheExecutable(executable),
      '$stepsDirectory/only_says_it.dart': _namesItInProse(executable),
      'lib/src/domain/outside_the_steps.dart': _spellsTheExecutable(executable),
    });
    final List<Finding> reported = spelledInvocations(
      planted,
      executable: executable,
      composedIn: composedIn,
    );

    test('the exempt file sits inside the directory this scan reads', () {
      // A composer named outside the step directory would be skipped by the scan anyway, so the
      // exemption would never fire and the probe below would pass without measuring anything.
      expect(
        composedIn,
        startsWith('$stepsDirectory/'),
        reason:
            '$composedIn is not under $stepsDirectory/, so exempting it changes nothing and this '
            'audit does not hold the rule it states',
      );
    });

    for (final String path in <String>[
      '$stepsDirectory/planted.dart',
      '$nested/planted.dart',
      '$stepsDirectory/planted_word.dart',
      '$nested/planted_word.dart',
    ]) {
      test('a planted invocation in $path is reported', () {
        expect(
          about(reported, path),
          isNotEmpty,
          reason: 'this scan cannot go red there, so its silence about the real tree means nothing',
        );
      });
    }

    test('the composer itself is where the word belongs and is not reported', () {
      expect(
        about(reported, composedIn),
        isEmpty,
        reason:
            'the rule is "every step file except the composer\'s own", and a scan that reports the '
            'composer states a rule no package can hold',
      );
    });

    test('prose that names the tool without quoting it is not reported', () {
      expect(
        about(reported, '$stepsDirectory/only_says_it.dart'),
        isEmpty,
        reason:
            'a sentence about the tool is not an invocation of it, and reporting one would push '
            'the word out of the comments that explain the steps',
      );
    });

    test('a file outside $stepsDirectory/ is not reported', () {
      expect(
        about(reported, 'lib/src/domain/outside_the_steps.dart'),
        isEmpty,
        reason:
            'this scan judges step files, and reporting more than that is not the rule it holds',
      );
    });

    test('the count of step files leaves out what is not a step file', () {
      expect(
        stepFilesOf(planted),
        isNot(contains('lib/src/domain/outside_the_steps.dart')),
        reason: 'a denominator that counts files the scan never reads overstates what was covered',
      );
    });

    test('a finding names the line the invocation sits on', () {
      expect(
        about(reported, '$stepsDirectory/planted.dart').map((Finding hit) => hit.line),
        contains(2),
        reason: 'without the line the finding names a file of unknown length',
      );
    });
  });
}

/// A step that spells [executable] as the executable of a command, on its second line.
String _spellsTheExecutable(String executable) =>
    'Future<void> plantedApply(StepContext context) async =>\n'
    "    context.shell.run(const Command('$executable', <String>['status']));";

/// A step that spells [executable] as one word of an argv list among others.
///
/// The word sits after another word rather than first, because a tool reached through a wrapper is
/// spelled exactly that way and a scan anchored on the head of the list would step over it.
String _spellsItAmongOtherWords(String executable) =>
    "const List<String> plantedArgv = <String>['sudo', '$executable', 'status'];";

/// Prose that names [executable] without quoting it — the innocent case.
String _namesItInProse(String executable) =>
    '/// The client is $executable, and this sentence names it without quoting it.';
