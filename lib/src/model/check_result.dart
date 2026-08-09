import 'package:meta/meta.dart';

/// The answer a step gives when asked about the machine before it runs.
///
/// Three answers and not two. A step that reports only "ready" or "not ready" cannot express the
/// case its idempotence depends on: the machine is already in the state this step produces, so
/// there is nothing to do and that is a success rather than a skip.
@immutable
sealed class CheckResult {
  const CheckResult();

  /// The preconditions hold and the work has not been done yet.
  const factory CheckResult.ready() = Ready;

  /// The machine is already in the state this step produces.
  const factory CheckResult.satisfied(String because) = Satisfied;

  /// A precondition does not hold, so this step cannot run.
  const factory CheckResult.blocked(String reason) = Blocked;
}

/// The preconditions hold and the work has not been done yet. See [CheckResult.ready].
@immutable
final class Ready extends CheckResult {
  /// Creates the answer of a step that can run and has work to do.
  const Ready();
}

/// The machine is already in the state this step produces. See [CheckResult.satisfied].
///
/// A second run of a whole program consists mostly of these, and that is what makes it a no-op.
@immutable
final class Satisfied extends CheckResult {
  /// Creates the answer of a step whose work is already done, because [because].
  const Satisfied(this.because);

  /// What was found that shows the work is already done.
  final String because;
}

/// A precondition does not hold. See [CheckResult.blocked].
///
/// This is a failure of the step, and the program's declared policy decides what it costs.
@immutable
final class Blocked extends CheckResult {
  /// Creates the answer of a step that cannot run, because [reason].
  const Blocked(this.reason);

  /// Which precondition does not hold, named so the operator can act on it.
  final String reason;
}
