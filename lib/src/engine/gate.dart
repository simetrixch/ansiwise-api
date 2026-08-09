import '../domain/run_store.dart';
import '../model/failures.dart';
import '../model/mode.dart';
import '../model/names.dart';
import '../model/run_record.dart';

/// Decides whether a run may start.
///
/// The three modes gate each other: a dry run needs a test that held, and a real run needs a dry run
/// that came back clean for exactly the same input. This is the feature the whole rebuild exists for
/// — the operator gets three buttons and each one unlocks the next.
///
/// It lives here rather than in whatever started the run. A gate in a user interface is a gate that
/// can be walked around: the command line would still be open, and so would another program calling
/// in. Here there is one door.
final class Gate {
  /// Creates a gate that asks [store] what has already run.
  const Gate(this.store);

  /// Where the record of previous runs is read from.
  final RunStore store;

  /// Admits a run of [program] in [mode] for [fingerprint], or refuses it.
  ///
  /// Throws [GateNotMet] naming what has to succeed first. Returns the run it was satisfied by, so a
  /// caller can show the operator which dry run they are acting on — a gate that only says yes
  /// leaves them guessing whether it was the one they just looked at.
  Future<RunRecord?> admit({
    required Mode mode,
    required ProgramName program,
    required String fingerprint,
  }) async {
    switch (mode) {
      case Mode.test:
        // Nothing precedes a test. It changes nothing and reads nothing it has not been given, so
        // there is nothing it could be too early for.
        return null;

      case Mode.dry:
        // A dry run is likewise safe by construction — the ports refuse every mutation — so it is
        // not gated on the test having been run separately. It performs the test's work on its way
        // through: the program is resolved and the predicates are measured before any step plans.
        return null;

      case Mode.run:
        final RunRecord? clean = await store.lastCleanDryRun(
          program: program,
          fingerprint: fingerprint,
        );
        if (clean == null) {
          throw const GateNotMet(wanted: 'run', required: 'dry');
        }
        return clean;
    }
  }
}
