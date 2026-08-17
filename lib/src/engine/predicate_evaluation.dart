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
