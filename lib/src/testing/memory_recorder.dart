import '../domain/clock.dart';
import '../domain/recorder.dart';
import '../model/names.dart';
import '../model/run_event.dart';

/// A recorder that keeps everything in a list, for tests.
///
/// A test asserts on the record rather than on what a step returned, and that is deliberate: the
/// record is what an operator sees, so a step that did the right thing and recorded it wrongly is a
/// step that has failed at the part this system exists for.
final class MemoryRecorder implements Recorder {
  /// Creates a recorder that stamps its events from the given clock.
  MemoryRecorder(this._clock);

  final Clock _clock;

  /// Everything that was recorded, in order.
  final List<RunEvent> events = <RunEvent>[];

  /// Whether the recorder was closed.
  bool closed = false;

  @override
  int get nextSequence => events.length;

  @override
  void record(RunEvent Function(int sequence, DateTime at) build) {
    events.add(build(events.length, _clock.now()));
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  /// Every event of type [T].
  List<T> only<T extends RunEvent>() => events.whereType<T>().toList(growable: false);

  /// Every event attributed to [step].
  List<RunEvent> forStep(StepName step) =>
      events.where((RunEvent e) => e.step == step).toList(growable: false);

  /// Everything a command wrote, in order, whatever step it belonged to.
  List<String> get output => only<Output>().map((Output e) => e.text).toList(growable: false);

  /// Every log line, in order.
  List<String> get logLines => only<Log>().map((Log e) => e.message).toList(growable: false);
}
