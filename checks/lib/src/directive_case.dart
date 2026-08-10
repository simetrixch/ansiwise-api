/// directive-case — every directive spells the on-disk file name byte for byte.
///
/// `import 'Foo.dart'` for a file named `foo.dart` compiles on Windows and fails on Linux, which is
/// the machine every step runs against and the machine the binary is compiled for. Nothing else
/// catches it: the analyzer resolves the import through the filesystem, and the Windows filesystem
/// opens the wrong case without complaint. For the same reason a check that asked whether the file
/// opens would be green on Windows and prove nothing. The comparison is against the DIRECTORY
/// LISTING instead: [SourceTree.on] walks the tree by listing it, so its paths carry each name as
/// the disk spells it, and every directive's resolved path is compared to them byte for byte.
///
/// What is judged is every `import`, `export`, `part` and `part of` directive whose target is a file
/// of the tree it is given — relative, or `package:` of a package that tree holds. `dart:` names no
/// file, and a package outside the tree resolves through the pub cache, whose spelling is pub's and
/// not this repository's.
///
/// A directive whose target is on disk under NO spelling is not a finding: that import is broken on
/// every platform, and the analyzer reports it.
///
/// EVERY PACKAGE RUNS THIS OVER ITS OWN TREE. The audit takes a tree, so a package that is a
/// dependency of another is judged where its files are — a scan rooted at the product would skip
/// every file of the four packages under it, because their sources are not in its tree at all.
library;

import 'package:path/path.dart' as p;

import 'finding.dart';
import 'source_tree.dart';

/// The scan itself, over a tree it is given rather than over the repository it lives in.
final class DirectiveCase {
  /// Judges the directives of [tree].
  const DirectiveCase(this.tree);

  /// The tree being judged.
  final SourceTree tree;

  /// Every directive of the tree that names a file of it under some spelling, as `<file>: <uri>`.
  ///
  /// This is the denominator: a run in which it is empty judged nothing, and its silence must not
  /// read as agreement.
  List<String> get directivesJudged {
    final Map<String, String> listing = _byLowerCase();
    return <String>[
      for (final _Directive directive in _directives)
        if (listing.containsKey(directive.target.toLowerCase()))
          '${directive.file}: ${directive.uri}',
    ];
  }

  /// Every directive whose spelling differs from the on-disk name.
  ///
  /// The finding names the line it sits on and the spelling the listing carries, which is the fix.
  List<Finding> get findings {
    final Map<String, String> listing = _byLowerCase();
    final List<Finding> found = <Finding>[];
    for (final _Directive directive in _directives) {
      if (tree.files.containsKey(directive.target)) {
        continue;
      }
      final String? actual = listing[directive.target.toLowerCase()];
      if (actual == null) {
        continue;
      }
      found.add(
        Finding(directive.file, '${directive.uri} — on disk it is $actual', line: directive.line),
      );
    }
    return found;
  }

  /// The files of the tree, keyed by their lower-cased path.
  ///
  /// Lower-casing both sides is what makes "same file, different spelling" one lookup; the value
  /// keeps the spelling the listing carries, which is what a finding names as the fix.
  Map<String, String> _byLowerCase() => <String, String>{
    for (final String path in tree.files.keys) path.toLowerCase(): path,
  };

  /// Every directive of every Dart file of the tree whose URI can name a file of this tree.
  Iterable<_Directive> get _directives sync* {
    for (final String file in tree.dartFiles) {
      final String? text = tree.textOf(file);
      if (text == null) {
        continue;
      }
      final List<String> lines = linesOf(text);
      for (int i = 0; i < lines.length; i++) {
        final String? uri = _directiveLine.firstMatch(lines[i])?.group(2);
        if (uri == null) {
          continue;
        }
        final String? target = _targetOf(file, uri);
        if (target != null) {
          yield _Directive(file: file, line: i + 1, uri: uri, target: target);
        }
      }
    }
  }

  /// The tree-relative path [uri] names from [file], or null when it names no file of this tree.
  String? _targetOf(String file, String uri) {
    if (uri.startsWith('dart:')) {
      return null;
    }
    if (uri.startsWith('package:')) {
      final String rest = uri.substring('package:'.length);
      final int slash = rest.indexOf('/');
      if (slash < 0) {
        return null;
      }
      final String? directory = _directoryOfPackage(rest.substring(0, slash));
      if (directory == null) {
        // A package name this tree does not declare resolves through the pub cache, whose spelling
        // is pub's and not this repository's.
        return null;
      }
      return p.posix.normalize(p.posix.join(directory, 'lib', rest.substring(slash + 1)));
    }
    return p.posix.normalize(p.posix.join(SourceTree.directoryOf(file), uri));
  }

  String? _directoryOfPackage(String name) {
    for (final MapEntry<String, String> package in tree.packages.entries) {
      if (package.value == name) {
        return package.key;
      }
    }
    return null;
  }
}

/// One directive, resolved to the tree-relative path it names.
final class _Directive {
  const _Directive({
    required this.file,
    required this.line,
    required this.uri,
    required this.target,
  });

  final String file;
  final int line;
  final String uri;
  final String target;
}

/// The one URI-carrying shape of each directive kind, matched at the start of a line.
///
/// `part of` is tried before bare `part`, so the URI taken is the one behind the whole marker. The
/// line anchor is also what keeps a counter-probe from reporting itself: a directive planted as a
/// string literal sits behind a quote, never at the start of a line.
final RegExp _directiveLine = RegExp(
  r'''^\s*(?:import|export|part\s+of|part)\s+(['"])([^'"]+)\1''',
);
