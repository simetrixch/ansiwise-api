import 'package:meta/meta.dart';

import 'step_context.dart';

/// One named condition a program may put behind `when:`.
///
/// A predicate is the only thing that decides whether a step runs. That is deliberate: the
/// alternative is a step deciding for itself and returning success without doing anything, which
/// looks identical in a record to a step that did its work.
///
/// Because the decision is a named, registered thing, the first gate can evaluate every predicate
/// against the machine and print the real plan: which steps will run, and which will be skipped by
/// which condition.
abstract interface class Predicate {
  /// Looks at the machine and answers.
  ///
  /// Must change nothing. The ports it is given enforce that in every mode, including a real run.
  Future<PredicateResult> evaluate(PredicateContext context);
}

/// What a predicate answered, and what it saw.
@immutable
final class PredicateResult {
  /// Records that the condition holds, because [because].
  const PredicateResult.holds(this.because) : held = true;

  /// Records that the condition does not hold, because [because].
  const PredicateResult.doesNotHold(this.because) : held = false;

  /// Whether the condition holds.
  final bool held;

  /// What was found, in the operator's words.
  ///
  /// Required in both directions. A skipped step is only useful to read when it says why it was
  /// skipped, and "this machine has one network interface" is the answer, not "false".
  final String because;
}
