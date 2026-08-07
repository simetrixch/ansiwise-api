/// Time, asked for rather than taken.
///
/// A step that waits for something calls this. Injecting it is what makes a timeout testable: a
/// test that had to wait out a real five-minute deadline would not be run, and a wait nobody tests
/// is a wait that hangs the first time the machine is slow.
abstract interface class Clock {
  /// The current moment, in UTC.
  DateTime now();

  /// Waits for [duration].
  Future<void> sleep(Duration duration);
}
