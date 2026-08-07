import '../domain/step.dart';
import '../domain/step_context.dart';
import '../model/check_result.dart';
import '../model/failures.dart';
import '../model/step_plan.dart';

/// A step whose work is waiting for something to become true.
///
/// It supplies all three parts from one question: [holds]. That question is the postcondition, so
/// there is no way to write a wait whose verdict comes from anything else — which is the failure
/// this replaces. The shell it succeeds had a wait that reported success when more than zero pods
/// were running, and another that timed out, warned, and let the run continue on something nobody
/// had confirmed.
///
/// Here a wait that reaches its deadline fails, and what that failure costs is the program's
/// declared policy rather than the step's own opinion.
base mixin WaitStep on Step {
  /// How long to keep asking before giving up.
  Duration get deadline;

  /// How long to leave between asks.
  Duration get interval;

  /// What is being waited for, in the operator's words, for the plan and for the failure.
  String get waitingFor;

  /// Asks once. Must change nothing.
  Future<bool> holds(StepContext context);

  @override
  Future<CheckResult> check(StepContext context) async =>
      await holds(context) ? CheckResult.satisfied(waitingFor) : const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.nothing('would wait up to ${deadline.inSeconds}s for $waitingFor');

  @override
  Future<void> apply(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(deadline);
    while (true) {
      if (await holds(context)) {
        return;
      }
      if (!context.clock.now().isBefore(giveUp)) {
        throw WaitedTooLong(waitingFor: waitingFor, deadline: deadline);
      }
      await context.clock.sleep(interval);
    }
  }
}
