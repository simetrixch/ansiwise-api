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
  Future<RunId> start({required ProgramName program, required Mode mode}) async {
    final RunId id = newRunId();
    await Process.start(
      executable,
      <String>[program.value, '--mode', mode.flag, '--run', id.value],
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    );
    return id;
  }
}
