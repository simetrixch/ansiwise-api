/// The three ports as every step receives them: whatever they carry out reaches the record,
/// attributed to the step, with secrets already removed.
///
/// This is why nothing in this framework logs. A step that runs a command has recorded it, because
/// running it is what recorded it. The shell this replaces spent its comments on which output
/// escaped its logging function — the raw output of the tools it called, what a container echoed, a
/// sibling script's own writing — and answered it by capturing a byte stream and slicing it by
/// offset. Here there is no escape to answer: a step reaches outside only through these.
library;

import 'dart:convert' show LineSplitter;

import '../domain/files.dart';
import '../domain/http.dart';
import '../domain/recorder.dart';
import '../domain/shell.dart';
import '../domain/step_log.dart';
import '../model/names.dart';
import '../model/run_event.dart';
import 'redactor.dart';

/// A shell that records every command it runs.
final class RecordingShell implements Shell {
  /// Wraps [inner] so that every command reaches [recorder], attributed to [step].
  const RecordingShell(
    this.inner, {
    required this.recorder,
    required this.redactor,
    required this.step,
  });

  /// The shell that actually runs the command.
  final Shell inner;

  /// Where the events go.
  final Recorder recorder;

  /// What is removed from the output before it is recorded.
  final Redactor redactor;

  /// The step the commands belong to.
  final StepName step;

  @override
  Future<CommandResult> run(Command command) async {
    recorder.record(
      (int sequence, DateTime at) => CommandStarted(
        sequence: sequence,
        at: at,
        step: step,
        argv: redactor.hideAll(command.argv),
        workingDirectory: command.workingDirectory,
      ),
    );

    final CommandResult result = await inner.run(command);

    _recordLines(result.stdout, OutputStream.stdout);
    _recordLines(result.stderr, OutputStream.stderr);

    recorder.record(
      (int sequence, DateTime at) => CommandFinished(
        sequence: sequence,
        at: at,
        step: step,
        exitCode: result.exitCode,
        elapsed: result.elapsed,
      ),
    );
    return result;
  }

  void _recordLines(String text, OutputStream stream) {
    if (text.isEmpty) {
      return;
    }
    // Split rather than record the block whole: the record is read line by line, and a client that
    // reconnected asks for everything after a sequence number, which only means something if one
    // line is one event.
    for (final String line in LineSplitter.split(text)) {
      recorder.record(
        (int sequence, DateTime at) => Output(
          sequence: sequence,
          at: at,
          step: step,
          stream: stream,
          text: redactor.hide(line),
        ),
      );
    }
  }
}

/// A file system that records every write.
final class RecordingFiles implements Files {
  /// Wraps [inner] so that every write reaches [recorder], attributed to [step].
  const RecordingFiles(this.inner, {required this.recorder, required this.step});

  /// The file system that actually carries out the operation.
  final Files inner;

  /// Where the events go.
  final Recorder recorder;

  /// The step the operations belong to.
  final StepName step;

  @override
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<String> read(String path) => inner.read(path);

  @override
  Future<List<String>> list(String path) => inner.list(path);

  @override
  Future<void> write(String path, String content, {required int mode}) async {
    final bool existed = await inner.exists(path);
    await inner.write(path, content, mode: mode);
    recorder.record(
      (int sequence, DateTime at) => FileWritten(
        sequence: sequence,
        at: at,
        step: step,
        path: path,
        bytes: content.length,
        created: !existed,
      ),
    );
  }

  @override
  Future<void> delete(String path) async {
    final bool existed = await inner.exists(path);
    await inner.delete(path);
    if (existed) {
      recorder.record(
        (int sequence, DateTime at) => Note(
          sequence: sequence,
          at: at,
          step: step,
          level: NoteLevel.info,
          message: 'deleted $path',
        ),
      );
    }
  }

  @override
  Future<void> createDirectory(String path, {required int mode}) async {
    final bool existed = await inner.exists(path);
    await inner.createDirectory(path, mode: mode);
    if (!existed) {
      recorder.record(
        (int sequence, DateTime at) => Note(
          sequence: sequence,
          at: at,
          step: step,
          level: NoteLevel.info,
          message: 'created directory $path',
        ),
      );
    }
  }
}

/// A network port that records every request.
final class RecordingHttp implements Http {
  /// Wraps [inner] so that every request reaches [recorder], attributed to [step].
  const RecordingHttp(
    this.inner, {
    required this.recorder,
    required this.redactor,
    required this.step,
  });

  /// The port that actually sends the request.
  final Http inner;

  /// Where the events go.
  final Recorder recorder;

  /// What is removed from the address before it is recorded.
  final Redactor redactor;

  /// The step the requests belong to.
  final StepName step;

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    final HttpAnswer answer = await inner.send(request);
    recorder.record(
      (int sequence, DateTime at) => RequestSent(
        sequence: sequence,
        at: at,
        step: step,
        method: request.method,
        url: redactor.hide(request.url),
        status: answer.status,
      ),
    );
    return answer;
  }
}

/// What a step says in its own words, on its way to the record.
final class RecordingLog implements StepLog {
  /// Sends every note to [recorder], attributed to [step].
  const RecordingLog({required this.recorder, required this.redactor, required this.step});

  /// Where the events go.
  final Recorder recorder;

  /// What is removed before the note is recorded.
  final Redactor redactor;

  /// The step the notes belong to.
  final StepName step;

  @override
  void info(String message) => _note(NoteLevel.info, message);

  @override
  void warn(String message) => _note(NoteLevel.warning, message);

  void _note(NoteLevel level, String message) {
    recorder.record(
      (int sequence, DateTime at) => Note(
        sequence: sequence,
        at: at,
        step: step,
        level: level,
        message: redactor.hide(message),
      ),
    );
  }
}
