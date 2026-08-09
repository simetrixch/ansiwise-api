/// The three ways a program can be executed, each gating the next.
///
/// The gating is enforced by the engine and not by whatever started it, so it holds for a person
/// clicking a button and for another program invoking the command line alike.
enum Mode {
  /// Resolve every step and predicate name against the registry, validate every argument against
  /// its step's schema, evaluate the predicates against this machine, and run each step's
  /// precondition check. Nothing outside is changed.
  ///
  /// What it produces is the real plan for this machine: every step that would run, and every step
  /// that would be skipped together with the predicate that skipped it.
  test,

  /// Ask every step what it would change, without changing it. Two independent guarantees hold at
  /// once: the engine calls the step's plan and never its apply, and the shell, file and network
  /// ports handed to the step throw on any operation the step did not declare read-only.
  dry,

  /// Do it. Refused unless a dry run for the same input has already succeeded.
  run;

  /// The name as it appears after `--mode` on the command line.
  String get flag => name;

  /// The mode that must have succeeded before this one may start, or null when there is none.
  Mode? get requires => switch (this) {
    Mode.test => null,
    Mode.dry => Mode.test,
    Mode.run => Mode.dry,
  };
}
