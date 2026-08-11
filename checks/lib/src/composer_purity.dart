/// composer-purity — one file puts an invocation of a tool together, and no other step spells it.
///
/// A tool is reached through a composer: one class that knows how the executable is called, what its
/// arguments look like, and what its output means. Every other step asks that composer. The scan
/// here is what keeps that true, because nothing else can: a second step that spells the executable
/// itself compiles, passes its own tests, and is only found when the two spellings disagree about
/// which client to run or how to read what it answered.
///
/// WHAT IS LOOKED FOR is the QUOTED executable — the literal a Dart source writes when the word is
/// the executable of a command or a word of an argv list. Prose about the tool writes the name
/// without quotes, so it is left alone; a step has no reason to quote the word at all, which is why
/// a quoted mention inside a comment is reported and that is accepted.
///
/// WHERE IT LOOKS is the step directory of the tree, and nowhere else. The composer is a step file
/// too, so the one file allowed to spell the invocation is named by the caller and exempted by path.
///
/// The executable and the composer's path are given by the caller: WHICH tool a package composes and
/// WHERE is a property of that package, and this is the mechanism rather than any one package's
/// tool.
library;

import 'finding.dart';
import 'registry_completeness.dart';
import 'source_tree.dart';

/// The step files of [tree], sorted.
///
/// This is the denominator: a run in which it is empty read no step at all, and its silence must not
/// be read as a package whose steps go through the composer.
///
/// [stepsDirectory] is where a step class belongs and is not a second definition of it — the same
/// constant the registry check counts the tree against, so the two cannot disagree about which files
/// are steps.
List<String> stepFilesOf(SourceTree tree) => tree.dartFiles
    .where((String path) => path.startsWith('$stepsDirectory/'))
    .toList(growable: false);

/// Every quoted spelling of [executable] in a step file of [tree], except in [composedIn].
///
/// One finding per line, naming the line, so what an operator opens is the place rather than a file
/// of unknown length.
List<Finding> spelledInvocations(
  SourceTree tree, {
  required String executable,
  required String composedIn,
}) {
  final String quoted = "'$executable'";
  final List<Finding> reported = <Finding>[];
  for (final String path in stepFilesOf(tree)) {
    if (path == composedIn) {
      continue;
    }
    final List<String> lines = linesOf(tree.textOf(path) ?? '');
    for (int at = 0; at < lines.length; at += 1) {
      if (lines[at].contains(quoted)) {
        reported.add(
          Finding(
            path,
            "spells '$executable' itself — the composer in $composedIn is the one place an "
            'invocation of it is put together',
            line: at + 1,
          ),
        );
      }
    }
  }
  return reported;
}
