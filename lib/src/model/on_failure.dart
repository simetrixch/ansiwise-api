/// What the engine does when a step fails.
///
/// A program declares this per step. The three values are the whole vocabulary: a step that fails
/// either ends the run, or is carried to the end of the run as a reported problem, or is noted and
/// otherwise ignored.
enum OnFailure {
  /// The run ends here. Nothing after this step is attempted.
  ///
  /// For a step whose successors cannot work without it — there is no point installing an addon
  /// into a cluster that never came up.
  die,

  /// The run continues, and the failure is carried to the end and reported there.
  ///
  /// For a step whose absence leaves the machine usable but incomplete: a cluster without a working
  /// certificate issuer stands, it just cannot issue a certificate.
  issue,

  /// The run continues and the failure is recorded, but it is not carried to the end.
  ///
  /// For a step that is a convenience rather than a requirement.
  warn,
}
