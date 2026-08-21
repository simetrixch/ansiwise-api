import 'package:meta/meta.dart';

import '../model/names.dart';
import 'arguments.dart';
import 'measurement.dart';
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

/// One place on a row whose value is measured while the run happens, and the row that measures it.
///
/// Bound by the resolver, so everything after it — the fingerprint, the plan, the record — reads one
/// answer to "where does this value come from" rather than each working it out of the program again.
///
/// **Two places, one set of rules.** A whole ARGUMENT takes a measurement, and so does one ENTRY of
/// a mapping argument. Which row may produce the value, where that row has to stand, and what it may
/// be gated on are the same questions for both, asked once against the same table — so they are one
/// kind of thing here, and the two below differ only in what they say they fill.
@immutable
sealed class MeasuredValue {
  /// Binds a place on a row to [measurement], which [publisher] at [position] produces.
  const MeasuredValue({
    required this.argument,
    required this.measurement,
    required this.publisher,
    required this.position,
  });

  /// The argument of the reading row that this value reaches.
  final String argument;

  /// The name it is published under.
  final MeasurementName measurement;

  /// The step of the row that measures it.
  final StepName publisher;

  /// Where that row stands in the program, counted from zero.
  final int position;

  /// What this fills, as a plan and a refusal name it.
  String get fills;

  /// The row that produces it, as a plan and a refusal name it.
  ///
  /// Counted from one here and from zero in [position], because the operator reading a file counts
  /// its first row as the first one.
  String get producedBy => 'step ${position + 1} $publisher';
}

/// One whole argument of a row whose value is measured while the run happens.
@immutable
final class MeasuredArgument extends MeasuredValue {
  /// Binds [argument] of a row to [measurement], which [publisher] at [position] produces.
  const MeasuredArgument({
    required super.argument,
    required super.measurement,
    required super.publisher,
    required super.position,
  });

  @override
  String get fills => '"$argument"';
}

/// One entry of a row's mapping argument whose value is measured while the run happens.
///
/// The engine writes the value into the entry as the row would have written it out, so the step
/// reading the mapping reads a value and learns nothing about where it came from.
@immutable
final class MeasuredSlot extends MeasuredValue {
  /// Binds the entry [slot] of [argument] to [measurement], which [publisher] at [position]
  /// produces.
  const MeasuredSlot({
    required super.argument,
    required this.slot,
    required super.measurement,
    required super.publisher,
    required super.position,
  });

  /// The name the entry stands under inside the mapping.
  final String slot;

  @override
  String get fills => '"$argument" entry "$slot"';
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
    this.measuredSlots = const <MeasuredSlot>[],
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

  /// The entries of this row's mapping arguments whose value is measured while the run happens.
  ///
  /// Held apart from [measured] because they fill different places: one is the whole of an argument
  /// and the other is one entry inside one. Everything that asks WHETHER this row takes a
  /// measurement asks [takesAMeasurement], which covers both.
  final List<MeasuredSlot> measuredSlots;

  /// Whether anything on this row takes its value from a measurement.
  ///
  /// **Every branch that decides something about a measured row asks THIS, and none of them asks
  /// [measured] on its own.** A row wired only through a mapping entry is a row the gate could not
  /// speak on in full, exactly as one wired through a whole argument is — its value was not in the
  /// fingerprint either. Asked through [measured] alone, such a row answers that nothing here is
  /// measured: it would be built in a dry run on a value that does not exist, and stamped proven in
  /// a real one.
  bool get takesAMeasurement => measured.isNotEmpty || measuredSlots.isNotEmpty;

  /// Everything on this row that is measured, arguments and mapping entries together.
  List<MeasuredValue> get measuredValues => <MeasuredValue>[...measured, ...measuredSlots];

  /// The names this row publishes under: what its step declares, with this row's renames applied.
  ///
  /// The EFFECTIVE names, which is what every other reader of the published table already uses. A
  /// postcondition read against the names the step declares would look for `http_field` on a row
  /// that publishes it as `run_id`, and would report a value missing that is there under the name
  /// the file gave it.
  List<MeasurementName> get publishesAs => <MeasurementName>[
    for (final MeasurementSpec spec in registered.publishes) entry.publish[spec.name] ?? spec.name,
  ];

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
