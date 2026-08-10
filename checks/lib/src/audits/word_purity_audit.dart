/// The suite that drives the word scan over one tree, with the counter-probe beside it.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../finding.dart';
import '../source_tree.dart';
import '../word_purity.dart';

/// Runs the word-purity audit over [tree], or over the repository this suite sits in.
///
/// [wordListPath] is the file, relative to the tree root, that holds the words. It is a FILE and not
/// a constant, because this audit has to name what it forbids in order to search for it: a list
/// written into a scanned source would be an occurrence of every word on it.
///
/// [scannedPaths] are the directories read to the byte — code, comment and fixture alike. They are
/// named one at a time by the caller rather than derived as "the tree minus its tools", so adding a
/// directory to the scan is a decision somebody makes rather than a silent widening. The directory
/// holding the word list is not among them, and a counter-probe below says so.
///
/// [theRule] is the sentence the verdict is stated in, because what a tree may not name differs with
/// what the tree is.
///
/// WHAT IT STATES: how many words are searched for and how many files were read. An empty list scans
/// for nothing and would pass over any tree at all; an empty file set means the scan looked nowhere.
void auditWordPurity({
  required String wordListPath,
  required List<String> scannedPaths,
  required String theRule,
  SourceTree? tree,
}) {
  final Directory root = repositoryRoot();
  final List<String> forbidden = forbiddenWords(root, wordListPath);
  final SourceTree judged = tree ?? SourceTree.on(root);
  final List<String> scanned = scannedFilesOf(judged, scannedPaths);
  final String where = scannedPaths.join(', ');
  // The probes below plant into the FIRST scanned directory rather than into a name written out
  // here, so a caller that scans somewhere else still has its own scan driven rather than a
  // directory this file happened to assume.
  final String firstScanned = scannedPaths.first;

  test('${forbidden.length} word(s) are searched for, read from $wordListPath', () {
    expect(
      forbidden,
      isNotEmpty,
      reason:
          '$wordListPath is the whole of what this check looks for; an empty list scans for nothing '
          'and would pass over any tree at all',
    );
  });

  test('${scanned.length} file(s) under $where were read', () {
    expect(
      scanned,
      isNotEmpty,
      reason: 'none of $where is in this tree, so a pass here would mean nothing',
    );
  });

  test('$theRule, in $where', () {
    expect(
      occurrencesOfForbiddenWords(judged, forbidden, scannedPaths: scannedPaths),
      isEmpty,
      reason:
          'each finding reads <file>:<line> — <text>, and the fix is to demote the name into a '
          'value whose caller supplies it, never to take the word off the list',
    );
  });

  group('counter-probe', () {
    // A check that cannot go red proves nothing about the tree it passes on, so the same scan runs
    // again over trees this audit writes, carrying the violations it must report and the innocent
    // neighbours it must leave alone.

    test('every word on the list is reported where it is planted', () {
      for (final String word in forbidden) {
        expect(
          _reportedIn(
            <String, String>{
              '$firstScanned/planted.dart': '/// Runs $word on the way to the target state.',
            },
            forbidden,
            scannedPaths,
          ),
          hasLength(1),
          reason:
              "a planted occurrence of '$word' was not reported, so this scan cannot go red on a "
              'word it claims to forbid',
        );
      }
    });

    test('a word buried inside a longer one is not an occurrence of it', () {
      for (final String word in forbidden) {
        expect(
          _reportedIn(
            <String, String>{
              '$firstScanned/innocent.dart': "const String value = 'before${word}after';",
            },
            forbidden,
            scannedPaths,
          ),
          isEmpty,
          reason:
              "the word-anchoring is gone: 'before${word}after' was read as an occurrence of "
              "'$word', which would forbid names this tree may legitimately use",
        );
      }
    });

    test('an underscore ends the word, so a SCREAMING_SNAKE name is not a hiding place', () {
      // The shape this closes: an environment variable, a shell-ish constant, a fixture key. `\b`
      // would count the underscore as part of the word and pass over every one of them, so the
      // scan's answer would rest on which separator the author happened to type.
      for (final String word in forbidden) {
        for (final String planted in <String>['${word}_addr', 'the_$word', '$word-addr']) {
          expect(
            _reportedIn(
              <String, String>{'$firstScanned/planted.dart': "const String value = '$planted';"},
              forbidden,
              scannedPaths,
            ),
            hasLength(1),
            reason:
                "'$planted' names '$word' as plainly as the bare word does, and was not reported",
          );
        }
      }
    });

    // Every scanned directory gets its own planted file, deep inside it, so a scan that quietly
    // stopped reading one of them is reported rather than covered by the others.
    for (final String directory in scannedPaths) {
      test('a file deep under $directory/ is reported, so no exempt path has grown back', () {
        expect(
          _reportedIn(
            <String, String>{'$directory/src/deep/planted.dart': _everyWordIn(forbidden)},
            forbidden,
            scannedPaths,
          ),
          isNotEmpty,
        );
      });
    }

    test(
      'the directory holding the word list is not scanned, or this check would report itself',
      () {
        final String harness = SourceTree.directoryOf(wordListPath);
        expect(
          _reportedIn(
            <String, String>{
              wordListPath: _everyWordIn(forbidden),
              '$harness/planted.dart': _everyWordIn(forbidden),
            },
            forbidden,
            scannedPaths,
          ),
          isEmpty,
          reason:
              '$harness holds the word list, which has to name what it forbids; scanning it makes '
              'this check impossible to pass',
        );
      },
    );
  });
}

List<Finding> _reportedIn(
  Map<String, String> files,
  List<String> forbidden,
  List<String> scannedPaths,
) => occurrencesOfForbiddenWords(SourceTree.planted(files), forbidden, scannedPaths: scannedPaths);

/// A file body naming every word of [words], built at run time so this source carries none of them.
String _everyWordIn(List<String> words) =>
    words.map((String word) => '/// It reaches for $word.').join('\n');
