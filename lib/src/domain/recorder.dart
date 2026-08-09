import '../model/run_event.dart';

/// The only thing in this framework that writes a record.
///
/// No step writes anywhere itself. Every command, every written file and every request reaches the
/// record through here, because the ports that carry them out report through here. That is why the
/// record is complete without anyone maintaining it.
///
/// It is also the single place a secret could otherwise reach a world-readable file, which is what
/// lets an implementation put redaction in one place instead of at every call site.
abstract interface class Recorder {
  /// Records one event.
  ///
  /// The caller supplies everything about the event except when it happened and where it sits in
  /// the run; [build] receives those two and returns the finished event. The sequence number is
  /// assigned here and nowhere else, so it is dense, ordered, and never reused.
  void record(RunEvent Function(int sequence, DateTime at) build);

  /// The number the next event will get.
  ///
  /// A step's record says which range of events belongs to it, and that range is what a client
  /// opens when the operator clicks the row. Reading the boundary is the alternative to emitting a
  /// marker event to find out where the boundary was — a marker that would then be in the record,
  /// meaning nothing to whoever read it.
  int get nextSequence;

  /// Finishes writing and releases whatever the record is being written to.
  ///
  /// A run that ends without this may leave its last events unwritten, so the runner calls it even
  /// when the run is ending because a step failed.
  Future<void> close();
}
