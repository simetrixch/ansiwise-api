import 'package:meta/meta.dart';

/// Running a command is one of the three ways this framework reaches outside.
///
/// A step never starts a process itself. It asks this. That is what lets a dry run refuse a
/// mutation, a test replace the machine with a fake, and every command reach the record without
/// anyone remembering to log it.
abstract interface class Shell {
  /// Runs [command] and returns what it did.
  ///
  /// Does not throw on a non-zero exit — the exit code is data, and what it means is the step's
  /// business. It throws only when the command could not be started at all, or when the mode
  /// forbids it.
  Future<CommandResult> run(Command command);
}

/// A command, described rather than written out.
@immutable
final class Command {
  /// Describes a command.
  ///
  /// The executable is its own parameter rather than the first entry of a list, so a command with
  /// nothing to run cannot be written down. A list with a length rule enforced by an assertion
  /// would say the same thing later, at run time, and only in a build that keeps assertions.
  const Command(this.executable, [this.arguments = const <String>[]])
    : workingDirectory = null,
      environment = const <String, String>{},
      observes = false,
      timeout = null;

  /// Describes a command with everything about how it runs spelled out.
  const Command.detailed(
    this.executable, {
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
    this.observes = false,
    this.timeout,
  });

  /// Describes a command that only looks at the machine.
  const Command.observing(this.executable, [this.arguments = const <String>[]])
    : workingDirectory = null,
      environment = const <String, String>{},
      observes = true,
      timeout = null;

  /// What is run.
  final String executable;

  /// What is passed to it, each argument as its own entry.
  ///
  /// A list and never a command line. The values are passed to the process directly, so a
  /// credential containing a quote, a dollar sign or a newline is data and cannot become syntax.
  /// The whole class of quoting failures that shell scripts spend their comments on does not exist
  /// here.
  final List<String> arguments;

  /// The executable and its arguments together, for recording and for a plan.
  List<String> get argv => <String>[executable, ...arguments];

  /// The directory to run in, or null for the one the run itself is in.
  final String? workingDirectory;

  /// Variables added to the environment the command sees.
  final Map<String, String> environment;

  /// Whether this command only looks at the machine and changes nothing.
  ///
  /// The default is false, so a command that was never thought about counts as changing something.
  /// Under a dry run that makes it throw, loudly, at the step that issued it — which is what makes
  /// the dry-run guarantee hold without trusting anyone to have remembered.
  final bool observes;

  /// How long to wait before giving up, or null to wait as long as it takes.
  final Duration? timeout;
}

/// What a command did.
@immutable
final class CommandResult {
  /// Records what a command did.
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.elapsed,
  });

  /// What the command returned.
  final int exitCode;

  /// Everything it wrote to standard output.
  final String stdout;

  /// Everything it wrote to standard error.
  final String stderr;

  /// How long it took.
  final Duration elapsed;

  /// Whether it returned zero.
  bool get ok => exitCode == 0;

  /// Standard output with surrounding whitespace removed, which is what a step reading a single
  /// value out of a command wants.
  String get trimmed => stdout.trim();
}
