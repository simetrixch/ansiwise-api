import 'package:ansiwise_checks/audits.dart';

/// api-purity — this framework names no platform, anywhere, with no exemption.
///
/// ansiwise-api is a step engine, three modes, a run record and four ports. It knows how to run a
/// declared program against a machine and nothing whatever about what is being deployed. Everything
/// of that kind lives in a plugin, in a repository of its own, and the dependency points one way.
///
/// So the scan is over every byte of [scanned] and not over its imports. THERE IS NO EXEMPT
/// DIRECTORY among them: lib/, test/, bin/ and programs/ are read to the byte, and a hit is a hit
/// wherever it is.
///
/// tool/ is not scanned, and that is the harness rather than a loophole. This check has to name the
/// words it forbids in order to search for them, and nothing under tool/ is compiled into the
/// framework or shipped with it. It is also why the list is a file there rather than a constant
/// here: a list written into a scanned file would be an occurrence of every word on it.
///
/// It is the SAME audit the plugins run against their own word lists, which is what keeps the rule
/// one rule: a framework that may name no platform and a plugin that may name no application of its
/// tool are the same scan pointed at two lists.
void main() => auditWordPurity(
  wordListPath: wordList,
  scannedPaths: scanned,
  theRule: 'this framework names no platform',
);

/// Where the words this framework may not name live, relative to the repository root.
const String wordList = 'tool/api-purity.words';

/// The directories of this repository that are read to the byte.
///
/// Named one at a time rather than as "the repository minus its tools", so adding a directory to the
/// scan is a decision somebody makes here rather than a silent widening.
const List<String> scanned = <String>['lib', 'test', 'bin', 'programs'];
