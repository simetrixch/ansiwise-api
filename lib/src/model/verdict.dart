import 'package:meta/meta.dart';

import 'on_failure.dart';

/// How one step ended.
///
/// Sealed, so every place that reacts to a verdict must handle all five cases. Adding a sixth
/// breaks the build at every such place instead of falling into somebody's default branch.
@immutable
sealed class Verdict {
  const Verdict();

  /// A short lower-case word naming this verdict, used in the record and in the command line
  /// output. It is the same vocabulary the program files use for [OnFailure].
  String get label;

  /// Whether the run may continue past this step.
  bool get continues;
}

/// The step ran and its postcondition holds.
@immutable
final class Succeeded extends Verdict {
  /// Creates the verdict of a step that ran and whose postcondition holds.
  const Succeeded();

  @override
  String get label => 'ok';

  @override
  bool get continues => true;
}

/// The step did not run, because a condition the program declared did not hold.
///
/// This is not a failure. It is the answer to "does this machine need this step", and the operator
/// sees it as a skipped row together with [predicate], the name of the condition that skipped it.
@immutable
final class Skipped extends Verdict {
  /// Creates the verdict of a step that was not run because [predicate] did not hold.
  const Skipped(this.predicate);

  /// The registered name of the predicate that did not hold.
  final String predicate;

  @override
  String get label => 'skipped';

  @override
  bool get continues => true;
}

/// The step failed and the program declared [OnFailure.warn] for it.
@immutable
final class Warned extends Verdict {
  /// Creates the verdict of a failed step whose failure is noted and otherwise ignored.
  const Warned(this.reason);

  /// What the operator is told about the failure.
  final String reason;

  @override
  String get label => 'warn';

  @override
  bool get continues => true;
}

/// The step failed and the program declared [OnFailure.issue] for it.
///
/// The run continues; the reason is carried to the end of the run and reported there, so an
/// installation that finished with three of these says so instead of looking clean.
@immutable
final class Issued extends Verdict {
  /// Creates the verdict of a failed step whose failure is carried to the end of the run.
  const Issued(this.reason);

  /// What the operator is told about the failure, and what the end-of-run report repeats.
  final String reason;

  @override
  String get label => 'issue';

  @override
  bool get continues => true;
}

/// The step failed and the program declared [OnFailure.die] for it. The run ends here.
@immutable
final class Died extends Verdict {
  /// Creates the verdict of a failed step that ends the run.
  const Died(this.reason);

  /// What the operator is told about the failure.
  final String reason;

  @override
  String get label => 'die';

  @override
  bool get continues => false;
}
