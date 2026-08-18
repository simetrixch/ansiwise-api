import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../domain/run_store.dart';
import '../model/mode.dart';
import '../model/names.dart';
import '../model/run_event.dart';
import '../model/run_record.dart';
import 'record_codec.dart';
import 'run_directory.dart';

/// Reads back what `FileRecorder` wrote.
///
/// This is the other half of the record and it never writes. A run in progress is being written by a
/// recorder in one process and read by this in another — the run itself is detached, and whoever is
/// watching it started later and may leave before it ends.
final class FileRunStore implements RunStore {
  /// Reads the runs kept under [directory].
  ///
  /// [poll] is how long it waits before looking at a live run's event file again.
  const FileRunStore({required this.directory, this.poll = const Duration(milliseconds: 200)});

  /// Where the runs are.
  final RunDirectory directory;

  /// How often the event file of a run that is still going is looked at again.
  ///
  /// Polling and not a file-system watch. A watch answers differently on each operating system, does
  /// not fire at all on some network file systems, and needs this same loop as a fallback anyway —
  /// so the fallback is the whole implementation.
  final Duration poll;

  static const RecordCodec _codec = RecordCodec();

  /// The byte a line ends with. A UTF-8 continuation byte is always 0x80 or above, so this value can
  /// only ever be a real line ending and never part of a character.
  static const int _lineEnd = 0x0a;

  @override
  Future<List<RunRecord>> list({ProgramName? program, Mode? mode, int limit = 50}) async {
    if (limit <= 0) {
      // `take` throws on a negative count, and a limit of nothing has one answer anyway.
      return const <RunRecord>[];
    }
    final List<RunRecord> runs = await _headers(program: program, mode: mode);
    return runs.length <= limit ? runs : runs.sublist(0, limit);
  }

  @override
  Future<RunRecord?> read(RunId id) => _header(id);

  @override
  Future<RunRecord?> lastCleanDryRun({
    required ProgramName program,
    required String fingerprint,
  }) async {
    final List<RunRecord> runs = await _headers(program: program, mode: Mode.dry);
    for (final RunRecord run in runs) {
      // Newest first, so the first match is the most recent one. The test is the exit code and not
      // [RunRecord.clean]: they agree — the runner returns 2 when a step reported an issue — and the
      // exit code is the value the gate is defined in terms of.
      if (run.exitCode == 0 && run.fingerprint == fingerprint) {
        return run;
      }
    }
    return null;
  }

  @override
  Stream<RunEvent> events(RunId id, {int from = 0}) {
    // A controller and not an `async*` generator, because of what cancelling one costs. A generator
    // notices that its listener has gone only when it reaches its next `yield`, and this loop may
    // have no more events to yield ever — a run that was killed writes neither a run-finished event
    // nor a closing header. The client's `cancel` would then never complete. Here the flag is read
    // once per turn, so leaving takes one poll interval at most.
    final StreamController<RunEvent> events = StreamController<RunEvent>();
    bool following = true;

    Future<void> follow() async {
      final File file = File(directory.events(id));
      int offset = 0;
      try {
        while (following) {
          // The header is read BEFORE the file, and that order is the whole of it. `run.json` only
          // says the run has ended once the last event has been written, so a read of the event file
          // that FOLLOWS a header saying so cannot be missing anything. The other order would let an
          // event land between the two reads and never be seen.
          final bool ended = await _hasEnded(id);
          final _Lines read = await _linesFrom(file, offset);
          offset = read.offset;

          for (final String line in read.lines) {
            if (!following) {
              return;
            }
            if (line.isEmpty) {
              continue;
            }
            final RunEvent event = _eventOf(line, file.path);
            if (event.sequence >= from) {
              events.add(event);
            }
            if (event is RunFinished) {
              return;
            }
          }

          if (ended) {
            return;
          }
          await Future<void>.delayed(poll);
        }
      } on Exception catch (failure, trace) {
        events.addError(failure, trace);
      } finally {
        await events.close();
      }
    }

    events.onListen = () => unawaited(follow());
    events.onCancel = () {
      following = false;
    };
    return events.stream;
  }

  Future<List<RunRecord>> _headers({ProgramName? program, Mode? mode}) async {
    final Directory root = Directory(directory.root);
    if (!await root.exists()) {
      return <RunRecord>[];
    }

    final List<RunRecord> runs = <RunRecord>[];
    await for (final FileSystemEntity entry in root.list(followLinks: false)) {
      if (entry is! Directory) {
        continue;
      }
      // A directory with no header is not a run — something else put it here, or a run's directory
      // was made and the process died before it wrote anything. Either way there is nothing to list.
      final RunRecord? record = await _header(RunId(p.basename(entry.path)));
      if (record == null) {
        continue;
      }
      if (program != null && record.program != program) {
        continue;
      }
      if (mode != null && record.mode != mode) {
        continue;
      }
      runs.add(record);
    }

    runs.sort(_newestFirst);
    return runs;
  }

  Future<RunRecord?> _header(RunId id) async {
    final File file = File(directory.header(id));
    if (!await file.exists()) {
      return null;
    }
    final Object? parsed = jsonDecode(await file.readAsString());
    if (parsed is! Map<String, Object?>) {
      // Not skipped quietly. The header is written whole and renamed into place, so a file here that
      // does not parse is real damage, and a list that silently left the run out would hide it.
      throw FormatException('${file.path} does not hold a run header');
    }
    return _codec.runFrom(parsed);
  }

  Future<bool> _hasEnded(RunId id) async {
    final RunRecord? header = await _header(id);
    return header != null && header.finished;
  }

  RunEvent _eventOf(String line, String path) {
    final Object? parsed = jsonDecode(line);
    if (parsed is! Map<String, Object?>) {
      throw FormatException('$path holds a line that is not an event');
    }
    return _codec.eventFrom(parsed);
  }

  Future<_Lines> _linesFrom(File file, int offset) async {
    if (!await file.exists()) {
      return _Lines(const <String>[], offset);
    }
    final RandomAccessFile handle = await file.open();
    try {
      final int length = await handle.length();
      if (length <= offset) {
        return _Lines(const <String>[], offset);
      }
      await handle.setPosition(offset);
      final Uint8List bytes = await handle.read(length - offset);

      // Read up to the last line ending and no further. What comes after it is a line the recorder
      // is still writing, and half a JSON object is not an event — it is a parse failure that would
      // end the stream of a run that is going perfectly well. The offset advances only over what was
      // whole, so the rest is read again next time round, by then complete.
      final int end = bytes.lastIndexOf(_lineEnd);
      if (end < 0) {
        return _Lines(const <String>[], offset);
      }
      return _Lines(utf8.decode(bytes.sublist(0, end)).split('\n'), offset + end + 1);
    } finally {
      await handle.close();
    }
  }

  static int _newestFirst(RunRecord a, RunRecord b) {
    final int byStart = b.start.compareTo(a.start);
    // Two runs can begin within the same microsecond. The identifier breaks the tie so the order is
    // total, and a list read twice does not come back in a different order the second time.
    return byStart != 0 ? byStart : b.id.value.compareTo(a.id.value);
  }
}

/// The complete lines read out of the event file, and where reading stopped.
final class _Lines {
  const _Lines(this.lines, this.offset);

  final List<String> lines;

  /// The byte after the last complete line, which is where the next read begins.
  final int offset;
}
