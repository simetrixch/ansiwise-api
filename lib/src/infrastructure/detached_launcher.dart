import 'dart:convert';
import 'dart:io';

import '../domain/run_launcher.dart';
import '../model/mode.dart';
import '../model/names.dart';

/// Starts a run in a process of its own that outlives the session that asked for it.
///
/// A deployment takes an hour or more. The session that started it is an SSH connection from a
/// laptop, and that laptop will close — so the run must not be a child of the thing serving the
/// request. It is started detached: the parent hands back the run's id and can end, and the run
/// keeps writing its record for whoever comes back for it.
///
/// `ProcessStartMode.detached` rather than `systemd-run`, because it needs no init system and works
/// the same on any machine this could run on. What it does not give is a unit to inspect or stop
/// from outside — stopping a run is its own operation and is not built yet.
final class DetachedLauncher implements RunLauncher {
  /// Starts runs by invoking [executable] again, in [workingDirectory].
  const DetachedLauncher({
    required this.executable,
    required this.workingDirectory,
    required this.newRunId,
  });

  /// The binary to start, which is this one.
  final String executable;

  /// Where the child runs, so it finds the same programs and writes to the same record directory.
  final String workingDirectory;

  /// What names a run.
  ///
  /// Injected rather than taken from the clock here, so a test gets a name it chose and the id
  /// scheme lives in one place instead of in every caller.
  final RunId Function() newRunId;

  @override
  Future<RunId> start({
    required ProgramName program,
    required Mode mode,
    Map<String, Object?> answers = const <String, Object?>{},
    String? elevationPassword,
    RunId? resumes,
    List<Mode> waived = const <Mode>[],
  }) async {
    final RunId id = newRunId();
    // Sent whenever there is anything to send. The password is part of what a caller hands a run,
    // so a run with no answers and a password still gets stdio.
    final bool hasInputs = answers.isNotEmpty || elevationPassword != null;

    // OVER STDIN, and the two routes not taken are the reason.
    //
    // Not argv: a value there is in every process listing on the machine, and an answer a program
    // declared secret is a credential.
    //
    // Not a file: the run record is redacted before anything reaches it, and a file of raw answers
    // beside it would be the one thing on that disk that is not. It would also outlive the run
    // unless somebody remembered to remove it, and the process that could remember is the detached
    // one nobody is waiting for.
    //
    // Stdio is attached only when there is something to send. `detached` gives the child no handles
    // at all, which is what a run with nothing to be told should have.
    final Process child = await Process.start(
      executable,
      <String>[
        program.value,
        '--mode',
        mode.flag,
        '--run',
        id.value,
        // In argv rather than over stdin, and it belongs there: a run identifier is not a secret,
        // and it is the one thing about this run that a process listing may as well say.
        if (resumes case final RunId earlier) ...<String>['--resume', earlier.value],
        // Also argv, and for the same reason: which gate an installation waived is not a secret,
        // and the run has to write it into its own header where a reader will look for it.
        for (final Mode gate in waived) ...<String>['--waived', gate.flag],
        if (hasInputs) ...<String>['--answers', '-'],
      ],
      workingDirectory: workingDirectory,
      mode: hasInputs ? ProcessStartMode.detachedWithStdio : ProcessStartMode.detached,
    );

    if (hasInputs) {
      // Written and CLOSED. The child reads until end-of-input, so a pipe left open would hold it
      // at its first instruction forever — and this parent is a request handler that is about to
      // answer and forget the run exists.
      // THE ENVELOPE, never the bare answers. The child reads `{"answers": {...}}` with
      // `elevation_password` beside it, which is the one shape both doors into this engine take —
      // this one and the command line. Writing the bare map here is what made every run started
      // over the API die before it wrote its header, while the same run started by hand went
      // through: two doors, one of them speaking a shape the other had left behind.
      child.stdin.write(
        jsonEncode(<String, Object?>{
          'answers': answers,
          if (elevationPassword case final String password) 'elevation_password': password,
        }),
      );
      await child.stdin.flush();
      await child.stdin.close();
    }
    return id;
  }
}
