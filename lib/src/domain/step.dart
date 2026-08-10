import '../model/check_result.dart';
import '../model/step_plan.dart';
import 'step_context.dart';

/// One thing that happens to a machine.
///
/// One step is one class in one file with one test, and it produces one row in the record. That is
/// what makes the record's reference to the file that produced a failure worth anything: opening it
/// shows the step and nothing else.
///
/// A step cannot be extended directly. It is extended through [ReversibleStep] or
/// [IrreversibleStep], and the constructor here is private so that the compiler enforces the
/// choice rather than a reviewer noticing it is missing. Every step therefore answers the question
/// "can this be taken back", which is what lets a dry run tell the operator in advance where the
/// run stops being reversible.
abstract base class Step {
  const Step._();

  /// Whether this step's answer rests on something the program row supplied and no code chose.
  ///
  /// The case this exists for: a step that runs whatever command its row names. The row declares
  /// that the command only looks, and the framework has nothing but that word — it did not choose
  /// the command, so it cannot verify the claim the dry-run guarantee keys on. The engine stamps
  /// such a row declared rather than proven, in every mode and whatever the verdict,
  /// so the closing line's three numbers carry it and the record never puts the weight of a
  /// measurement behind the row's own claim. The dry-safety check reads the same flag and lists
  /// these steps instead of counting them safe.
  ///
  /// The default is false: a step whose author fixed in code everything it reaches for is answered
  /// by the framework's own measurements.
  bool get answersOnTrust => false;

  /// Looks at the machine and reports whether this step can run and whether it still needs to.
  ///
  /// Called in every mode, including a dry run, so it must change nothing. The ports it is given
  /// enforce that.
  ///
  /// It is also called a second time, after [apply], and that is where a step's verdict comes from.
  /// A step that ran without throwing but whose check does not then answer [Satisfied] has failed —
  /// whatever the command it ran returned. The shell this replaces had eleven phases that reported
  /// success over a real failure, every one of them by trusting an exit code: a wait whose bar was
  /// "more than zero pods running", a version reader that printed `not installed` and returned zero,
  /// an upgrade that fell back to an unpinned install. None of those can survive a postcondition
  /// that is checked rather than assumed.
  ///
  /// This is why [CheckResult] has three answers and not two. [Satisfied] is not only how
  /// idempotence is expressed; it is how success is proven.
  Future<CheckResult> check(StepContext context);

  /// Reports what applying this step would change, without changing it.
  ///
  /// Called only in a dry run, and only when [check] answered [Ready] — a step that has nothing to
  /// do is reported as such from the check and is never asked to plan.
  Future<StepPlan> plan(StepContext context);

  /// Does it.
  ///
  /// Called only in a real run, and only when [check] answered [Ready]. Throwing is how a step
  /// fails; what the failure costs is the program's declared policy, not the step's business.
  ///
  /// Returning without throwing is not success. [check] runs again afterwards and has to answer
  /// [Satisfied] before the step counts as done.
  Future<void> apply(StepContext context);
}

/// A step that can be taken back.
///
/// The engine unwinds in reverse when a later step ends the run, calling [undo] on each reversible
/// step it had already applied, and recording what it undid.
///
/// **Saying it can be taken back obliges it to keep what it overwrites.** That is not an extra
/// property beside the claim, it IS the claim, and the compiler holds it: [capture] cannot be left
/// out, and [undo] is handed what it returned rather than being free to go and look.
///
/// WHY LOOKING AGAIN IS NOT ENOUGH, and this is the whole of it. An undo that re-measures the
/// machine measures a machine that has changed since — by this step, by the steps after it, and by
/// whatever was going on outside the run. One step in this platform removed the packages it found
/// installed at undo time, believing they were the ones it had installed; a machine that already
/// carried one of them had it taken away while the run was cleaning up after an unrelated failure.
/// The author had written the correct rule in a comment directly above the code that did not hold
/// it.
abstract base class ReversibleStep<T> extends Step {
  /// Creates a step that can be taken back.
  const ReversibleStep() : super._();

  /// What this step is about to change, read BEFORE [Step.apply] runs.
  ///
  /// Whatever [undo] needs in order to put the machine back, and nothing else. A step that CREATES
  /// something absent captures the fact that it was absent; a step that CHANGES something captures
  /// what was there.
  ///
  /// It runs before apply and must not change anything itself — the ports refuse a mutation in the
  /// two modes that change nothing, and this is called in all three.
  Future<T> capture(StepContext context);

  /// Returns the machine to the state [captured] describes.
  ///
  /// Must tolerate being called after a partial apply: the step it is undoing may have failed
  /// halfway, and that is exactly when it matters.
  Future<void> undo(StepContext context, T captured);
}

/// A step that only measures the machine, and refuses the run when what it measures is not so.
///
/// The preflight gates are these: is this the operating system we pin, is the machine big enough,
/// is there disk, is the command we need on the path. They change nothing, so the question of
/// taking them back does not arise — which is why they are their own kind rather than a
/// [ReversibleStep] with an empty undo or an [IrreversibleStep] with a reason that is not true.
///
/// **A gate's check answers [Satisfied] or [Blocked], never [Ready].** A gate has no work to do, so
/// a third answer would mean the engine calls [Step.apply], which does nothing, and then finds the
/// machine unchanged — reported as a failure for a reason nobody could act on. A gate that holds is
/// satisfied; one that does not is blocked, and what that costs the run is the program's declared
/// policy.
///
/// **The one thing that answers [Ready] here is a WAIT**, and it is not an exception to the
/// sentence above but to its reason: `WaitStep` supplies an apply, so `Ready` sends the engine to
/// work that exists. A wait belongs to this kind for the same reason a gate does — it changes
/// nothing on the machine, so it is neither reversible nor irreversible — and what it does with the
/// time is ask the same question again.
abstract base class ObservingStep extends Step {
  /// Creates a step that only measures.
  const ObservingStep() : super._();

  /// Whether this gate verifies what an earlier step did, rather than measuring the machine as it
  /// was found.
  ///
  /// It decides what a dry run does with a gate that does not hold, and the two cases are genuinely
  /// different:
  ///
  /// - A gate that **measures the machine as found** answers the same in every mode. "This machine
  ///   has four processors and the platform needs eight" is as true before a run as during one, and
  ///   a dry run that hid it would be hiding the answer the operator came for.
  /// - A gate that **verifies an earlier step** cannot answer before that step has run. In a dry run
  ///   nothing happened, so the key it is looking for is not there and the package it is looking for
  ///   is not installed — through no fault of the machine. Failing there would make a dry run
  ///   useless for every program that proves its own work, which is every program worth writing.
  ///
  /// So in the two modes that change nothing, a verifying gate reports what it *would* check and a
  /// measuring gate reports what it found. Neither lies. In a real run both are answered, because by
  /// then the steps they verify have run — which is the only mode in which the question means
  /// anything.
  ///
  /// The default is the measuring one: a gate nobody thought about is answered truthfully rather
  /// than quietly passed over.
  bool get verifiesAnEarlierStep => false;

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.nothing(
    verifiesAnEarlierStep
        ? 'would check this once the steps before it have run'
        : 'this step only measures the machine',
  );

  @override
  Future<void> apply(StepContext context) async {
    // Nothing. A gate that holds was already satisfied by its check, and one that does not never
    // reaches here.
  }
}

/// A step that cannot be taken back, and says why.
///
/// The reason is not a formality. It is what the dry run shows the operator when it names the point
/// beyond which there is no going back, so it is written for them and not for a reviewer.
abstract base class IrreversibleStep extends Step {
  /// Creates a step that cannot be taken back.
  const IrreversibleStep() : super._();

  /// Why this cannot be undone, in the operator's words.
  ///
  /// Not "no undo implemented" — what it is about the change that cannot be reversed. Removing a
  /// package can be undone by installing it again; deleting the address pool a running cluster is
  /// using cannot, because what is lost is state nothing wrote down.
  String get irreversibleReason;
}
