import 'package:meta/meta.dart';

import '../model/names.dart';
import 'arguments.dart';
import 'program.dart';
import 'registry.dart';

/// A program whose every name has been found in the registry.
///
/// The difference between this and [Program] is the difference between what a file says and what
/// can be run. A [Program] holds names; this holds the classes those names stand for. Nothing can
/// build one except the resolver, and the resolver refuses everything that does not add up.
///
/// That is why nothing downstream of here has to ask whether a name exists, and why no code in the
/// engine needs a null check to run a step. A whole class of "it looked fine until it ran" is gone
/// because the type says the lookup already happened.
@immutable
final class ResolvedProgram {
  /// Binds [declared] to the classes its names stand for.
  const ResolvedProgram({required this.declared, required this.steps});

  /// What the file said.
  final Program declared;

  /// Its entries, each bound to what it names.
  final List<ResolvedStep> steps;
}

/// One argument of a row whose value is measured while the run happens, and by the row that
/// measures it.
///
/// Bound by the resolver, so everything after it — the fingerprint, the plan, the record — reads one
/// answer to "where does this value come from" rather than each working it out of the program again.
@immutable
final class MeasuredArgument {
  /// Binds [argument] of a row to [measurement], which [publisher] at [position] produces.
  const MeasuredArgument({
    required this.argument,
    required this.measurement,
    required this.publisher,
    required this.position,
  });

  /// The argument of the reading row that this value fills.
  final String argument;

  /// The name it is published under.
  final MeasurementName measurement;

  /// The step of the row that measures it.
  final StepName publisher;

  /// Where that row stands in the program, counted from zero.
  final int position;

  /// The row that produces it, as a plan and a refusal name it.
  ///
  /// Counted from one here and from zero in [position], because the operator reading a file counts
  /// its first row as the first one.
  String get producedBy => 'step ${position + 1} $publisher';
}

/// One entry of a program, bound to the classes it names.
@immutable
final class ResolvedStep {
  /// Binds [entry] to [registered] and to the predicates behind its `when:`.
  const ResolvedStep({
    required this.entry,
    required this.registered,
    required this.when,
    this.measured = const <MeasuredArgument>[],
  });

  /// What the file said about this step.
  final ProgramStep entry;

  /// The registry entry its name stands for.
  final RegisteredStep registered;

  /// The registry entries the names behind its `when:` stand for, in the order written.
  final List<RegisteredPredicate> when;

  /// The arguments of this row whose value is measured while the run happens, by argument name.
  ///
  /// Empty for almost every row. A row with an entry here is a row the gate could not speak on in
  /// full: its value was not in the fingerprint, because the fingerprint is built before the first
  /// step runs. That is why the dry run says the value is not known yet and the record counts the
  /// row as declared rather than proven.
  final List<MeasuredArgument> measured;

  /// Where [argument] takes its value from, or null when the row wrote it or left it to a default.
  MeasuredArgument? measurementFor(String argument) {
    for (final MeasuredArgument each in measured) {
      if (each.argument == argument) {
        return each;
      }
    }
    return null;
  }

  /// What this step runs with: the values the file wrote, plus the ones its specification declares
  /// by default.
  ///
  /// ANYTHING THAT BUILDS THE STEP MUST USE THIS. The registry holds a factory rather than an
  /// instance, so asking a step anything at all — whether it can be taken back, what it would plan —
  /// means building it, and a step that reads an argument it was given a default for is refused when
  /// handed the file's values alone. The engine has always filled them in before building; anything
  /// else that built a step was one defaulted argument away from throwing, and the reading endpoint
  /// was exactly that.
  Arguments get argumentsWithDefaults {
    final Map<String, Object> defaults = <String, Object>{
      for (final ArgumentSpec spec in registered.arguments)
        if (spec.defaultValue case final Object value) spec.name: value,
    };
    return defaults.isEmpty ? entry.arguments : entry.arguments.withDefaults(defaults);
  }
}
