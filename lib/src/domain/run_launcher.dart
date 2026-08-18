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
  /// [answers] is what the operator supplied, exactly as it arrived and not yet checked. The
  /// caller refuses a bad set before ever reaching here, and the run itself checks it again
  /// against the program's own declaration — the process that will act on a value is the one
  /// that has to be sure of it.
  ///
  /// [waived] names the proofs this run is going without, and travels for the same reason [resumes]
  /// does: it is known here, it is decided nowhere else, and the header the run writes has to carry
  /// it. An absent proof and a waived one look identical from the outside, so a run that did not
  /// carry the fact would leave a record nobody could tell apart from one that was gated normally.
  ///
  /// [resumes] names the run this one continues, and it changes nothing about what is run.
  /// A resumed run walks the same program from the top; every step that already did its work
  /// answers that there is nothing to do, and a machine somebody touched in between is measured
  /// again rather than assumed. What the identifier is for is the record — without it an operator
  /// reading the history sees two halves of one story with nothing joining them.
  Future<RunId> start({
    required ProgramName program,
    required Mode mode,
    Map<String, Object?> answers = const <String, Object?>{},
    RunId? resumes,
    List<Mode> waived = const <Mode>[],
  });
}
