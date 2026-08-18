import 'package:meta/meta.dart';
import '../model/failures.dart';

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

/// A condition was asked and what it reads said nothing it could make sense of.
///
/// NOT a failed run and not an answer: it is the THIRD outcome, and [PredicateResult] has no room
/// for it. Both of its cases assert something about the machine, so a condition that could not read
/// its input has to leave the run rather than pick one — answering "it does not hold" would put
/// words in the machine's mouth and switch off every step waiting on that name, silently.
///
/// **It lives in the framework so the engine can catch it.** A package that wraps a tool cannot
/// raise an engine failure — [EngineFailure] is sealed here — and an exception the engine does not
/// know is one it cannot close a record for. That was measured: a condition refusing left the record
/// on disk with no end and no exit code, so everything reading records afterwards showed a run still
/// going while the process was already gone.
final class ConditionUnanswerable implements Exception {
  /// Records that a condition could not be answered, because [because].
  const ConditionUnanswerable(this.because);

  /// What was found, and what the operator has to write instead.
  ///
  /// Held to what every refusal here is held to: it names the thing it read, what stood there, and
  /// what would make it answerable.
  final String because;

  @override
  String toString() => because;
}
