import '../model/mode.dart';
import '../model/names.dart';

/// Starts a run and returns immediately.
///
/// A deployment takes an hour or more, and the session that asked for it must not have to stay open
/// for it. So starting is one thing and watching is another: this hands back the run's identifier as
/// soon as the run is going, and everything after that is read from the record.
///
/// An interface, because what "detached" means is the machine's business and not the API's. On a
/// machine with systemd it is `systemd-run`; a test replaces it with something that runs the program
/// in the same process, and nothing above here can tell the difference.
abstract interface class RunLauncher {
  /// Starts [program] in [mode] and returns the identifier of the run.
  ///
  /// Returns once the run is going, not once it is finished. A failure to START is thrown; a failure
  /// of the run itself is in the record, because by then there is nobody left waiting for it.
  Future<RunId> start({required ProgramName program, required Mode mode});
}
