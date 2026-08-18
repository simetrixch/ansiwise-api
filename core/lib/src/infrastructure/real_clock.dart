import '../domain/clock.dart';

/// The machine's own time, and a wait that really waits.
///
/// The one port with nothing underneath it worth describing. It exists so that everything above can
/// take time as something it is handed rather than something it reaches for, which is what lets a
/// test wait out a five-minute deadline in no time at all.
final class RealClock implements Clock {
  /// Creates the clock a real run is given.
  const RealClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);
}
