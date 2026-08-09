import 'package:meta/meta.dart';

import 'names.dart';
import 'on_failure.dart';
import 'step_plan.dart';
import 'verdict.dart';

/// One thing that happened during a run.
///
/// A run is a stream of these while it is running and a file of these afterwards, and both carry
/// exactly the same events in the same order. That is what lets a client that reconnected read on
/// from the last sequence number it saw and miss nothing.
///
/// Every event is attributed to the step that produced it. The old shell had to capture a byte
/// stream and slice it by offset, because a command's own output escaped whatever logging function
/// it was supposed to go through. Here there is no escape: a step reaches outside only through the
/// shell, file and network ports, and every one of them emits its event.
@immutable
sealed class RunEvent {
  const RunEvent({required this.sequence, required this.at, required this.step});

  /// The position of this event in the run, counted from zero and never reused.
  ///
  /// A reconnecting client asks for everything after the last sequence it holds.
  final int sequence;

  /// When it happened, in UTC.
  final DateTime at;

  /// The step that produced it, or null for an event that belongs to the run itself.
  final StepName? step;

  /// The kind name written into the record, and the key a reader switches on.
  String get kind;
}

/// The run began. See [RunEvent].
@immutable
final class RunStarted extends RunEvent {
  /// Records the beginning of a run of [program] in [mode].
  const RunStarted({
    required super.sequence,
    required super.at,
    required this.program,
    required this.mode,
  }) : super(step: null);

  /// The program being run.
  final ProgramName program;

  /// The mode it is being run in, as it was written on the command line.
  final String mode;

  @override
  String get kind => 'run-started';
}

/// A condition was measured against this machine. See [RunEvent].
///
/// Every predicate a program uses is evaluated once, before the first step, so that every step sees
/// the same answers and a run cannot change its mind about the machine halfway through. These
/// events are what lets the first gate print the real plan: which steps will run, and which will be
/// skipped by which condition.
@immutable
final class PredicateEvaluated extends RunEvent {
  /// Records that [predicate] answered [held], because [because].
  const PredicateEvaluated({
    required super.sequence,
    required super.at,
    required this.predicate,
    required this.held,
    required this.because,
  }) : super(step: null);

  /// The registered name of the condition.
  final PredicateName predicate;

  /// Whether it holds on this machine.
  final bool held;

  /// What was found, in the operator's words.
  final String because;

  @override
  String get kind => 'predicate-evaluated';
}

/// A step began. See [RunEvent].
@immutable
final class StepStarted extends RunEvent {
  /// Records the beginning of a step, defined at [source].
  const StepStarted({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.source,
  });

  /// Where the step's class is defined, as `path:line` relative to the repository root.
  ///
  /// This is the reference the operator opens when a step fails. It names the file that does
  /// exactly this step, which is why one step is one class in one file.
  final String source;

  @override
  String get kind => 'step-started';
}

/// A command was started. See [RunEvent].
@immutable
final class CommandStarted extends RunEvent {
  /// Records the start of [argv].
  const CommandStarted({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.argv,
    this.workingDirectory,
  });

  /// The executable and its arguments, as they were passed — never joined into a command line.
  final List<String> argv;

  /// The directory it ran in, or null for the run's own.
  final String? workingDirectory;

  @override
  String get kind => 'command-started';
}

/// Which of a command's two output streams a line came from.
enum OutputStream {
  /// The command's standard output.
  stdout,

  /// The command's standard error.
  stderr,
}

/// A command wrote a line. See [RunEvent].
@immutable
final class Output extends RunEvent {
  /// Records one line a command wrote to [stream].
  const Output({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.stream,
    required this.text,
  });

  /// Which stream the line came from.
  final OutputStream stream;

  /// The line, with its trailing newline removed and secrets already redacted.
  final String text;

  @override
  String get kind => 'output';
}

/// A command ended. See [RunEvent].
@immutable
final class CommandFinished extends RunEvent {
  /// Records the end of a command with [exitCode].
  const CommandFinished({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.exitCode,
    required this.elapsed,
  });

  /// What the command returned.
  final int exitCode;

  /// How long it took.
  final Duration elapsed;

  @override
  String get kind => 'command-finished';
}

/// A file was written. See [RunEvent].
@immutable
final class FileWritten extends RunEvent {
  /// Records a write to [path].
  const FileWritten({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.path,
    required this.bytes,
    required this.created,
  });

  /// The file that was written.
  final String path;

  /// How many bytes were written.
  final int bytes;

  /// Whether the file did not exist before.
  final bool created;

  @override
  String get kind => 'file-written';
}

/// A request was sent. See [RunEvent].
@immutable
final class RequestSent extends RunEvent {
  /// Records a [method] request to [url] that answered [status].
  const RequestSent({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.method,
    required this.url,
    required this.status,
  });

  /// The request method.
  final String method;

  /// The address, with any credential in it already redacted.
  final String url;

  /// The status that came back.
  final int status;

  @override
  String get kind => 'request-sent';
}

/// What a step would have done, recorded in place of doing it. See [RunEvent].
@immutable
final class Planned extends RunEvent {
  /// Records the [plan] a step produced instead of acting.
  const Planned({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.plan,
  });

  /// What the step would have changed.
  final StepPlan plan;

  @override
  String get kind => 'planned';
}

/// How much weight a log line carries.
///
/// THE FOUR EVERY SYSTEM HAS, and that is the whole reason they are these four. Somebody who has
/// seen one of them knows the other three exist; a set invented here would have to be learned, and
/// the learning would happen while somebody is reading a record to find out what went wrong.
///
/// **Ordered from quietest to loudest**, because a run is configured by naming the quietest level it
/// writes. The order is the mechanism and not a presentation detail.
enum LogLevel {
  /// Detail that matters while something is being worked out, and not otherwise.
  debug,

  /// Something the operator may want to know.
  info,

  /// Something that is not right and did not stop the step.
  warn,

  /// Something that went wrong.
  ///
  /// Whether the run goes on is the program's `on_failure` for that step and is not decided here. A
  /// failure the run walked past is exactly the one a reader needs to find afterwards, so it is
  /// written at this level either way.
  error;

  /// Whether a run writing at [threshold] and louder writes this line.
  bool passes(LogLevel threshold) => index >= threshold.index;
}

/// A step said something in its own words. See [RunEvent].
///
/// For what a command's own output cannot say: which of several branches a step took, what it
/// found when it looked, why it decided there was nothing to do.
@immutable
final class Log extends RunEvent {
  /// Records [message] at [level].
  const Log({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.level,
    required this.message,
  });

  /// How much weight the line carries.
  final LogLevel level;

  /// The line itself, with secrets already redacted.
  final String message;

  @override
  String get kind => 'log';
}

/// A step ended. See [RunEvent].
@immutable
final class StepFinished extends RunEvent {
  /// Records the end of a step with [verdict].
  const StepFinished({
    required super.sequence,
    required super.at,
    required StepName super.step,
    required this.verdict,
    required this.elapsed,
  });

  /// How the step ended.
  final Verdict verdict;

  /// How long it took.
  final Duration elapsed;

  @override
  String get kind => 'step-finished';
}

/// The run ended. See [RunEvent].
@immutable
final class RunFinished extends RunEvent {
  /// Records the end of the run with [exitCode].
  const RunFinished({
    required super.sequence,
    required super.at,
    required this.exitCode,
    required this.issues,
  }) : super(step: null);

  /// What the process returns to whatever started it.
  final int exitCode;

  /// Everything a step reported under [OnFailure.issue], repeated here so a run that finished with
  /// three problems says so rather than looking clean.
  final List<String> issues;

  @override
  String get kind => 'run-finished';
}
