import 'package:meta/meta.dart';

import '../model/names.dart';

/// One value a step takes off the machine during a run and publishes for a later row to use.
///
/// **What this exists for.** Two packages that must not depend on each other measured the same
/// thing twice, because the framework had no channel by which a step could hand a VALUE to a later
/// one: a condition answers yes or no, and an answer comes from the operator before the run. This
/// is that channel, and it is deliberately the narrowest one that carries the case: a NAME standing
/// for exactly one piece of text.
///
/// **It is a mechanism and not a language.** A row names the measurement it takes and nothing else.
/// There is no expression over it, no condition on it, no part of it and no arithmetic with it — the
/// moment a program file could compute from a measured value, what is being debugged would be the
/// file instead of the code.
///
/// **What it costs, stated here because it is the whole of the trade.** A value measured while the
/// run is going cannot be in the fingerprint the gate spoke on, which is built from the resolved
/// program before the first step runs. So a row that takes one is never counted among the measured
/// rows: the dry run says the value is not known yet, and the record of the real run says the row
/// was declared rather than proven.
@immutable
final class MeasurementSpec {
  /// Declares that a step publishes [name].
  const MeasurementSpec({required this.name, required this.describes, this.secret = false});

  /// The name a row writes to take this value.
  ///
  /// The name the STEP publishes. A row may publish it under another name, and the step is never
  /// told: the sink the engine hands it takes this name and writes the row's.
  final MeasurementName name;

  /// What was measured, in one line, for the plan the operator reads before starting.
  final String describes;

  /// Whether what is published under [name] is a credential.
  ///
  /// **Declared in code by the step that produces the value, never chosen by a row.** A row that
  /// could flag secrecy is a row that could forget it, and a credential nobody marked is one nothing
  /// hides. The step knows what it read; the file does not.
  ///
  /// **What follows from it happens without anybody asking.** The run's own sink registers the value
  /// with the redactor at the moment it is published, before the value is stored under its name.
  /// From then on the one shared redactor hides it wherever it appears, on every surface of the run.
  ///
  /// **It reaches forward and not back, and that is the whole of what it promises.** Nothing can be
  /// taken out of a line already written, so whatever the step did with the value BEFORE it
  /// published stands in the record as it was written: the output of the command that produced it,
  /// where the row said `keep_output` or the command failed, and any line the step logged itself.
  /// A step publishes what it measured before it does anything else with it.
  ///
  /// **It is also half of a matching rule the resolver holds.** An argument declared secret takes
  /// only a measurement declared secret, and an argument that is not secret takes only one that is
  /// not. An argument a program calls secret and fills from an unregistered value would tell a
  /// reader the value is hidden while the record carries it in the clear.
  final bool secret;
}

/// Where a step publishes what it measured.
///
/// Narrow on purpose: a step may PUT a value in and cannot take one out. A step that could read
/// another step's measurement directly would be reaching for a value that is in none of its declared
/// arguments — invisible to the fingerprint, which is the one thing the row-level wiring exists to
/// keep visible.
abstract interface class MeasurementSink {
  /// The sink of a context that is not part of a run.
  ///
  /// Publishing into it throws rather than dropping the value. A measurement nothing collects is a
  /// measurement no row can read, and a sink that swallowed it would let a step believe it had
  /// handed something on.
  static const MeasurementSink none = _NothingCollects();

  /// Publishes [value] under [name].
  ///
  /// Throws when the step's registry entry does not declare [name], and when [value] is empty. A
  /// step publishes what it READ; where it read nothing it publishes nothing and says so through
  /// its check, because "the machine answered with an empty string" and "nothing here could be
  /// read" are different facts and the row that takes the value cannot tell them apart afterwards.
  ///
  /// [name] is the name the STEP declares, always. What a row of a program publishes it under is the
  /// sink's business, and a step that had to know would be a step that could get it wrong.
  ///
  /// Where the spec declaring [name] says the value is secret, this is where it is registered with
  /// the run's redactor, and every line written from here on hides it. A line written before it
  /// cannot have anything taken out of it, so a step publishes a measured credential before it logs
  /// it or hands it to another port.
  void publish(MeasurementName name, String value);
}

/// What [MeasurementSink.none] is.
@immutable
final class _NothingCollects implements MeasurementSink {
  const _NothingCollects();

  @override
  void publish(MeasurementName name, String value) {
    throw ArgumentError.value(
      name.value,
      'name',
      'this context is not part of a run, so nothing collects measurements and no row could read '
          'this one',
    );
  }
}
