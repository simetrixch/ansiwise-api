import 'package:meta/meta.dart';

import '../model/names.dart';
import '../model/on_failure.dart';
import 'arguments.dart';

/// An ordered list of steps, and what each of them is allowed to cost.
///
/// A program is declared as data and never as code. It names steps, gives them arguments, puts
/// named conditions in front of some of them, and says what a failure costs. It cannot compute: no
/// loops, no expressions, no templating, no precedence between sources. The moment a program file
/// can compute, the thing being debugged is the file rather than the code, which is the state this
/// framework exists to avoid.
@immutable
final class Program {
  /// Creates a program.
  const Program({required this.name, required this.roles, required this.steps});

  /// Its name, which is also the sub-command that runs it.
  final ProgramName name;

  /// The machine roles it applies to.
  ///
  /// A program run against a machine whose role is not in here is refused at the first gate, before
  /// anything is looked at.
  final List<Role> roles;

  /// The steps, in the order they run.
  final List<ProgramStep> steps;

  /// Whether this program may be run against a machine of [role].
  bool appliesTo(Role role) => roles.contains(role);
}

/// One entry in a program: which step, with what, when, and what a failure costs.
@immutable
final class ProgramStep {
  /// Creates one entry in a program.
  const ProgramStep({
    required this.step,
    required this.onFailure,
    this.arguments = Arguments.none,
    this.when = const <PredicateName>[],
  });

  /// The registered name of the step.
  final StepName step;

  /// What a failure of this step costs the run.
  ///
  /// Required, with no default. A default would be a policy nobody chose, applied to the step
  /// somebody forgot to think about — and the steps nobody thought about are exactly the ones whose
  /// failure policy turns out to be wrong.
  final OnFailure onFailure;

  /// The values this step is given.
  final Arguments arguments;

  /// The conditions that must all hold for this step to run.
  ///
  /// Combined with and, never with or. A condition that needs an or is two named conditions too
  /// few — and a program file that can express or is one expression away from being able to
  /// compute.
  final List<PredicateName> when;
}
