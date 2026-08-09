import '../model/mode.dart';
import '../model/names.dart';
import '../model/run_event.dart';
import '../model/run_record.dart';
import 'recorder.dart';

/// Everything this machine has recorded, read back.
///
/// The write side is not here — that is [Recorder], which every port already reports through. This
/// is the other half: what a client asks for when it lists past runs, opens one, or comes back to a
/// run it lost the connection to.
///
/// The two are deliberately separate interfaces over the same files. A run in progress is being
/// written by a recorder and read by a store at the same time, from different processes: the run
/// itself is detached, and whoever is watching it started later.
abstract interface class RunStore {
  /// The runs this machine has recorded, newest first.
  Future<List<RunRecord>> list({ProgramName? program, Mode? mode, int limit = 50});

  /// One run, or null when there is none by that name.
  Future<RunRecord?> read(RunId id);

  /// The events of [id], from sequence number [from] onwards.
  ///
  /// Continues while the run is still going and closes when it ends, so one call serves both
  /// watching a run happen and reading a finished one. `from` is what makes a dropped connection
  /// cost nothing: sequence numbers are dense and never reused, so asking for everything after the
  /// last one held misses nothing and repeats nothing.
  Stream<RunEvent> events(RunId id, {int from = 0});

  /// The most recent successful dry run of [program] for exactly this input, or null.
  ///
  /// This is what the gate asks. It lives here rather than in whatever starts a run, so it holds for
  /// a person pressing a button and for another program calling in — a gate in a user interface is
  /// a gate that can be walked around.
  Future<RunRecord?> lastCleanDryRun({required ProgramName program, required String fingerprint});
}
