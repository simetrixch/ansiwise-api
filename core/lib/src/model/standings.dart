import 'package:meta/meta.dart';

import 'step_standing.dart';

/// How many rows of a run were measured, how many were taken on trust, and how many did not run.
///
/// The three numbers a run ends with. A bare "succeeded" answers a different question from the one
/// an operator is asking after a real run — they know it did not fail, and what they need to know is
/// how much of it anything actually looked at.
///
/// Counted in ONE place and read from there by both the record and the closing event, so the number
/// somebody tailing a run sees and the number in the record it leaves behind cannot disagree.
@immutable
final class Standings {
  /// Counts a run of [proven] measured rows, [declared] trusted ones and [skipped] rows that did
  /// not run.
  const Standings({this.proven = 0, this.declared = 0, this.skipped = 0});

  /// Counts what [standings] holds, one entry per row of the run.
  factory Standings.of(Iterable<StepStanding> standings) {
    int proven = 0;
    int declared = 0;
    int skipped = 0;
    for (final StepStanding standing in standings) {
      switch (standing) {
        case StepStanding.proven:
          proven++;
        case StepStanding.declared:
          declared++;
        case StepStanding.skipped:
          skipped++;
      }
    }
    return Standings(proven: proven, declared: declared, skipped: skipped);
  }

  /// How many rows the framework measured.
  final int proven;

  /// How many rows carry something nothing measured.
  final int declared;

  /// How many rows did not run.
  final int skipped;

  /// Every row of the run, which is the three added up.
  int get total => proven + declared + skipped;

  /// Whether every row that ran was measured and none was waived.
  ///
  /// The one question this type exists to be able to answer honestly. A run with a single declared
  /// row is not fully proven, however green everything else came back.
  bool get fullyProven => declared == 0 && skipped == 0;

  /// The three numbers as the closing line states them.
  ///
  /// Separately and always all three, including the zeroes: a line that dropped the empty ones would
  /// read as though those states did not exist, and the reader could not tell "nothing was skipped"
  /// from "skipping is not counted here".
  String get summary => '$proven proven, $declared declared, $skipped skipped';

  @override
  bool operator ==(Object other) =>
      other is Standings &&
      other.proven == proven &&
      other.declared == declared &&
      other.skipped == skipped;

  @override
  int get hashCode => Object.hash(proven, declared, skipped);

  @override
  String toString() => summary;
}
