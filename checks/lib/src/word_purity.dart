/// word-purity — a tree names none of the words it is held away from.
///
/// A unit may know its TOOL and never an application of it. That rule cannot be checked by looking
/// at imports: the knowledge does not arrive as a dependency, where a reviewer would meet it in the
/// manifest. It arrives one word at a time, in a doc comment that explains a port by the tool the
/// author had in mind, and in a fixture that names a real thing because a real thing was handy. Both
/// read as illustration on the day they are written and as specification a year later.
///
/// So the scan is over every BYTE of the directories it is given — code, comment and fixture alike —
/// against a list of words held in a file. The list lives in a file rather than in this source
/// because a list written into a scanned file would be an occurrence of every word on it.
///
/// The directories scanned and the file the words come from are given by the caller: which words a
/// tree may not name is a property of that tree, and this is the mechanism rather than any one
/// tree's list.
library;

import 'dart:io';

import 'finding.dart';
import 'source_tree.dart';

/// The words a tree may not name, read from [wordListPath] under [root].
///
/// A blank line and a line beginning with `#` are not words. An absent file throws rather than
/// answering with an empty list: a scan for nothing finds nothing and reads exactly like a scan that
/// found nothing.
List<String> forbiddenWords(Directory root, String wordListPath) {
  final File file = File(
    <String>[root.path, ...wordListPath.split('/')].join(Platform.pathSeparator),
  );
  if (!file.existsSync()) {
    throw StateError(
      '$wordListPath is missing, so this check has nothing to search for and its silence would '
      'mean nothing',
    );
  }
  return <String>[
    for (final String line in linesOf(file.readAsStringSync()))
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line.trim(),
  ];
}

/// The files of [tree] that sit under one of [scannedPaths], sorted.
///
/// This is the denominator: a run in which it is empty scanned nothing, and its silence must not
/// read as agreement.
List<String> scannedFilesOf(SourceTree tree, List<String> scannedPaths) =>
    tree.files.keys.where((String path) => _isScanned(path, scannedPaths)).toList(growable: false)
      ..sort();

/// Every occurrence of a word of [words] under [scannedPaths] of [tree], one finding per line.
///
/// Matched case-insensitively, because the words appear as prose as often as identifiers, and
/// anchored on letters and digits, so a longer name that merely contains one is left alone.
///
/// The anchor is written out rather than left to `\b`, and the difference is the underscore. `\b`
/// counts it as part of a word, so a word followed by `_ADDR` would not match — and SCREAMING_SNAKE
/// is exactly where such a name arrives, because that is the shape of an environment variable.
/// Anything that is not a letter or a digit ends the word here, so `<word>_ADDR`, `<word>-addr` and
/// `<word>.addr` are each an occurrence, while `<word>ish` is not.
List<Finding> occurrencesOfForbiddenWords(
  SourceTree tree,
  List<String> words, {
  required List<String> scannedPaths,
}) {
  if (words.isEmpty) {
    return const <Finding>[];
  }
  final RegExp anyOfThem = RegExp(
    '(?<![A-Za-z0-9])(?:${words.map(RegExp.escape).join('|')})(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  final List<Finding> found = <Finding>[];
  for (final String path in scannedFilesOf(tree, scannedPaths)) {
    final String? text = tree.textOf(path);
    if (text == null) {
      continue;
    }
    final List<String> lines = linesOf(text);
    for (int i = 0; i < lines.length; i++) {
      if (anyOfThem.hasMatch(lines[i])) {
        found.add(Finding(path, lines[i].trim(), line: i + 1));
      }
    }
  }
  return found;
}

bool _isScanned(String path, List<String> scannedPaths) =>
    scannedPaths.any((String root) => path == root || path.startsWith('$root/'));
