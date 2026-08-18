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
///
/// **It can be waived, and a waiver is never a lie.** Without [requireDryRun] an operator who knows
/// what they are doing has no way past this except to make the framework's guarantee meaningless
/// everywhere. Absent, the gate holds; an installation that decided otherwise says so once in its
/// own configuration. What a waiver does NOT do is change what the run then claims: [admit] hands
/// back nothing to have been satisfied by, the run records that the proof was waived, and its
/// closing line still states the three standings apart.
final class Gate {
  /// Creates a gate that asks [store] what has already run.
  ///
  /// [requireDryRun] is true unless an installation's configuration turned it off, so a caller that
  /// says nothing gets the gate.
  const Gate(this.store, {this.requireDryRun = true});

  /// Where the record of previous runs is read from.
  final RunStore store;

  /// Whether a real run still needs a clean dry run of the same input behind it.
  final bool requireDryRun;

  /// Admits a run of [program] in [mode] for [fingerprint], or refuses it.
  ///
  /// Throws [GateNotMet] naming what has to succeed first. Returns the run it was satisfied by, so a
  /// caller can show the operator which dry run they are acting on — a gate that only says yes
  /// leaves them guessing whether it was the one they just looked at. Null is that same answer for a
  /// mode nothing precedes, and for a gate this installation waived.
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
        if (!requireDryRun) {
          // The store is not even asked. A waived gate that went looking anyway would report a dry
          // run it happened to find as the one this run was proven by, and it was not — the operator
          // decided to go without a proof, and the record has to say that and not something better.
          return null;
        }
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
