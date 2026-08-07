import 'package:meta/meta.dart';

/// What a step would change, produced by a dry run and never by a real one.
///
/// Sealed with one variant per kind of change a step can make, because those are exactly the three
/// ways out of this framework — a command, a file, a request — plus the case of a step that has
/// nothing to do.
@immutable
sealed class StepPlan {
  const StepPlan();

  /// The command that would run.
  const factory StepPlan.argv(List<String> argv, {String? workingDirectory, bool serverVerified}) =
      ArgvPlan;

  /// The file that would be written, and how it would differ from what is there now.
  const factory StepPlan.diff(String path, {required String before, required String after}) =
      DiffPlan;

  /// The request that would be sent.
  const factory StepPlan.request(String method, String url, {String? body}) = RequestPlan;

  /// Nothing would change, because the machine is already in the state this step produces.
  const factory StepPlan.nothing(String because) = NothingPlan;

  /// One line naming what would happen, for the plan the operator reads.
  String get summary;

  /// Whether the change was confirmed by the thing that would receive it, rather than predicted.
  ///
  /// A prediction says what we believe would happen. A server-side dry run says what the server
  /// answered when asked. The operator is shown which of the two they are reading, because they
  /// carry different weight when a plan looks wrong.
  bool get serverVerified => false;
}

/// A command that would run. See [StepPlan.argv].
@immutable
final class ArgvPlan extends StepPlan {
  /// Creates the plan of a step that would run [argv].
  const ArgvPlan(this.argv, {this.workingDirectory, this.serverVerified = false});

  /// The executable and its arguments, unquoted and unjoined.
  ///
  /// A list and not a command line: the value never passes through a shell, so a credential
  /// containing a quote or a dollar sign is data rather than syntax.
  final List<String> argv;

  /// The directory the command would run in, or null for the run's own.
  final String? workingDirectory;

  @override
  final bool serverVerified;

  @override
  String get summary => argv.join(' ');
}

/// A file that would be written. See [StepPlan.diff].
@immutable
final class DiffPlan extends StepPlan {
  /// Creates the plan of a step that would write [path].
  const DiffPlan(this.path, {required this.before, required this.after});

  /// The absolute path of the file.
  final String path;

  /// The current content, or the empty string when the file does not exist yet.
  final String before;

  /// The content that would be written.
  final String after;

  /// Whether the file does not exist yet.
  bool get creates => before.isEmpty;

  @override
  String get summary => creates ? 'create $path' : 'change $path';
}

/// A request that would be sent. See [StepPlan.request].
@immutable
final class RequestPlan extends StepPlan {
  /// Creates the plan of a step that would send [method] to [url].
  const RequestPlan(this.method, this.url, {this.body});

  /// The request method.
  final String method;

  /// The address the request would go to.
  final String url;

  /// The request body, redacted before it reaches the record.
  final String? body;

  @override
  String get summary => '$method $url';
}

/// Nothing would change. See [StepPlan.nothing].
///
/// This is what a step returns when its own check found the machine already in the state it
/// produces — the shape idempotence takes in a dry run.
@immutable
final class NothingPlan extends StepPlan {
  /// Creates the plan of a step that has nothing to do, because [because].
  const NothingPlan(this.because);

  /// Why there is nothing to do, in the operator's words.
  final String because;

  @override
  String get summary => 'nothing to do: $because';
}
