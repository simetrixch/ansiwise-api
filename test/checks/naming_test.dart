import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'source_tree.dart';

/// naming — the abolished words appear in no name.
///
/// WHAT WAS ABOLISHED IS A PROGRAM NAME, NOT A VERB, and this distinction is the whole check. The
/// shell implementation this framework replaced had `install.sh` and `setup.sh`: two programs split
/// along a line nobody could name, which is how one of them came to do five unrelated things. The
/// verbs for our programs are `deploy` and `onboard`, and what is deployed or onboarded is named
/// after itself. So the two words are forbidden where a program or a sub-command is named, and
/// there only.
///
/// `install` as the name of what a command DOES is not abolished and must not be reported. A step
/// that runs `apt-get install` is called install_packages.dart because that is the word the
/// software itself uses, and the naming law of this project is to take that word rather than invent
/// one. A check that forbade the substring would rename the step to something that no longer says
/// what it runs — which is the failure this check exists to prevent, arriving from the other side.
///
/// THE ONE UNCONDITIONAL WORD IS `desktop`, in a file name, a directory name or a sub-command
/// alike. It is not a bad name, it is a false one: one client runs on web, on a phone, on a tablet
/// and on a laptop, so `desktop` states a platform the code inside it does not have. There is no
/// position in which that becomes true, so there is no position in which it is allowed.
///
/// A word can hide in three places a compiler never reads: a file name, a directory name, and the
/// string a sub-command answers to on the command line. Those are what this scans.
void main() {
  final SourceTree tree = SourceTree.on(repositoryRoot());
  final List<String> roots = rootsOf(tree);

  test('there are names to judge', () {
    expect(
      <String>[for (final String root in roots) ...tree.namesUnder(root)],
      isNotEmpty,
      reason: 'nothing was walked, so this check measured nothing',
    );
  });

  test('no file, directory or sub-command carries an abolished word', () {
    expect(
      <String>[
        for (final String root in roots) ...abolishedNamesUnder(tree, root),
        for (final String root in roots) ...abolishedSubCommandsUnder(tree, root),
      ],
      isEmpty,
      reason:
          'the verbs are deploy and onboard, and a step named for the command it runs keeps that '
          'name',
    );
  });

  group('counter-probe', () {
    // Both scans get a planted violation AND a correct neighbour, so a scan that reported
    // everything is caught as surely as one that reports nothing. The correct neighbours are the
    // point of this probe: install_packages.dart and deploy-host.yaml are exactly what a substring
    // match would eat, so they are what reports the check having been "simplified" back into one.

    final SourceTree planted = SourceTree.planted(<String, String>{
      'setup/whatever.dart': 'const int x = 1;',
      'lib/desktop/shell.dart': 'const int x = 2;',
      'install.sh': '#!/bin/sh',
      'programs/setup-cluster.yaml': 'name: p',
      'lib/deploy_host.dart': 'const int x = 3;',
      'lib/install_packages.dart': 'const int x = 4;',
      'programs/deploy-host.yaml': 'name: p',
      'lib/commands.dart': _plantedCommandSource,
    });
    final List<String> names = abolishedNamesUnder(planted, '');
    final List<String> commands = abolishedSubCommandsUnder(planted, '');

    for (final String path in <String>[
      'setup',
      'lib/desktop',
      'install.sh',
      'programs/setup-cluster.yaml',
    ]) {
      test('the planted name $path is reported', () {
        expect(
          names.where((String hit) => hit.startsWith('$path —')),
          isNotEmpty,
          reason: 'the name scan cannot go red',
        );
      });
    }

    for (final String path in <String>[
      'lib/deploy_host.dart',
      'lib/install_packages.dart',
      'programs/deploy-host.yaml',
    ]) {
      test('$path names the command it runs and is not reported', () {
        expect(
          names.where((String hit) => hit.startsWith('$path —')),
          isEmpty,
          reason: 'the name scan has collapsed back into a match on the substring',
        );
      });
    }

    for (final String name in _plantedCommands) {
      test("the planted sub-command '$name' is reported", () {
        expect(
          commands.where((String hit) => hit.endsWith(':$name')),
          isNotEmpty,
          reason: 'the sub-command scan cannot go red',
        );
      });
    }

    for (final String name in _allowedCommands) {
      test("the sub-command '$name' carries no abolished word and is not reported", () {
        expect(commands.where((String hit) => hit.endsWith(':$name')), isEmpty);
      });
    }
  });
}

/// What is scanned: tool/ and every Dart package.
///
/// The empty string is the whole tree, which is what the root package of this repository amounts
/// to. tool/ is named beside it for the tree where the gate's own programs sit outside every
/// package: a name an operator reads is a name an operator reads wherever the file lives.
List<String> rootsOf(SourceTree tree) => <String>['tool', ...tree.packages.keys];

/// Every file and directory name under [root] carrying an abolished word, as `<path> — <why>`.
///
/// Four rules. `desktop` is the only test on the substring, for the reason above; the other three
/// ask WHERE the name sits before they ask what it says, which is what keeps install_packages.dart
/// out of the findings. Every test is case-insensitive, because `Setup` is the same word wearing a
/// disguise.
List<String> abolishedNamesUnder(SourceTree tree, String root) {
  final List<String> found = <String>[];
  for (final String path in tree.namesUnder(root)) {
    final String name = p.posix.basename(path).toLowerCase();

    if (name.contains('desktop')) {
      found.add('$path — desktop names a platform the code does not have');
      continue;
    }

    if (tree.directories.contains(path)) {
      // A directory CALLED install or setup is the old split by another route: it collects whatever
      // somebody decided belongs to installing, which is the grouping that had no name.
      if (name == 'install' || name == 'setup') {
        found.add('$path — a directory named for the abolished program, not for what is in it');
      }
      continue;
    }

    // The two shell programs themselves, and a Dart file that would inherit their names.
    if (const <String>{'install.sh', 'setup.sh', 'install.dart', 'setup.dart'}.contains(name)) {
      found.add('$path — the abolished program name; the verbs are deploy and onboard');
      continue;
    }

    // A program file is one that lives in a programs/ directory: its name is what an operator picks
    // from a list, so it is named like a sub-command and judged like one.
    if (SourceTree.directoryOf(path).split('/').contains('programs') &&
        (name.startsWith('install') || name.startsWith('setup'))) {
      found.add('$path — a program named install/setup; the verbs are deploy and onboard');
    }
  }
  return found;
}

/// Every Dart sub-command under [root] whose name carries an abolished word, as
/// `<file>:<line>:<name>`.
///
/// A sub-command is declared in one of two shapes, and both are read out of the source rather than
/// guessed at: `parser.addCommand('deploy-host')` for a bare ArgParser, and `String get name =>
/// 'deploy-host'` for a Command subclass. A word that reaches the command line is what an operator
/// types and reads in help output, so it outlives every rename of the file behind it.
///
/// A sub-command is a program name, so `install`, `setup` and anything beginning with them is out.
/// `desktop` is out wherever it sits in the string.
List<String> abolishedSubCommandsUnder(SourceTree tree, String root) {
  final List<String> found = <String>[];
  for (final String path in tree.dartFiles) {
    if (root.isNotEmpty && path != root && !path.startsWith('$root/')) {
      continue;
    }
    final String? text = tree.textOf(path);
    if (text == null) {
      continue;
    }
    final List<String> lines = linesOf(text);
    for (int i = 0; i < lines.length; i++) {
      final RegExpMatch? match = _declaredCommand.firstMatch(lines[i]);
      if (match?.group(2) case final String name) {
        final String lower = name.toLowerCase();
        if (lower.startsWith('install') || lower.startsWith('setup') || lower.contains('desktop')) {
          found.add('$path:${i + 1}:$name');
        }
      }
    }
  }
  return found;
}

/// The name a sub-command answers to, in either of the two shapes it is declared in.
///
/// The literal is taken from immediately behind the marker rather than as the first quoted thing on
/// the line, so a line that carries the marker inside a string of its own — which is what the
/// counter-probe below writes — yields the string it actually declares.
final RegExp _declaredCommand = RegExp(r'''(?:addCommand\(\s*|get name\s*=>\s*)(['"])([^'"]*)\1''');

const List<String> _plantedCommands = <String>[
  'install',
  'install-cluster',
  'setup',
  'desktop-cli',
];
const List<String> _allowedCommands = <String>['deploy-cluster', 'onboard'];

/// The planted sub-command declarations, built by interpolation.
///
/// This file is itself scanned by the check it holds. Writing the planted names into the source
/// straight after a marker would declare them here, and the check would report itself; assembled
/// this way the marker on each template line yields the interpolation and not a forbidden name.
final String _plantedCommandSource = <String>[
  for (final String name in <String>[..._plantedCommands.take(2), _allowedCommands.first])
    "  String get name => '$name';",
  for (final String name in <String>[..._plantedCommands.skip(2), _allowedCommands.last])
    "    parser.addCommand('$name');",
].join('\n');
