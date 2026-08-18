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
  const MeasurementSpec({required this.name, required this.describes});

  /// The name a row writes to take this value.
  final MeasurementName name;

  /// What was measured, in one line, for the plan the operator reads before starting.
  final String describes;
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
