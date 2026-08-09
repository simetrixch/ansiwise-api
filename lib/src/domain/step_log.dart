/// What a step says in its own words.
///
/// For what a command's output cannot say: which of several branches the step took, what it found
/// when it looked, why it decided there was nothing to do. Everything written here reaches the
/// record attributed to the step that wrote it, and passes the redactor on the way.
abstract interface class StepLog {
  /// Notes something the operator may want to know.
  void info(String message);

  /// Notes something that is not right but does not stop the step.
  ///
  /// This is not a verdict. A step that cannot do its work fails; this is for the case where it did
  /// its work and something about the machine deserves saying.
  void warn(String message);
}
