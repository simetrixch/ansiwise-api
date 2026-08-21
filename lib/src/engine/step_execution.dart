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
import '../model/step_standing.dart';
import '../model/verdict.dart';
import 'measurements.dart';
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
  ///
  /// [measurements] is what the steps of this run have published so far, and where this one
  /// publishes. A row that takes a value from a measurement is filled out of it — in the mode that
  /// changes things, which is the only mode in which the row that produces the value has done its
  /// work.
  Future<StepOutcome> execute({
    required ResolvedStep resolved,
    required Mode mode,
    required Facts facts,
    required Arguments answers,
    required DateTime start,
    Measurements? measurements,
  }) async {
    final StepName name = resolved.entry.step;
    final int firstEvent = recorder.nextSequence;
    // A caller that runs one step by itself gets a collection of its own, so a step that publishes
    // does not throw on a sink that is not there. Nothing reads it: one step is not a program, and
    // a row taking a value is bound to a row of the same program by the resolver.
    final Measurements taken = measurements ?? Measurements(redactor);

    final PredicateName? blocking = _blockedBy(resolved, facts);
    if (blocking != null) {
      return _finish(
        resolved: resolved,
        verdict: Skipped(blocking.value),
        // Nothing ran, so there is nothing here anything could have measured. It is counted apart
        // from the measured rows and never added to them.
        standing: StepStanding.skipped,
        start: start,
        firstEvent: firstEvent,
      );
    }

    recorder.record(
      (int sequence, DateTime at) =>
          StepStarted(sequence: sequence, at: at, step: name, source: resolved.registered.source),
    );

    // THE ROW WHOSE VALUE DOES NOT EXIST YET. In the two modes that change nothing, the row that
    // measures this value has not done its work, so there is nothing to build this step with. It is
    // not asked what it would do: a step asked with a stand-in answers about a file or a command the
    // run need not touch, and the operator reads that as knowledge.
    if (mode != Mode.run && resolved.takesAMeasurement) {
      return _notKnownYet(resolved: resolved, mode: mode, start: start, firstEvent: firstEvent);
    }

    // One set of values, used to build the step and to build its context, so that what the step
    // was constructed with and what it reads at run time cannot drift apart.
    final Arguments withDefaults = _argumentsWithDefaults(
      resolved.registered,
      resolved.entry.arguments,
    );
    final List<MeasuredValue> missing = <MeasuredValue>[
      for (final MeasuredValue each in resolved.measuredValues)
        if (taken.valueOf(each.measurement) == null) each,
    ];
    if (missing.isNotEmpty) {
      // The row that produces the value did not produce it — it failed, and this program said to
      // carry on past it. Nothing here stands in for it: this row refuses, under its own failure
      // policy, and names the measurement that is missing and the row that owed it.
      return _finish(
        resolved: resolved,
        verdict: _verdictFor(resolved.entry.onFailure, _missingSaid(missing)),
        standing: StepStanding.declared,
        start: start,
        firstEvent: firstEvent,
      );
    }
    final Arguments arguments = _withMeasured(resolved, withDefaults, taken);
    if (resolved.takesAMeasurement) {
      _sayWhatIsNotProven(name, _duringTheRunSaid(resolved));
    }

    final Step step = resolved.registered.create(arguments);
    final StepContext context = _contextFor(name, mode, arguments, facts, answers, taken, resolved);

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
        // A failure the framework watched happen is a measurement. What is proven here is not that
        // the step worked — the verdict says it did not — but that the row says what was seen.
        standing: _measured(step, resolved),
        start: start,
        firstEvent: firstEvent,
      );
    }
  }

  /// Closes a row the framework did not ask, because its value is measured while the run happens.
  ///
  /// The verdict is success and the standing is declared, which is the same pair the gate that
  /// verifies an earlier step ends on and for the same reason: the run carries on, and nothing here
  /// measured anything.
  StepOutcome _notKnownYet({
    required ResolvedStep resolved,
    required Mode mode,
    required DateTime start,
    required int firstEvent,
  }) {
    final StepPlan plan = StepPlan.notKnownYet(_notKnownYetSaid(resolved));
    _sayWhatIsNotProven(resolved.entry.step, plan.summary);
    if (mode == Mode.dry) {
      _recordPlan(resolved.entry.step, plan);
    }
    return _finish(
      resolved: resolved,
      verdict: const Succeeded(),
      standing: StepStanding.declared,
      start: start,
      firstEvent: firstEvent,
      plan: mode == Mode.dry ? plan : null,
    );
  }

  /// What the plan of a row whose value is not known yet says, one reading per clause.
  String _notKnownYetSaid(ResolvedStep resolved) => <String>[
    for (final MeasuredValue each in resolved.measuredValues)
      '${each.fills} holds the measurement "${each.measurement}", which ${each.producedBy} '
          'takes while the run happens',
  ].join('; ');

  /// What the record says about a row that ran on a value measured during the run.
  String _duringTheRunSaid(ResolvedStep resolved) =>
      '${<String>[for (final MeasuredValue each in resolved.measuredValues) '${each.fills} holds the measurement "${each.measurement}", taken by '
            '${each.producedBy} during this run'].join('; ')} — a value measured while the run happens was not in the fingerprint the gate '
      'spoke on, so this row is declared rather than proven';

  /// What a row says when the measurement it takes was never published.
  String _missingSaid(List<MeasuredValue> missing) => <String>[
    for (final MeasuredValue each in missing)
      'the measurement "${each.measurement}" was never published, so ${each.fills} has no '
          'value — ${each.producedBy} produces it, and it did not',
  ].join('; ');

  /// Writes into the record why a row is not counted among the measured ones.
  ///
  /// Recorded straight rather than through the step's logger, so the quietest level a run was
  /// configured to write cannot remove it. A row standing as declared with no reason beside it is a
  /// record that states a fact and withholds the only thing that makes it readable.
  void _sayWhatIsNotProven(StepName step, String message) {
    recorder.record(
      (int sequence, DateTime at) => Log(
        sequence: sequence,
        at: at,
        step: step,
        level: LogLevel.warn,
        message: redactor.hide(message),
      ),
    );
  }

  /// [given] with every measured value written where the row said it goes.
  ///
  /// The measurement wins over the step's own default for that argument. The default is what makes
  /// the row examinable before the run — it is not what the row was written to run with.
  ///
  /// **A mapping entry is written out as a value, exactly as the row could have written it.** The
  /// step then reads the value it was always going to read and learns nothing about where it came
  /// from — which is what keeps a step free of any knowledge of measurements, the same way it is
  /// free of any knowledge of the mode it runs in.
  Arguments _withMeasured(ResolvedStep resolved, Arguments given, Measurements taken) {
    if (!resolved.takesAMeasurement) {
      return given;
    }
    final Map<String, Object> values = <String, Object>{
      for (final String name in given.names)
        if (given.raw(name) case final Object value) name: value,
    };
    for (final MeasuredArgument each in resolved.measured) {
      if (taken.valueOf(each.measurement) case final String value) {
        values[each.argument] = value;
      }
    }
    for (final MeasuredSlot each in resolved.measuredSlots) {
      if (taken.valueOf(each.measurement) case final String value) {
        // Cast rather than checked: the resolver read this entry OUT of a mapping, so an argument
        // that is not one here is a resolution that did not happen and belongs in the open rather
        // than passed over.
        final Map<String, Object?> mapping = values[each.argument]! as Map<String, Object?>;
        values[each.argument] = <String, Object?>{...mapping, each.slot: value};
      }
    }
    return Arguments(values);
  }

  /// A step's own check, with the one thing it cannot answer turned into an answer.
  ///
  /// **A check that could not be PERFORMED is BLOCKED, not a crash.** A step measures the machine
  /// with a tool, and on the machine this whole mode exists for — one where nothing has been done
  /// yet — that tool is regularly what an earlier step installs. Reaching for it throws, and the
  /// throw carried the step away entirely: no verdict, no plan, a run ended on a stack trace where
  /// the truthful answer was "I cannot measure this yet, and here is what is missing".
  ///
  /// Blocked is exactly that answer, and it is already the verdict the rest of this method knows how
  /// to read: a step that verifies an earlier one reports what it WOULD check, and one that measures
  /// the machine as found reports what it found. Neither had a branch for "could not look".
  ///
  /// **It is caught here and in no step**, because every step has this problem and a fix repeated
  /// fifty times is fifty chances to get it wrong. What is NOT caught here is a failure of the work
  /// itself — this wraps the check alone.
  ///
  /// Found on a real machine and findable nowhere else: a fake shell answers an argv without the
  /// executable needing to exist, so a suite is green over a program that stops at its fourth step.
  Future<CheckResult> _checked(Step step, StepContext context) async {
    try {
      return await step.check(context);
    } on Object catch (why) {
      return CheckResult.blocked(
        'this could not be measured: ${'$why'.split('\n').map((String l) => l.trim()).join(' ')}',
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
    final CheckResult before = await _checked(step, context);

    switch (before) {
      case Blocked(:final String reason):
        // A step resting on an earlier one cannot proceed in either of the two modes that change
        // nothing, because the step it rests on has not run. It reports what it WOULD do instead of
        // failing on a state nobody produced — otherwise a test or a dry run of any program that
        // installs something and then configures it dies at the first configuring step, and that is
        // every deployment program there is.
        //
        // ITS OWN plan() IS NOT ASKED where it cannot look. A gate composes its plan out of a fixed
        // sentence; a step that writes composes one out of the file it is about to change — and the
        // whole reason it is here is that the file is not there yet. Asking would fail a second
        // time, in a place with no verdict to put it in.
        //
        // EITHER SIDE MAY SAY IT, and they are different statements. The step says it where it is
        // true of every use — a gate that verifies what an earlier step did can never answer before
        // that step has run, whatever program names it. The ROW says it where it is true of this
        // sequence — the same writer rests on nothing when the thing it configures is already there.
        if (mode != Mode.run &&
            (step.restsOnAnEarlierStep || resolved.entry.restsOnAnEarlierStep)) {
          final StepPlan plan = step is ObservingStep
              ? await step.plan(context)
              : const StepPlan.nothing('would do this once the steps before it have run');
          if (mode == Mode.dry) {
            _recordPlan(resolved.entry.step, plan);
          }
          context.log.info('not answered before the steps it rests on have run: $reason');
          return _finish(
            resolved: resolved,
            verdict: const Succeeded(),
            // THE ROW THIS STATE EXISTS FOR. The step's own check could not hold, so its plan is
            // what it says it would do rather than what anything confirmed, and the verdict beside
            // it is the framework letting the run continue rather than the framework agreeing. Both
            // read as success and neither was measured.
            standing: StepStanding.declared,
            start: start,
            firstEvent: firstEvent,
            plan: mode == Mode.dry ? plan : null,
          );
        }
        return _finish(
          resolved: resolved,
          verdict: _verdictFor(resolved.entry.onFailure, reason),
          // The check answered, and what it answered was that a precondition does not hold.
          standing: _measured(step, resolved),
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
          // The check read the machine and found it already in the state this step produces. That
          // is a measurement, and it is the one idempotence rests on.
          standing: _measured(step, resolved),
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
          // The step's own check answered on this machine. That is everything a test claims.
          standing: _measured(step, resolved),
          start: start,
          firstEvent: firstEvent,
        );

      case Mode.dry:
        final StepPlan plan = await step.plan(context);
        _recordPlan(resolved.entry.step, plan);
        return _finish(
          resolved: resolved,
          verdict: const Succeeded(),
          // The framework asked while the precondition held, with the planning ports around every
          // way out of this step — so whatever it reached for on the way to this answer was refused
          // rather than carried out. That is what makes the plan a measurement and not a claim.
          standing: _measured(step, resolved),
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

        try {
          await step.apply(context);
        } on Exception catch (failure) {
          // CAUGHT HERE AND NOT AT THE TOP, and the difference is the whole of the undo contract.
          // An apply that throws is the partial apply a step's undo exists for — it changed
          // something and then stopped — and the capture taken above is exactly what putting that
          // back needs. Letting the throw reach the outer catch loses it: that one answers without
          // an applied step, so the unwind never reaches this step at all, and what it changed
          // before it threw stands while its kind still tells the operator it can be taken back.
          return _finish(
            resolved: resolved,
            verdict: _verdictFor(resolved.entry.onFailure, failure.toString()),
            standing: _measured(step, resolved),
            start: start,
            firstEvent: firstEvent,
            applied: _applied(resolved, step, context, captured),
          );
        }

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
            // The postcondition was read after the apply and did not hold. Measured, and the answer
            // was no.
            standing: _measured(step, resolved),
            start: start,
            firstEvent: firstEvent,
            applied: _applied(resolved, step, context, captured),
          );
        }
        return _finish(
          resolved: resolved,
          verdict: const Succeeded(),
          // The postcondition was read after the apply and holds. This is the only thing in the
          // framework that turns "the step returned without throwing" into "the step worked".
          standing: _measured(step, resolved),
          start: start,
          firstEvent: firstEvent,
          applied: _applied(resolved, step, context, captured),
        );
    }
  }

  /// What a branch that measured through [step] may claim.
  ///
  /// A step that answers on trust cannot yield a proven row, whichever way its check, its plan or
  /// its verdict came out: everything measured here was measured through something only the program
  /// row vouches for, and a measurement over an unverified instrument is the row's claim, not the
  /// framework's. The two branches that never measured — a skipped row and the verifying gate —
  /// state their own standing and do not come through here.
  ///
  /// A row that takes a value from a measurement cannot yield a proven row either, and for a
  /// different reason: what it ran with was not in the fingerprint, because the fingerprint is built
  /// before the first step runs. The framework did watch this row work; what it cannot say is that
  /// the input the gate cleared is the input this row acted on. Whatever the verdict, the row is
  /// declared — which is what makes the whole run not fully proven.
  StepStanding _measured(Step step, ResolvedStep resolved) =>
      step.answersOnTrust || resolved.takesAMeasurement
      ? StepStanding.declared
      : StepStanding.proven;

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
    Measurements taken,
    ResolvedStep resolved,
  ) {
    final RecordingLogger log = RecordingLogger(
      recorder: recorder,
      redactor: redactor,
      step: name,
      threshold: logLevel,
    );
    final Machine recording = Machine(
      shell: RecordingShell(
        machine.shell,
        recorder: recorder,
        redactor: redactor,
        step: name,
        keepsOutput: resolved.entry.keepsOutput,
      ),
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
      // Scoped to this step and to what its registry entry declares, in every mode. A step does not
      // know which mode it is in and must not have to: it measures and publishes wherever it
      // measures, and what a mode where nothing changes does with the value is decided above, by the
      // engine, which is the only place that can know the row producing it has not run.
      //
      // The row's rename is applied HERE and nowhere else, so a step publishes the name its class
      // declares and never learns it was published under another. What it takes off the machine is
      // the same whichever program names it; which name the value stands under is a fact about the
      // program, and this is where the program's facts meet the step.
      measurements: taken.forStep(
        name,
        resolved.registered.publishes,
        publishedAs: resolved.entry.publish,
      ),
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
        keepsOutput: resolved.entry.keepsOutput,
      );

  /// The verdict of a step that failed under [policy].
  ///
  /// One verdict, told what the program said. Whether the run goes on is the policy's business and
  /// not a second class of failure.
  Verdict _verdictFor(OnFailure policy, String reason) => Failed(reason, policy: policy);

  /// Closes one row.
  ///
  /// [standing] has no default, and that is deliberate. Every branch above states how much it
  /// measured, so a branch added later cannot inherit a claim nobody made for it — and "proven"
  /// inherited by accident is the exact shape of a run claiming more than it has.
  StepOutcome _finish({
    required ResolvedStep resolved,
    required Verdict verdict,
    required StepStanding standing,
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
        standing: standing,
      ),
    );

    return StepOutcome(
      record: StepRecord(
        step: resolved.entry.step,
        source: resolved.registered.source,
        start: start,
        end: end,
        verdict: verdict,
        standing: standing,
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
