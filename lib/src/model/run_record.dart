import 'package:meta/meta.dart';

import 'mode.dart';
import 'names.dart';
import 'step_record.dart';

/// What one run was and how it ended.
///
/// Written when the run begins and completed when it ends, so a run that was killed still leaves a
/// header and its steps rather than nothing at all.
@immutable
final class RunRecord {
  /// Creates the record of one run.
  const RunRecord({
    required this.id,
    required this.program,
    required this.mode,
    required this.argv,
    required this.start,
    required this.stage,
    required this.role,
    required this.fqdn,
    required this.commit,
    required this.fingerprint,
    this.resumes,
    this.end,
    this.exitCode,
    this.steps = const <StepRecord>[],
    this.issues = const <String>[],
  });

  /// The run's identifier, unique on the machine that produced it.
  final RunId id;

  /// The program that was run.
  final ProgramName program;

  /// Which of the three modes it was run in.
  final Mode mode;

  /// How it was invoked, word for word.
  final List<String> argv;

  /// When it began, in UTC.
  final DateTime start;

  /// The stage this installation is.
  final Stage stage;

  /// The role of the machine it ran against.
  final Role role;

  /// The installation's domain name.
  ///
  /// This is installation state and lives only on the machine. It is never written to a file that
  /// belongs in the repository.
  final Fqdn fqdn;

  /// The commit of the branch that was executing.
  ///
  /// This is what makes every [StepRecord.source] still meaningful weeks later: the line numbers
  /// are the line numbers of this commit, not of whatever the branch holds today.
  final String commit;

  /// What makes two runs the same input.
  ///
  /// Computed from the program, the arguments every step resolved to, and the commit. The gate asks
  /// for a clean dry run with this exact value: a real run is refused unless one exists, and
  /// changing any answer changes the value, so an operator cannot get a green dry for one set of
  /// answers and then run a different set.
  final String fingerprint;

  /// The run this one continues, or null when it starts fresh.
  ///
  /// **Resuming does not skip anything.** It runs the same program again, and every step that
  /// already did its work answers that there is nothing to do — which is what idempotence is for.
  /// Skipping to a remembered position would be faster and worse: a machine somebody touched between
  /// the two runs would never be re-measured, and the run would build on a state nobody checked.
  ///
  /// What this field is for is the record. Without it a resumed run is a second, unrelated run, and
  /// an operator reading the history sees two halves of one story with nothing joining them.
  final RunId? resumes;

  /// When it ended, in UTC, or null while it is still running.
  final DateTime? end;

  /// What the process returned, or null while it is still running.
  final int? exitCode;

  /// One record per step that was reached.
  final List<StepRecord> steps;

  /// Everything reported as an issue, repeated at the run level.
  final List<String> issues;

  /// Whether the run has finished.
  bool get finished => end != null;

  /// Whether the run finished and reported nothing.
  bool get clean => exitCode == 0 && issues.isEmpty;

  /// A copy of this record with the closing fields filled in.
  RunRecord closed({
    required DateTime end,
    required int exitCode,
    required List<StepRecord> steps,
    required List<String> issues,
  }) => RunRecord(
    id: id,
    program: program,
    mode: mode,
    argv: argv,
    start: start,
    stage: stage,
    role: role,
    fqdn: fqdn,
    commit: commit,
    fingerprint: fingerprint,
    resumes: resumes,
    end: end,
    exitCode: exitCode,
    steps: steps,
    issues: issues,
  );
}
