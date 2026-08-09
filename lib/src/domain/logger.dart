/// How a step says something in its own words.
///
/// **Logging is what keeps this alive.** Nobody is watching the machine while a run happens, and the
/// record is the only way anybody ever learns what really occurred on it. So every step logs, at
/// every level, always — there is no situation in which saying less is the right answer, and the
/// level is how a reader afterwards decides what to look at rather than how a step decides what to
/// admit.
///
/// FOUR LEVELS, AND THEY ARE THE FOUR EVERY SYSTEM HAS. Somebody who has seen one of them knows the
/// other three exist, which is exactly what a closed set of words has to do and what a set invented
/// here would not.
library;

/// A step's own account of what it found and what it did.
abstract interface class Logger {
  /// Detail that matters while something is being worked out, and not otherwise.
  ///
  /// The branch that was taken, the value that was read, the path that was checked. A run at the
  /// default level does not carry it; a run somebody is debugging does, and then it is the
  /// difference between reading what happened and guessing at it.
  void debug(String message);

  /// Something the operator may want to know.
  void info(String message);

  /// Something that is not right and did not stop the step.
  ///
  /// This is not a verdict. A step that cannot do its work fails; this is for the case where it DID
  /// its work and something about the machine deserves saying.
  void warn(String message);

  /// Something that went wrong.
  ///
  /// Whether the run goes on is not decided here — that is the program's `on_failure` for this step.
  /// What this says is that something failed, and it says it whether the run continues or not: a
  /// failure the run walked past is exactly the one a reader needs to find afterwards.
  void error(String message);
}
