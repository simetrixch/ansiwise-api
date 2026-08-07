import 'package:meta/meta.dart';

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

/// One entry of a program, bound to the classes it names.
@immutable
final class ResolvedStep {
  /// Binds [entry] to [registered] and to the predicates behind its `when:`.
  const ResolvedStep({required this.entry, required this.registered, required this.when});

  /// What the file said about this step.
  final ProgramStep entry;

  /// The registry entry its name stands for.
  final RegisteredStep registered;

  /// The registry entries the names behind its `when:` stand for, in the order written.
  final List<RegisteredPredicate> when;
}
