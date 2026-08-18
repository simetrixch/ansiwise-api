import '../domain/arguments.dart';
import '../domain/machine.dart';
import '../domain/predicate.dart';
import '../domain/recorder.dart';
import '../domain/registry.dart';
import '../domain/resolved_program.dart';
import '../domain/step_context.dart';
import '../domain/logger.dart';
import '../model/names.dart';
import '../model/run_event.dart';
import 'planning_ports.dart';

/// Measures every condition a program uses, once, before the first step runs.
///
/// Once and not per step, for two reasons that are really one. A condition measured twice can
/// answer differently the second time, and then a run has two views of the same machine and no way
/// to say which one it acted on. And a plan printed before anything happens is only worth reading
/// if it is the plan that will actually be followed.
///
/// Predicates are evaluated through the planning ports in every mode, including a real run. A
/// condition that changes the machine while measuring it is not a condition, and here it cannot be
/// written by accident: the port refuses it.
final class PredicateEvaluation {
  /// Creates an evaluation against [machine], reporting to [recorder].
  const PredicateEvaluation({
    required this.machine,
    required this.recorder,
    required this.log,
    this.answers = Arguments.none,
  });

  /// An evaluation that records nothing, for the questions asked before a run exists.
  ///
  /// Whether an answer had to be given at all is decided before the answers are checked, and a
  /// program whose answers do not add up never becomes a run. There is no record to write into, so
  /// this states that rather than being handed one that goes nowhere.
  const PredicateEvaluation.unrecorded({required this.machine, this.answers = Arguments.none})
    : recorder = const _RecordsNothing(),
      log = const _SaysNothing();

  /// What the conditions look at.
  final Machine machine;

  /// Where the answers go.
  final Recorder recorder;

  /// Where a condition's own log lines go.
  final Logger log;

  /// What this run was told, for a condition pointed at a file named for this installation.
  final Arguments answers;

  /// Measures every condition [program] uses and returns the answers.
  Future<Facts> evaluate(ResolvedProgram program) async {
    final Map<PredicateName, RegisteredPredicate> needed = <PredicateName, RegisteredPredicate>{};
    for (final ResolvedStep step in program.steps) {
      for (final RegisteredPredicate predicate in step.when) {
        needed[predicate.name] = predicate;
      }
    }

    final Map<PredicateName, bool> answers = <PredicateName, bool>{};
    for (final RegisteredPredicate registered in needed.values) {
      // Non-null because the resolver refuses a row that names a condition nothing bound values to,
      // and a program reaches this only once it has resolved.
      final PredicateResult result = await registered.predicate!.evaluate(
        _context(registered.name),
      );
      answers[registered.name] = result.held;
      recorder.record(
        (int sequence, DateTime at) => PredicateEvaluated(
          sequence: sequence,
          at: at,
          predicate: registered.name,
          held: result.held,
          because: result.because,
        ),
      );
    }
    return Facts(answers);
  }

  /// Which of the conditions an ANSWER is stated under hold, before the answers are validated.
  ///
  /// **Why this is separate from [evaluate], which does the same for rows.** A row's condition is
  /// asked once the program is resolved and the answers are known. An answer's condition decides
  /// whether that answer had to be given at all, so it has to be asked BEFORE they are checked — and
  /// what it reads is the answers as they were supplied, not as they came out of a validation that
  /// has not happened.
  ///
  /// Nothing is recorded here for the same reason: the record belongs to a run, and a program whose
  /// answers do not add up never becomes one.
  Future<Set<String>> answerConditionsThatHold(ResolvedProgram program, Registry registry) async {
    final Set<String> named = <String>{
      for (final ArgumentSpec spec in program.declared.answers.specs)
        if (spec.statedWhen case final StatedWhen stated) stated.predicate,
    };
    final Set<String> held = <String>{};
    for (final String name in named) {
      // Non-null because the resolver refuses a program naming a condition nothing registered, and a
      // program reaches this only once it has resolved.
      final RegisteredPredicate registered = registry.predicate(PredicateName(name))!;
      final PredicateResult result = await registered.predicate!.evaluate(
        _context(registered.name),
      );
      if (result.held) {
        held.add(name);
      }
    }
    return held;
  }

  PredicateContext _context(PredicateName name) {
    // The name is borrowed as a step name so that a refusal says which condition reached for
    // something it may not. A predicate is not a step, but the refusal has to name something the
    // operator can find, and the condition's own name is that.
    final StepName owner = StepName(name.value);
    return PredicateContext(
      shell: PlanningShell(machine.shell, step: owner),
      files: PlanningFiles(machine.files, step: owner),
      http: PlanningHttp(machine.http, step: owner),
      clock: machine.clock,
      log: log,
      answers: answers,
    );
  }
}

/// A recorder for the questions asked before there is a run to record into.
final class _RecordsNothing implements Recorder {
  const _RecordsNothing();

  @override
  void record(RunEvent Function(int sequence, DateTime at) build) {}

  /// Always one, because nothing was ever recorded and nothing ever will be.
  @override
  int get nextSequence => 1;

  @override
  Future<void> close() async {}
}

/// A log for the questions asked before there is a run to write one.
///
/// What a condition says about itself belongs in the record of the run it gated. Asked before the
/// answers are even checked, there is no such run, and printing to an operator's terminal about a
/// question they did not ask is noise rather than information.
final class _SaysNothing implements Logger {
  const _SaysNothing();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
