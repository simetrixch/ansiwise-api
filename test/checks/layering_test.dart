import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:ansiwise_checks_tree/ansiwise_checks_tree.dart';

/// layering — no import points outward.
///
/// Two directions have to hold, and neither is visible in a diff that adds one import line.
///
/// INSIDE a package, by directory name: presentation depends on application depends on domain, and
/// infrastructure depends on domain. domain is what the system is; it may reach nothing. The moment
/// domain imports infrastructure the arrow reverses: the thing that was meant to be testable
/// without a machine now needs one, and every test above it drags a real process along.
///
/// ACROSS packages: everything may depend on this framework and it may depend on nothing of this
/// workspace. It is meant to be lifted into a repository of its own, and one import of a sibling
/// ends that. The rule is derived from each package's own manifest rather than from a list here, so
/// a package that lands later is covered on the day it lands rather than on the day somebody
/// remembers to add it.
///
/// A directory that names none of the four layers — the engine, the model, the step catalogue — is
/// not judged: the rule is about the four names, and inventing a fifth arrow here would be a rule
/// nobody wrote down.
///
/// Only the layer half is measurable in this repository, which holds one package. The cross-package
/// half is driven by the counter-probe over a planted workspace of two.
void main() {
  final SourceTree tree = SourceTree.on(repositoryRoot());

  test('there are files under a layer directory to judge', () {
    expect(
      tree.dartFiles.where((String path) => layerOf(path) != null),
      isNotEmpty,
      reason:
          'no file sits under a ${layerNames.join('/, ')}/ directory, so the layer half of this '
          'check bound to nothing and an empty derivation must not read as agreement',
    );
  });

  test('no import points outward', () {
    expect(
      outwardImportsIn(tree),
      isEmpty,
      reason:
          'each finding reads <importing file>: imports <uri> — <why>; the fix is to move the '
          'thing being imported down, not to widen the arrow',
    );
  });

  group('counter-probe', () {
    // Both halves get their own probe, and each proves both directions — a scan that reported every
    // import would satisfy the red half alone.

    final SourceTree planted = SourceTree.planted(<String, String>{
      '$apiDirectoryName/pubspec.yaml': 'name: ansiwise_api\n',
      'a_plugin/pubspec.yaml': 'name: a_plugin\n',
      '$apiDirectoryName/lib/src/domain/reaches_out.dart':
          "import '../infrastructure/real_shell.dart';",
      '$apiDirectoryName/lib/src/domain/stays_in.dart': "import 'reaches_out.dart';",
      '$apiDirectoryName/lib/src/infrastructure/real_shell.dart':
          "import '../domain/stays_in.dart';",
      '$apiDirectoryName/lib/src/domain/pulls_a_plugin.dart':
          "import 'package:a_plugin/steps.dart';",
      'a_plugin/lib/steps.dart': "import 'package:ansiwise_api/ansiwise_api.dart';",
    });
    final List<String> reported = outwardImportsIn(planted);

    for (final String path in <String>['domain/reaches_out.dart', 'domain/pulls_a_plugin.dart']) {
      test('the planted violation in $path is reported', () {
        expect(
          reported.where((String hit) => hit.contains('$path: imports')),
          isNotEmpty,
          reason: 'this scan cannot go red, so its silence about the real tree means nothing',
        );
      });
    }

    for (final String path in <String>[
      'domain/stays_in.dart',
      'infrastructure/real_shell.dart',
      'a_plugin/lib/steps.dart',
    ]) {
      test('$path follows the arrow and is not reported', () {
        expect(
          reported.where((String hit) => hit.contains('$path: imports')),
          isEmpty,
          reason: 'this scan refuses correct code',
        );
      });
    }

    test('both packages of the planted workspace were found', () {
      expect(
        planted.packages.values,
        containsAll(<String>['ansiwise_api', 'a_plugin']),
        reason:
            'the cross-package half reads the name out of each manifest; with a package missing it '
            'would judge nothing and report nothing',
      );
    });
  });
}

/// The directory this framework's package sits in.
///
/// The cross-package rule names a directory rather than a package, because it is about which
/// repository a thing can be lifted into.
const String apiDirectoryName = 'ansiwise-api';

/// The four layer names, innermost last.
const List<String> layerNames = <String>['presentation', 'application', 'infrastructure', 'domain'];

/// Which layer may import which. A layer always imports itself.
const Map<String, Set<String>> layerMayImport = <String, Set<String>>{
  'domain': <String>{'domain'},
  'application': <String>{'application', 'domain'},
  'presentation': <String>{'presentation', 'application', 'domain'},
  'infrastructure': <String>{'infrastructure', 'domain'},
};

/// The layer [path] sits in, or null.
///
/// The LAST layer-named segment wins, so a file under lib/src/domain/ is domain even when the
/// package directory happens to carry a layer word.
String? layerOf(String path) {
  String? layer;
  for (final String segment in path.split('/')) {
    if (layerNames.contains(segment)) {
      layer = segment;
    }
  }
  return layer;
}

/// Every import that points outward in [tree], as `<importing file>: imports <uri> — <why>`.
List<String> outwardImportsIn(SourceTree tree) {
  final String? apiPackage = _apiPackageOf(tree);
  final List<String> found = <String>[];

  for (final String file in tree.dartFiles) {
    final String? text = tree.textOf(file);
    if (text == null) {
      continue;
    }
    final String? sourcePackage = _packageOfFile(tree, file);
    final String? sourceLayer = layerOf(file);

    for (final String uri in importUrisIn(text)) {
      // The SDK carries no layer and is not a package of this workspace.
      if (uri.startsWith('dart:')) {
        continue;
      }

      final String targetPackage;
      final String target;
      if (uri.startsWith('package:')) {
        final String rest = uri.substring('package:'.length);
        final int slash = rest.indexOf('/');
        if (slash < 0) {
          continue;
        }
        targetPackage = rest.substring(0, slash);
        final String? directory = _directoryOfPackage(tree, targetPackage);
        // A package name this workspace does not know is a third-party dependency: it has no layers
        // here and no arrow to point the wrong way.
        if (directory == null) {
          continue;
        }
        target = p.posix.normalize(p.posix.join(directory, 'lib', rest.substring(slash + 1)));
      } else {
        targetPackage = sourcePackage ?? '';
        // The target of an import may not exist — a broken import is the analyzer's finding, not
        // this one — so the path is collapsed textually and never resolved against the tree.
        target = p.posix.normalize(p.posix.join(SourceTree.directoryOf(file), uri));
      }

      // The framework's SHIPPED library may import no other package of this workspace. Its test
      // tree may: a test is carried onto no machine, so an import there drags a package along for
      // nobody — and the audits a check is written against are a package of their own for the
      // reason the exec-confinement rule states, that they walk files and the shipped library may
      // not. The arrow this rule exists to protect is the one that TRAVELS, and that one is
      // unchanged.
      if (apiPackage != null &&
          sourcePackage == apiPackage &&
          targetPackage != apiPackage &&
          _shipsWithTheLibrary(file)) {
        found.add(
          '$file: imports $uri — the shipped library of $apiPackage may import no other package of '
          'this workspace',
        );
        continue;
      }

      final String? targetLayer = layerOf(target);
      if (sourceLayer == null || targetLayer == null) {
        continue;
      }
      if (!(layerMayImport[sourceLayer] ?? const <String>{}).contains(targetLayer)) {
        found.add('$file: imports $uri — $sourceLayer may not import $targetLayer');
      }
    }
  }
  return found;
}

/// The import and export URIs in [text].
///
/// `part` is not read: a part is the same library as its parent and cannot cross a boundary the
/// parent has not already crossed.
List<String> importUrisIn(String text) => <String>[
  for (final String line in linesOf(text))
    if (_importLine.firstMatch(line) case final RegExpMatch match)
      if (match.group(2) case final String uri) uri,
];

final RegExp _importLine = RegExp(r'''^\s*(?:import|export)\s+(['"])([^'"]+)\1''');

/// Whether [file] is part of what a package depending on this one receives.
///
/// Only `lib/` is. Everything else — the tests, the entry point, the gate's own programs — stays in
/// the repository and reaches nothing that depends on it, which is why the cross-package rule
/// asks this before it reports.
bool _shipsWithTheLibrary(String file) =>
    file == 'lib' || file.startsWith('lib/') || file.contains('/lib/');

/// The package name of the package [tree] holds in a directory called [apiDirectoryName].
String? _apiPackageOf(SourceTree tree) {
  for (final MapEntry<String, String> package in tree.packages.entries) {
    final String directory = package.key.isEmpty ? tree.rootName : p.posix.basename(package.key);
    if (directory == apiDirectoryName) {
      return package.value;
    }
  }
  return null;
}

/// The package [file] belongs to: the package directory that is the longest prefix of its path.
///
/// Longest, because a package may sit inside another package's tree.
String? _packageOfFile(SourceTree tree, String file) {
  String? best;
  int bestLength = -1;
  for (final MapEntry<String, String> package in tree.packages.entries) {
    final bool holdsIt = package.key.isEmpty || file.startsWith('${package.key}/');
    if (holdsIt && package.key.length > bestLength) {
      best = package.value;
      bestLength = package.key.length;
    }
  }
  return best;
}

String? _directoryOfPackage(SourceTree tree, String name) {
  for (final MapEntry<String, String> package in tree.packages.entries) {
    if (package.value == name) {
      return package.key;
    }
  }
  return null;
}
