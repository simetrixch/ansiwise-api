import 'package:ansiwise_api/ansiwise_api.dart';

/// A step that writes a file. Reversible: the undo puts back whatever was there, or deletes it when
/// there was nothing.
final class WritesAFile extends ReversibleStep<String?> with FileStep {
  WritesAFile({required this.path, required this.content});

  final String path;

  final String content;

  @override
  String pathFor(StepContext context) => path;

  @override
  int get mode => 0x1a4;

  @override
  Future<FileContent> contentFor(StepContext context) async => FileContent.text(content);

  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      await context.files.delete(path);
      return;
    }
    await context.files.write(path, captured, mode: mode);
  }
}

/// A step that runs a command it declares as changing something, and whose postcondition is a file
/// the command is supposed to leave behind.
final class RunsACommand extends IrreversibleStep with CommandStep {
  RunsACommand({required this.argv, required this.leaves});

  final List<String> argv;

  /// The file the command is supposed to produce, which is what proves it worked.
  final String leaves;

  @override
  String get irreversibleReason => 'the command it runs does not come with a way back';

  @override
  Command commandFor(StepContext context) => Command(argv.first, argv.sublist(1));

  @override
  Future<CheckResult> check(StepContext context) async => await context.files.exists(leaves)
      ? CheckResult.satisfied('$leaves is there')
      : const CheckResult.ready();
}

/// A step that tries to change something from inside its own check.
///
/// It exists to be refused. Nothing in the framework stops a step being written this way, and that
/// is exactly why the port has to.
final class MutatesWhileChecking extends IrreversibleStep {
  const MutatesWhileChecking();

  @override
  String get irreversibleReason => 'it is only here to be refused';

  @override
  Future<CheckResult> check(StepContext context) async {
    await context.files.write('/tmp/never', 'this must not be written', mode: 0x1a4);
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.nothing('nothing');

  @override
  Future<void> apply(StepContext context) async {}
}

/// A step whose plan reaches for a command it did not declare as only looking.
final class MutatesWhilePlanning extends IrreversibleStep {
  const MutatesWhilePlanning();

  @override
  String get irreversibleReason => 'it is only here to be refused';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async {
    await context.shell.run(const Command('rm', <String>['-rf', '/']));
    return const StepPlan.nothing('nothing');
  }

  @override
  Future<void> apply(StepContext context) async {}
}

/// A step that does its work and whose postcondition never holds afterwards.
///
/// The shape of every phase the shell had that reported success over a real failure: the command
/// returns zero, and the machine is not in the state the step is supposed to produce.
final class ClaimsSuccessWithout extends IrreversibleStep {
  const ClaimsSuccessWithout();

  @override
  String get irreversibleReason => 'it is only here to fail its own postcondition';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.nothing('nothing');

  @override
  Future<void> apply(StepContext context) async {
    await context.shell.run(const Command('true'));
  }
}

/// A step that cannot run, and says which precondition is missing.
final class Blocks extends IrreversibleStep {
  const Blocks(this.reason);

  final String reason;

  @override
  String get irreversibleReason => 'it never runs';

  @override
  Future<CheckResult> check(StepContext context) async => CheckResult.blocked(reason);

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.nothing('nothing');

  @override
  Future<void> apply(StepContext context) async {}
}

/// A condition that answers whatever it was built with.
final class Says implements Predicate {
  const Says({required this.answer, required this.because});

  final bool answer;
  final String because;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async =>
      answer ? PredicateResult.holds(because) : PredicateResult.doesNotHold(because);
}

/// A step that only measures the machine and finds it as it should be.
///
/// There is nothing to take it back from, which is exactly what makes it worth having here: a
/// question about what a run leaves behind must not answer "this step" for something that leaves
/// nothing. Only its KIND says so — the class is neither reversible nor irreversible — so a reader
/// asking merely "is it a ReversibleStep" gets the wrong answer about it.
final class Measures extends ObservingStep {
  const Measures(this.because);

  final String because;

  @override
  Future<CheckResult> check(StepContext context) async => CheckResult.satisfied(because);

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.nothing(because);
}

/// A gate whose whole job is verifying an earlier step, asked before that step has run.
///
/// The one row in this framework that ends up declared. Its check cannot hold in a mode where
/// nothing was applied — what it looks for is not there, through no fault of the machine — so the
/// engine carries the run past it on the strength of what it says it WOULD check. Nothing measured
/// that, and the record has to say so rather than count the row among the measured ones.
final class VerifiesWhatRanBefore extends ObservingStep {
  const VerifiesWhatRanBefore();

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async =>
      const CheckResult.blocked('the file the earlier step writes is not there');

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.nothing('would read back what the earlier step wrote');
}
