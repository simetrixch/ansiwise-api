import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/shell.dart';

/// Runs a command by starting the process, and never by way of a shell.
///
/// `runInShell` stays false and there is no code path that turns it on. The executable and its
/// arguments are handed to the operating system as a list, so a value carrying a quote, a dollar
/// sign, a semicolon or a newline arrives at the process as that value. There is no string for it to
/// be part of, which is why the whole class of quoting failures a shell script spends its comments
/// on cannot occur here.
final class RealShell implements Shell {
  /// Creates the shell a real run is given.
  const RealShell();

  @override
  Future<CommandResult> run(Command command) async {
    final Stopwatch watch = Stopwatch()..start();
    final Process process = await Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      // Added to the environment rather than replacing it: null means the parent's environment is
      // passed through unchanged, and a map is merged on top of it.
      environment: command.environment.isEmpty ? null : command.environment,
      runInShell: false,
    );

    // Both streams are drained while the process is still running. A process whose output fills the
    // pipe buffer blocks on its next write until somebody reads, so collecting the output only after
    // waiting for the exit code deadlocks — and only once the output is large enough, which on a
    // deployment it eventually is.
    final Future<String> out = process.stdout.transform(_decoder).join();
    final Future<String> err = process.stderr.transform(_decoder).join();

    final int exitCode = await _waitFor(process, command);
    watch.stop();

    return CommandResult(
      exitCode: exitCode,
      stdout: await out,
      stderr: await err,
      elapsed: watch.elapsed,
    );
  }

  /// Malformed bytes become the replacement character instead of throwing. A command that writes
  /// something that is not UTF-8 has still run, and losing the whole run over one bad byte in a log
  /// line would be the wrong trade.
  static const Utf8Decoder _decoder = Utf8Decoder(allowMalformed: true);

  Future<int> _waitFor(Process process, Command command) async {
    final Duration? timeout = command.timeout;
    if (timeout == null) {
      return process.exitCode;
    }
    try {
      return await process.exitCode.timeout(timeout);
    } on TimeoutException {
      // Killed and then reaped, not abandoned. A command left running past its deadline goes on
      // changing the machine while the run that started it is already reporting a failure, and the
      // operator has no way of knowing that is happening.
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      throw TimeoutException('${command.argv.join(' ')} did not finish and was killed', timeout);
    }
  }
}
