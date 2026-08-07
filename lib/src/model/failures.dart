import 'names.dart';

/// Something this framework refused, or could not do.
///
/// Sealed, so a caller that reacts to failures has to account for every kind, and a new kind breaks
/// the build at every such place rather than falling into a catch-all.
///
/// These are exceptions and not errors on purpose. Every one of them is a condition the engine is
/// built to meet and report — a program that does not add up, a step reaching for something the
/// mode forbids — and catching it in order to record it properly is the whole point. An error would
/// have to be left to crash the process, which would lose the record.
sealed class EngineFailure implements Exception {
  const EngineFailure(this.message);

  /// What went wrong, written for whoever has to act on it.
  final String message;

  @override
  String toString() => message;
}

/// A step tried to change something in a mode that does not allow changes.
///
/// This is the dry run's guarantee doing its work. Reaching this means a step performed a mutation
/// from inside a code path that a dry run enters — almost always its own check or plan — and the
/// port stopped it before it reached the machine.
final class MutationRefused extends EngineFailure {
  /// Records that [what] was refused because the run is only planning.
  const MutationRefused(this.what, {required this.step}) : super('refused while planning: $what');

  /// What the step tried to do.
  final String what;

  /// The step that tried.
  final StepName step;
}

/// A program file does not add up.
///
/// Raised by the loader before anything is looked at or touched: an unknown step name, an unknown
/// predicate, an argument a step does not accept, a required argument that is missing, a value of
/// the wrong kind, a failure policy that is not one of the three.
final class ProgramInvalid extends EngineFailure {
  /// Records that a program file is invalid, at [where], because [message].
  const ProgramInvalid(super.message, {required this.where});

  /// Where in the file the problem is, as far as it can be located.
  final String where;

  @override
  String toString() => '$where: $message';
}

/// The configuration says which plugins are active, and the answer does not add up.
///
/// Raised before a program file is even read, because which steps exist at all is decided here. It
/// carries every problem at once for the same reason the loader does: a configuration is fixed in
/// one pass rather than one error per attempt.
final class PluginRejected extends EngineFailure {
  /// Records that the active set was refused, because [message].
  const PluginRejected(super.message);
}

/// A run was asked for that the gate does not allow yet.
///
/// The three modes gate each other, and the gate lives here rather than in whatever started the
/// run — so it holds for a person pressing a button and for another program calling the command
/// line alike. A gate in the user interface is a gate that can be walked around.
final class GateNotMet extends EngineFailure {
  /// Records that [wanted] was refused because [required] has not succeeded for this input.
  const GateNotMet({required this.wanted, required this.required})
    : super('$wanted needs a successful $required for the same input first');

  /// The mode that was asked for.
  final String wanted;

  /// The mode that has to have succeeded first.
  final String required;
}

/// A command returned something other than zero.
///
/// The message carries the command and what it wrote to standard error, because that pair is what
/// an operator reads first and having to open the record to find it is one step too many.
final class CommandFailed extends EngineFailure {
  /// Records that [argv] returned [exitCode].
  CommandFailed({required this.argv, required this.exitCode, required this.stderr})
    : super(
        stderr.trim().isEmpty
            ? '${argv.join(' ')} returned $exitCode'
            : '${argv.join(' ')} returned $exitCode: ${stderr.trim()}',
      );

  /// The command that failed.
  final List<String> argv;

  /// What it returned.
  final int exitCode;

  /// What it wrote to standard error.
  final String stderr;
}

/// A wait reached its deadline without what it was waiting for becoming true.
final class WaitedTooLong extends EngineFailure {
  /// Records that [waitingFor] did not become true within [deadline].
  WaitedTooLong({required this.waitingFor, required this.deadline})
    : super('waited ${deadline.inSeconds}s for $waitingFor and it did not happen');

  /// What was being waited for.
  final String waitingFor;

  /// How long it was waited for.
  final Duration deadline;
}

/// A request came back with a status the step does not accept.
final class RequestRefused extends EngineFailure {
  /// Records that [method] to [url] answered [status].
  RequestRefused({
    required this.method,
    required this.url,
    required this.status,
    required this.body,
  }) : super('$method $url answered $status');

  /// The request method.
  final String method;

  /// Where it went.
  final String url;

  /// What came back.
  final int status;

  /// The body that came with it, redacted before it reaches the record.
  final String body;
}

/// A machine role does not match the program.
final class RoleMismatch extends EngineFailure {
  /// Records that [program] does not apply to a machine of [role].
  const RoleMismatch({required this.program, required this.role, required this.applies})
    : super('$program applies to $applies, and this machine is $role');

  /// The program that was asked for.
  final String program;

  /// What this machine is.
  final String role;

  /// What the program says it applies to.
  final String applies;
}
