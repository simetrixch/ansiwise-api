import 'package:meta/meta.dart';

import '../model/names.dart';
import 'arguments.dart';
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
}

/// One predicate, as the registry holds it.
@immutable
final class RegisteredPredicate {
  /// Registers one predicate.
  const RegisteredPredicate({
    required this.name,
    required this.source,
    required this.predicate,
    required this.describes,
  });

  /// The name a program file writes behind `when:`.
  final PredicateName name;

  /// Where the class is defined, as `path:line` relative to the repository root.
  final String source;

  /// The condition itself.
  ///
  /// One instance and not a factory: a predicate takes no arguments, because a condition that needs
  /// arguments is really several conditions that each deserve a name a program file can write.
  final Predicate predicate;

  /// What it asks about the machine, in one line, for the plan the operator reads.
  final String describes;
}
