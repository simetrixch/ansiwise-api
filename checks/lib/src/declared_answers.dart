/// The answers a probe plants, taken from what the programs declare.
///
/// A step reads an answer BY NAME out of the run, and the KIND and the DEFAULT of that value are
/// declared by the program file — never by the step, and never by the package the step ships in. So
/// a probe that invents a value plants something no installation ever plants: it exercises a branch
/// the product never takes, and the branch the product DOES take is measured by nothing while the
/// step is reported as covered.
///
/// The measured shape of that: an answer declared `default: ''` was planted as `x`, so the early
/// return every real run takes was never entered, and the step left the ledger of what is not
/// covered without any fixture having been written for it.
///
/// So the declarations are READ. What no program declares is not guessed at — it is NAMED, because
/// a probe silently falling back to a placeholder is the same defect wearing a different hat.
library;

import 'package:ansiwise_api/ansiwise_api.dart';

import 'installation_programs.dart';
import 'step_under_probe.dart';

/// What a probe will hand the steps, and what it could not read.
final class PlantedAnswers {
  /// Records the planted [values] and the names [notDeclared] by any program.
  const PlantedAnswers({required this.values, required this.notDeclared});

  /// A value for every answer, as the programs declare it.
  final Arguments values;

  /// The answers no program declares, sorted.
  ///
  /// Each one was planted as plain text with no default, which is a guess. A check asserts this is
  /// empty rather than letting the guess pass for a reading.
  final List<String> notDeclared;
}

/// Every answer specification the programs under [directory] declare, first declaration winning.
///
/// The union of every program's declarations, because a check runs each registered step once and
/// does not know which program will name it. Two programs declaring one name with different kinds
/// would make this ambiguous; the resolver would refuse such a pair anyway, and until then the first
/// one read wins.
Future<List<ArgumentSpec>> answerSpecsIn(Files files, String directory) async {
  final List<ArgumentSpec> declared = <ArgumentSpec>[];
  final Set<String> seen = <String>{};
  final List<String> names = <String>[
    for (final String name in await files.list(directory))
      if (name.endsWith('.yaml')) name,
  ]..sort();

  for (final String name in names) {
    final Program program = loadProgram(await files.read('$directory/$name'), where: name);
    for (final ArgumentSpec spec in program.answers.specs) {
      if (seen.add(spec.name)) {
        declared.add(spec);
      }
    }
  }
  return declared;
}

/// A value for every answer any program under [directory] declares.
///
/// What a check plants where every declared answer is wanted rather than the ones one registry
/// reaches for — the product that owns the programs registers the steps of every plugin under it, so
/// there is no name here that belongs to nobody.
Future<Arguments> plausibleAnswers(Files files, String directory) async =>
    plausibleArguments(await answerSpecsIn(files, directory));

/// A value for each of [names], planted the way [declared] says that answer is declared.
///
/// A name with no declaration among [declared] still gets a value — a check that could not build the
/// step would measure nothing at all about it — but it is named in [PlantedAnswers.notDeclared], so
/// the difference between a value that was read and a value that was guessed is visible rather than
/// buried in one map.
PlantedAnswers answersFrom(Set<String> names, List<ArgumentSpec> declared) {
  final Map<String, ArgumentSpec> byName = <String, ArgumentSpec>{
    for (final ArgumentSpec spec in declared) spec.name: spec,
  };
  final List<String> notDeclared = <String>[];
  final List<ArgumentSpec> planted = <ArgumentSpec>[];
  for (final String name in names.toList()..sort()) {
    final ArgumentSpec? spec = byName[name];
    if (spec == null) {
      notDeclared.add(name);
      planted.add(
        ArgumentSpec(
          name: name,
          kind: ArgumentKind.text,
          describes: 'a value no program declares, so a probe can only guess at it',
        ),
      );
      continue;
    }
    planted.add(spec);
  }
  return PlantedAnswers(values: plausibleArguments(planted), notDeclared: notDeclared);
}

/// The answers every step of [registry] reads, planted as the programs under [directory] declare
/// them.
///
/// Only what the registry declares, because that is what a step may read: an answer no step of this
/// registry reaches for would be a value planted for nobody, and a step that reads one it never
/// declared throws where the audit can report it.
///
/// A REGISTRY WHOSE STEPS READ NO ANSWER OPENS NO INSTALLATION TREE. There is no name to look up, so
/// the declarations cannot change the answer, and demanding a foreign checkout to read them anyway
/// made a package unable to run its own checks over a question it never asks. The two answers are
/// identical — [answersFrom] over an empty set of names plants nothing whatever it is given.
///
/// [files] and [directory] are what a counter-probe replaces; left alone they are the real reader
/// over the installation beside this checkout, which is what every package's checks want.
Future<PlantedAnswers> answersDeclaredBy(
  Registry registry, {
  Files files = const RealFiles(),
  String? directory,
}) async {
  final Set<String> read = <String>{
    for (final RegisteredStep entry in registry.steps.values) ...entry.answers,
  };
  if (read.isEmpty) {
    return const PlantedAnswers(values: Arguments.none, notDeclared: <String>[]);
  }
  return answersFrom(read, await answerSpecsIn(files, directory ?? installationProgramsRoot));
}
