import '../domain/machine.dart';
import '../domain/recorder.dart';
import '../domain/resolved_program.dart';
import '../domain/step_context.dart';
import '../domain/step_log.dart';
import '../model/failures.dart';
import '../model/mode.dart';
import '../model/names.dart';
import '../model/run_event.dart';
import '../model/run_record.dart';
import '../model/step_record.dart';
import '../model/verdict.dart';
import 'predicate_evaluation.dart';
import 'recording_ports.dart';
import 'redactor.dart';
import 'step_execution.dart';
import 'unwind.dart';

/// Runs a program against a machine, in one of the three modes, and produces its record.
///
/// It does four things and delegates the rest: it refuses a program that does not apply to this
/// machine, it has the conditions measured once, it walks the steps applying the failure policy
/// each one declared, and when a step ends the run it has what was already done taken back.
///
/// What it never does is decide what a step means. A verdict comes from the step's own checked
/// postcondition, and what a failure costs comes from the program file. Both of those live outside
/// this class on purpose: a runner that also judged would be a runner every judgement had to be
/// argued with.
final class Runner {
  /// Creates a runner against [machine], recording to [recorder].
  const Runner({required this.machine, required this.recorder, required this.redactor});

  /// What the program acts on.
  final Machine machine;

  /// Where everything that happens is written.
  final Recorder recorder;

  /// What is removed on the way into the record.
  final Redactor redactor;

  /// Runs [program] in [mode] against the machine described by [header].
  ///
  /// Returns the completed record. Throws [RoleMismatch] when the program does not apply to this
  /// machine — before anything is measured, because measuring a machine a program will not run
  /// against is work with no reader.
  Future<RunRecord> run({
    required ResolvedProgram program,
    required Mode mode,
    required RunRecord header,
  }) async {
    if (!program.declared.appliesTo(header.role)) {
      throw RoleMismatch(
        program: program.declared.name.value,
        role: header.role.value,
        applies: program.declared.roles.map((Role r) => r.value).join(', '),
      );
    }

    try {
      recorder.record(
        (int sequence, DateTime at) =>
            RunStarted(sequence: sequence, at: at, program: program.declared.name, mode: mode.flag),
      );

      final Facts facts = await _measure(program);
      final _Walk walk = await _walkSteps(program, mode, facts);

      if (walk.ended && walk.applied.isNotEmpty) {
        await Unwind(
          machine: machine,
          recorder: recorder,
          redactor: redactor,
        ).undo(walk.applied, facts);
      }

      final int exitCode = walk.ended ? 1 : (walk.issues.isEmpty ? 0 : 2);
      final DateTime end = machine.clock.now();
      recorder.record(
        (int sequence, DateTime at) =>
            RunFinished(sequence: sequence, at: at, exitCode: exitCode, issues: walk.issues),
      );

      return header.closed(end: end, exitCode: exitCode, steps: walk.records, issues: walk.issues);
    } finally {
      // Closed even when a step threw something this engine does not catch. A run that crashed
      // without leaving its record is a run nobody can find out anything about, which is the one
      // outcome worse than failing.
      await recorder.close();
    }
  }

  Future<Facts> _measure(ResolvedProgram program) {
    final StepLog log = RecordingLog(
      recorder: recorder,
      redactor: redactor,
      step: const StepName('when'),
    );
    return PredicateEvaluation(machine: machine, recorder: recorder, log: log).evaluate(program);
  }

  Future<_Walk> _walkSteps(ResolvedProgram program, Mode mode, Facts facts) async {
    final StepExecution execution = StepExecution(
      machine: machine,
      recorder: recorder,
      redactor: redactor,
    );
    final List<StepRecord> records = <StepRecord>[];
    final List<AppliedStep> applied = <AppliedStep>[];
    final List<String> issues = <String>[];

    for (final ResolvedStep step in program.steps) {
      final StepOutcome outcome = await execution.execute(
        resolved: step,
        mode: mode,
        facts: facts,
        start: machine.clock.now(),
      );
      records.add(outcome.record);
      if (outcome.applied case final AppliedStep entry) {
        applied.add(entry);
      }
      if (outcome.record.verdict case final Issued issued) {
        issues.add('${step.entry.step}: ${issued.reason}');
      }
      if (!outcome.continues) {
        return _Walk(records: records, applied: applied, issues: issues, ended: true);
      }
    }
    return _Walk(records: records, applied: applied, issues: issues, ended: false);
  }
}

/// What walking the steps produced, gathered so the run can close on it.
final class _Walk {
  const _Walk({
    required this.records,
    required this.applied,
    required this.issues,
    required this.ended,
  });

  final List<StepRecord> records;
  final List<AppliedStep> applied;
  final List<String> issues;

  /// Whether a step ended the run before the last one was reached.
  final bool ended;
}
