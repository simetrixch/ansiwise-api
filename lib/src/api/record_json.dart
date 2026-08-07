import '../model/run_event.dart';
import '../model/run_record.dart';

/// Turns the record types into what goes on the wire.
///
/// An interface and not a function, because the same shapes are written to the file on the machine
/// and sent to the client, and those two must not drift apart. One implementation serves both: a
/// client reading a run over the network and an operator reading `events.jsonl` on the machine see
/// the same objects, which is why an exported run can be opened later by the same reader.
abstract interface class RecordJson {
  /// One run's header and its step rows.
  Map<String, Object?> run(RunRecord record);

  /// One event.
  Map<String, Object?> event(RunEvent event);
}
