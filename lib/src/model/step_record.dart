import 'package:meta/meta.dart';

import 'names.dart';
import 'step_plan.dart';
import 'verdict.dart';

/// What one step did, as one row in the run the operator reads.
///
/// The events carry the detail; this carries what a list of steps has to show without opening any
/// of them. [firstEvent] and [lastEvent] are how a row is opened: everything the step produced sits
/// between those two sequence numbers.
@immutable
final class StepRecord {
  /// Creates the record of one step.
  const StepRecord({
    required this.step,
    required this.source,
    required this.start,
    required this.end,
    required this.verdict,
    required this.firstEvent,
    required this.lastEvent,
    this.plan,
    this.issues = const <String>[],
  });

  /// The registered name of the step.
  final StepName step;

  /// Where its class is defined, as `path:line` relative to the repository root.
  ///
  /// Resolvable against the commit the run record pins, so a run from three weeks ago still points
  /// at the file that produced it.
  final String source;

  /// When it began, in UTC.
  final DateTime start;

  /// When it ended, in UTC.
  final DateTime end;

  /// How it ended.
  final Verdict verdict;

  /// The sequence number of this step's first event.
  final int firstEvent;

  /// The sequence number of this step's last event.
  final int lastEvent;

  /// What it would have changed, present only for a dry run.
  final StepPlan? plan;

  /// What it reported that the end of the run repeats.
  final List<String> issues;

  /// How long it took.
  Duration get elapsed => end.difference(start);
}
