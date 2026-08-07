/// The three ports as a dry run hands them out: everything that only looks is passed through,
/// everything that would change something is refused.
///
/// This is the second of the two guarantees a dry run rests on, and the one that does not depend on
/// anybody having written the step correctly. The first is that the engine calls a step's plan and
/// never its apply. This one holds even when that is not enough — when a check reaches for something
/// it should not, when a plan computes its difference by writing a temporary file, when a helper
/// three calls down grew a side effect nobody noticed in review.
///
/// It works because a step has no other way out. It cannot start a process, open a file or send a
/// request except through these, and a lint keeps it that way.
library;

import '../domain/files.dart';
import '../domain/http.dart';
import '../domain/shell.dart';
import '../model/failures.dart';
import '../model/names.dart';

/// A shell that refuses to run anything a step did not declare as only looking.
final class PlanningShell implements Shell {
  /// Wraps [inner] so that only observing commands reach it.
  const PlanningShell(this.inner, {required this.step});

  /// The shell that carries out the commands that are allowed through.
  final Shell inner;

  /// The step these commands belong to, named in the refusal.
  final StepName step;

  @override
  Future<CommandResult> run(Command command) {
    if (!command.observes) {
      throw MutationRefused(command.argv.join(' '), step: step);
    }
    return inner.run(command);
  }
}

/// A file system that answers every read and refuses every write.
final class PlanningFiles implements Files {
  /// Wraps [inner] so that only reads reach it.
  const PlanningFiles(this.inner, {required this.step});

  /// The file system that carries out the reads.
  final Files inner;

  /// The step these operations belong to, named in the refusal.
  final StepName step;

  @override
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<String> read(String path) => inner.read(path);

  @override
  Future<List<String>> list(String path) => inner.list(path);

  @override
  Future<void> write(String path, String content, {required int mode}) =>
      throw MutationRefused('write $path', step: step);

  @override
  Future<void> delete(String path) => throw MutationRefused('delete $path', step: step);

  @override
  Future<void> createDirectory(String path, {required int mode}) =>
      throw MutationRefused('create directory $path', step: step);
}

/// A network port that sends what only reads and refuses the rest.
final class PlanningHttp implements Http {
  /// Wraps [inner] so that only reading requests reach it.
  const PlanningHttp(this.inner, {required this.step});

  /// The port that carries out the requests that are allowed through.
  final Http inner;

  /// The step these requests belong to, named in the refusal.
  final StepName step;

  @override
  Future<HttpAnswer> send(HttpRequest request) {
    if (!request.observes) {
      throw MutationRefused('${request.method} ${request.url}', step: step);
    }
    return inner.send(request);
  }
}
