import 'package:meta/meta.dart';

import '../domain/arguments.dart';
import '../domain/machine.dart';
import '../domain/recorder.dart';
import '../domain/registry.dart';
import '../domain/resolved_program.dart';
import '../domain/step.dart';
import '../domain/step_context.dart';
import '../model/check_result.dart';
import '../model/mode.dart';
import '../model/names.dart';
import '../model/on_failure.dart';
import '../model/run_event.dart';
import '../model/step_plan.dart';
import '../model/step_record.dart';
import '../model/verdict.dart';
import 'planning_ports.dart';
import 'recording_ports.dart';
import 'redactor.dart';
import 'unwind.dart';

/// Runs one entry of a program and produces its record.
///
/// The three modes differ here and nowhere else, which is what keeps a step free of any knowledge
/// of which mode it is in — knowledge it could get wrong.
///
/// | mode | what this calls |
/// |---|---|
/// | test | the step's check, and nothing else |
/// | dry | the step's check, then its plan |
/// | run | the step's check, then its apply, **then its check again** |
///
/// That last check is where a verdict comes from. A step that returned without throwing has not
/// succeeded; a step whose postcondition holds afterwards has.
final class StepExecution {
  /// Creates an execution against [machine], reporting to [recorder].
  const StepExecution({
    required this.machine,
    required this.recorder,
    required this.redactor,
    this.logLevel = LogLevel.info,
  });

  /// What the steps act on.
  final Machine machine;

  /// Where the events go.
  final Recorder recorder;

  /// What is removed on the way into the record.
  final Redactor redactor;

  /// The quietest level this run writes, carried from the runner.
  final LogLevel logLevel;

  /// Runs [resolved] in [mode], given what the predicates found in [facts].
  ///
  /// [answers] is what the operator supplied for the whole run. It is handed to every step and read
  /// BY NAME, never substituted into a step's arguments: substitution would mean a program file
  /// that computes, and a file that computes is a file being debugged instead of the code.
  Future<StepOutcome> execute({
    required ResolvedStep resolved,
    required Mode mode,
    required Facts facts,
    required Arguments answers,
    required DateTime start,
  }) async {
    final StepName name = resolved.entry.step;
    final int firstEvent = recorder.nextSequence;

    final PredicateName? blocking = _blockedBy(resolved, facts);
    if (blocking != null) {
      return _finish(
        resolved: resolved,
        verdict: Skipped(blocking.value),
        start: start,
        firstEvent: firstEvent,
      );
    }

    recorder.record(
      (int sequence, DateTime at) =>
          StepStarted(sequence: sequence, at: at, step: name, source: resolved.registered.source),
    );

    // One set of values, used to build the step and to build its context, so that what the step
    // was constructed with and what it reads at run time cannot drift apart.
    final Arguments arguments = _argumentsWithDefaults(
      resolved.registered,
      resolved.entry.arguments,
    );
    final Step step = resolved.registered.create(arguments);
    final StepContext context = _contextFor(name, mode, arguments, facts, answers);

    try {
      return await _perform(
        resolved: resolved,
        step: step,
        context: context,
        mode: mode,
        start: start,
        firstEvent: firstEvent,
      );
    } on Exception catch (failure) {
      return _finish(
        resolved: resolved,
        verdict: _verdictFor(resolved.entry.onFailure, failure.toString()),
        start: start,
        firstEvent: firstEvent,
      );
    }
  }

  Future<StepOutcome> _perform({
    required ResolvedStep resolved,
    required Step step,
    required StepContext context,
    required Mode mode,
    required DateTime start,
    required int firstEvent,
  }) async {
    final CheckResult before = await step.check(context);

    switch (before) {
      case Blocked(:final String reason):
        // A gate that verifies an earlier step cannot hold in either of the two modes that change
        // nothing, because the step it verifies has not run. It reports what it would check instead
        // of failing on a state nobody produced — otherwise a test or a dry run of any program that
        // proves its own work dies at the first proof.
        if (mode != Mode.run && step is ObservingStep && step.verifiesAnEarlierStep) {
          final StepPlan plan = await step.plan(context);
          if (mode == Mode.dry) {
            _recordPlan(resolved.entry.step, plan);
          }
          context.log.info('not checked before the steps it verifies have run: $reason');
          return _finish(
            resolved: resolved,
            verdict: const Succeeded(),
            start: start,
            firstEvent: firstEvent,
            plan: mode == Mode.dry ? plan : null,
          );
        }
        return _finish(
          resolved: resolved,
          verdict: _verdictFor(resolved.entry.onFailure, reason),
          start: start,
          firstEvent: firstEvent,
        );

      case Satisfied(:final String because):
        if (mode == Mode.dry) {
          _recordPlan(resolved.entry.step, StepPlan.nothing(because));
        }
        context.log.info('nothing to do: $because');
        return _finish(
          resolved: resolved,
          verdict: const Succeeded(),
          start: start,
          firstEvent: firstEvent,
          plan: mode == Mode.dry ? StepPlan.nothing(because) : null,
        );

      case Ready():
        return _performReady(
          resolved: resolved,
          step: step,
          context: context,
          mode: mode,
          start: start,
          firstEvent: firstEvent,
        );
    }
  }

  Future<StepOutcome> _performReady({
    required ResolvedStep resolved,
    required Step step,
    required StepContext context,
    required Mode mode,
    required DateTime start,
    required int firstEvent,
  }) async {
    switch (mode) {
      case Mode.test:
        // The preconditions hold and there is work to do. That is the whole answer a test gives;
        // the work itself belongs to the other two modes.
        return _finish(
          resolved: resolved,
          verdict: const Succeeded(),
          start: start,
          firstEvent: firstEvent,
        );

      case Mode.dry:
        final StepPlan plan = await step.plan(context);
        _recordPlan(resolved.entry.step, plan);
        return _finish(
          resolved: resolved,
          verdict: const Succeeded(),
          start: start,
          firstEvent: firstEvent,
          plan: plan,
        );

      case Mode.run:
        // BEFORE apply, and that is the whole of it. A step that read the machine afterwards would
        // be reading a machine it had already changed, and an undo built on that is a guess rather
        // than a restoration.
        final Object? captured = step is ReversibleStep<Object?>
            ? await step.capture(context)
            : null;
        await step.apply(context);
        final CheckResult after = await step.check(context);
        if (after is! Satisfied) {
          final String why = switch (after) {
            Blocked(:final String reason) => reason,
            Ready() => 'the step ran and the machine is still not in the state it produces',
            Satisfied() => '',
          };
          return _finish(
            resolved: resolved,
            verdict: _verdictFor(resolved.entry.onFailure, why),
            start: start,
            firstEvent: firstEvent,
            applied: _applied(resolved, step, context, captured),
          );
        }
        return _finish(
          resolved: resolved,
          verdict: const Succeeded(),
          start: start,
          firstEvent: firstEvent,
          applied: _applied(resolved, step, context, captured),
        );
    }
  }

  PredicateName? _blockedBy(ResolvedStep resolved, Facts facts) {
    for (final RegisteredPredicate predicate in resolved.when) {
      if (!facts.held(predicate.name)) {
        return predicate.name;
      }
    }
    return null;
  }

  Arguments _argumentsWithDefaults(RegisteredStep registered, Arguments given) {
    final Map<String, Object> defaults = <String, Object>{
      for (final ArgumentSpec spec in registered.arguments)
        if (spec.defaultValue case final Object value) spec.name: value,
    };
    return defaults.isEmpty ? given : given.withDefaults(defaults);
  }

  StepContext _contextFor(
    StepName name,
    Mode mode,
    Arguments arguments,
    Facts facts,
    Arguments answers,
  ) {
    final RecordingLogger log = RecordingLogger(
      recorder: recorder,
      redactor: redactor,
      step: name,
      threshold: logLevel,
    );
    final Machine recording = Machine(
      shell: RecordingShell(machine.shell, recorder: recorder, redactor: redactor, step: name),
      files: RecordingFiles(machine.files, recorder: recorder, step: name),
      http: RecordingHttp(machine.http, recorder: recorder, redactor: redactor, step: name),
      clock: machine.clock,
      // Neither recorded nor wrapped, in any mode. A mint changes nothing outside this process, so
      // a dry run has nothing to refuse — and what comes out is a credential, which is the one kind
      // of value that must never reach the record. It reaches the record only where the step then
      // writes it, and there the redactor is what removes it.
      entropy: machine.entropy,
    );
    // Only a real run is given ports that can change anything. In the other two the planning
    // wrapper sits outside the recording one, so a refusal happens before the attempt is recorded
    // as having been made.
    final bool planning = mode != Mode.run;
    return StepContext(
      shell: planning ? PlanningShell(recording.shell, step: name) : recording.shell,
      files: planning ? PlanningFiles(recording.files, step: name) : recording.files,
      http: planning ? PlanningHttp(recording.http, step: name) : recording.http,
      clock: recording.clock,
      entropy: recording.entropy,
      log: log,
      step: name,
      arguments: arguments,
      answers: answers,
      facts: facts,
    );
  }

  void _recordPlan(StepName step, StepPlan plan) {
    recorder.record(
      (int sequence, DateTime at) => Planned(sequence: sequence, at: at, step: step, plan: plan),
    );
  }

  AppliedStep _applied(ResolvedStep resolved, Step step, StepContext context, Object? captured) =>
      AppliedStep(
        name: resolved.entry.step,
        step: step,
        arguments: context.arguments,
        captured: captured,
        undo: resolved.entry.undo,
      );

  /// The verdict of a step that failed under [policy].
  ///
  /// One verdict, told what the program said. Whether the run goes on is the policy's business and
  /// not a second class of failure.
  Verdict _verdictFor(OnFailure policy, String reason) => Failed(reason, policy: policy);

  StepOutcome _finish({
    required ResolvedStep resolved,
    required Verdict verdict,
    required DateTime start,
    required int firstEvent,
    StepPlan? plan,
    AppliedStep? applied,
  }) {
    final DateTime end = machine.clock.now();
    final int lastEvent = recorder.nextSequence;
    recorder.record(
      (int sequence, DateTime at) => StepFinished(
        sequence: sequence,
        at: at,
        step: resolved.entry.step,
        verdict: verdict,
        elapsed: end.difference(start),
      ),
    );

    return StepOutcome(
      record: StepRecord(
        step: resolved.entry.step,
        source: resolved.registered.source,
        start: start,
        end: end,
        verdict: verdict,
        firstEvent: firstEvent,
        lastEvent: lastEvent,
        plan: plan,
        // A failure the run carried on past is what the closing line reports. One that ended the
        // run needs no entry here: the run stopped, and the record's last step is the reason.
        issues: verdict is Failed && verdict.continues
            ? <String>[verdict.reason]
            : const <String>[],
      ),
      applied: applied,
    );
  }
}

/// What running one entry of a program produced.
@immutable
final class StepOutcome {
  /// Records what one entry produced.
  const StepOutcome({required this.record, this.applied});

  /// The row this entry becomes.
  final StepRecord record;

  /// The step, present only when its apply actually ran.
  ///
  /// This is what the unwind needs. A step that was skipped, or that had nothing to do, or that was
  /// only planned, changed nothing and must not be undone — undoing it would be a mutation nobody
  /// asked for, performed while cleaning up after a failure.
  final AppliedStep? applied;

  /// Whether the run may continue past this entry.
  bool get continues => record.verdict.continues;
}
