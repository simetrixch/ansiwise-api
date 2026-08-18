import 'package:meta/meta.dart';

import '../model/names.dart';
import 'arguments.dart';
import 'measurement.dart';
import 'predicate.dart';
import 'step.dart';

/// The map from the names a program file writes to the classes that implement them.
///
/// Dart compiled ahead of time has no reflection, so this is written out by hand rather than
/// discovered. That is not a workaround. A registry that is written is a registry a check can count
/// against the classes on disk **in both directions**: no step exists unregistered, and no entry
/// points at a class that is gone.
///
/// It is also where a step's [RegisteredStep.source] lives. A step does not know which file it is
/// in — Dart has no way to tell it — and hand-maintaining that inside every step would drift
/// silently. Here it sits next to the entry the same check already verifies.
@immutable
final class Registry {
  /// Creates a registry from its two maps.
  const Registry({required this.steps, required this.predicates});

  /// Every step that may appear in a program file.
  final Map<StepName, RegisteredStep> steps;

  /// Every predicate that may appear behind `when:`.
  final Map<PredicateName, RegisteredPredicate> predicates;

  /// The entry for [name], or null when nothing is registered under it.
  RegisteredStep? step(StepName name) => steps[name];

  /// The entry for [name], or null when nothing is registered under it.
  RegisteredPredicate? predicate(PredicateName name) => predicates[name];
}

/// One step, as the registry holds it.
@immutable
final class RegisteredStep {
  /// Registers one step.
  const RegisteredStep({
    required this.name,
    required this.source,
    required this.create,
    this.arguments = const <ArgumentSpec>[],
    this.answers = const <String>[],
    this.publishes = const <MeasurementSpec>[],
  });

  /// The name a program file writes.
  final StepName name;

  /// Where the class is defined, as `path:line` relative to the repository root.
  ///
  /// This is what the record reports and what the operator opens when a step fails.
  final String source;

  /// Builds the step from the values a program gave it.
  ///
  /// Called only after those values have been validated against [arguments], so it may read them
  /// without checking them again.
  final Step Function(Arguments arguments) create;

  /// What this step accepts, and what it needs.
  final List<ArgumentSpec> arguments;

  /// The answers this step reads out of the run, by name.
  ///
  /// Declared for the same reason the arguments are: a step reaching for an answer the program
  /// never declared would fail in the middle of an installation, and the resolver refuses that
  /// combination before anything is looked at.
  final List<String> answers;

  /// The values this step measures during a run and publishes for a later row to take.
  ///
  /// Declared here and not by the step, for the same reason the source line is: this is what the
  /// resolver reads to answer, before anything runs, whether the name a row takes its value from is
  /// produced anywhere in that program. A step that published without declaring would produce a
  /// wiring no resolution could have checked, so the sink the engine hands it refuses a name that
  /// is not here.
  final List<MeasurementSpec> publishes;
}

/// One predicate, as the registry holds it.
///
/// It comes in two shapes, and the difference is whether the condition still has to be TOLD what to
/// look at. A condition that reads nothing — "this machine has two network interfaces" — is one
/// instance, registered here and named by a program row as it stands. A GENERIC condition — "the key
/// is true in that file" — is the same code pointed at different facts, and what it is pointed at is
/// a property of the installation and of nothing else: the plugin that brings it may not name our
/// file or our key, and a program row may not carry a structure because `when:` is a list of bare
/// names. So the values arrive from the installation's own configuration, once, before any program
/// is resolved, and what the registry then holds under the name that configuration chose is the
/// first shape again.
@immutable
final class RegisteredPredicate {
  /// Registers a condition that reads nothing, as the one instance it is.
  const RegisteredPredicate({
    required this.name,
    required this.source,
    required Predicate predicate,
    required this.describes,
  }) : _instance = predicate,
       _factory = null,
       arguments = const <ArgumentSpec>[],
       bound = Arguments.none;

  /// The result of pointing a generic condition at what one installation wants it to look at.
  const RegisteredPredicate._bound({
    required this.name,
    required this.source,
    required Predicate predicate,
    required this.describes,
    required this.bound,
  }) : _instance = predicate,
       _factory = null,
       arguments = const <ArgumentSpec>[];

  /// Registers a GENERIC condition, which does one thing to whatever it is told to look at.
  ///
  /// Mirrors [RegisteredStep]: a factory rather than an instance, and the values it will be handed
  /// declared as [ArgumentSpec]s so they are checked against their kinds before anything runs. The
  /// factory is a separate constructor rather than the same one because a closure is not a constant
  /// in Dart, and a registry a plugin writes out is const.
  const RegisteredPredicate.taking({
    required this.name,
    required this.source,
    required Predicate Function(Arguments values) create,
    required this.describes,
    required this.arguments,
  }) : _instance = null,
       _factory = create,
       bound = Arguments.none;

  /// The name a program file writes behind `when:`.
  final PredicateName name;

  /// Where the class is defined, as `path:line` relative to the repository root.
  final String source;

  /// What this condition has to be told, and what of it is required.
  ///
  /// Empty for a condition that reads nothing.
  final List<ArgumentSpec> arguments;

  /// What it asks about the machine, in one line, for the plan the operator reads.
  final String describes;

  final Predicate? _instance;

  final Predicate Function(Arguments values)? _factory;

  /// Whether this still has to be told what to look at before a program row may name it.
  bool get takesArguments => _factory != null;

  /// This condition under [as], built once from [values] and fixed from then on.
  ///
  /// Built here and not at each evaluation so the values are read one single time, on the way in,
  /// where a wrong kind is still a refusal an operator meets before the run rather than a failure in
  /// the middle of one.
  RegisteredPredicate boundTo(PredicateName as, Arguments values) => RegisteredPredicate._bound(
    name: as,
    source: source,
    predicate: _factory!(values),
    describes: describes,
    bound: values,
  );

  /// What this condition was told, kept so the fingerprint can state it.
  ///
  /// Empty for a condition that reads nothing. The instance above cannot be asked what it was built
  /// from, and what a run was gated against has to include it: two installations naming the same
  /// condition and pointing it at different facts would otherwise hash alike, and the dry run of one
  /// would admit the real run of the other.
  final Arguments bound;

  /// The condition itself, for the engine to ask.
  ///
  /// Null while this still [takesArguments]. The resolver refuses a program row that names such an
  /// entry, by name and before the first step, so nothing that reaches a run is holding one.
  Predicate? get predicate => _instance;
}
