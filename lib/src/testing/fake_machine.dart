/// A machine that exists only in memory, for tests.
///
/// Every step in this system is unit-testable, and this is what makes that true rather than
/// aspirational: a step reaches outside only through the five ports, so replacing them replaces the
/// world. The only code that cannot be tested this way is the thin real implementations, and that
/// is a category rather than a gap.
library;

import '../domain/clock.dart';
import '../domain/entropy.dart';
import '../domain/files.dart';
import '../domain/http.dart';
import '../domain/machine.dart';
import '../domain/shell.dart';

/// A shell that answers from a table instead of starting anything.
final class FakeShell implements Shell {
  /// Creates a shell that answers according to [answers].
  ///
  /// The key is the command joined by spaces. A command with no entry answers exit code zero and
  /// empty output, so a test only has to describe the commands it cares about.
  FakeShell([Map<String, CommandResult>? answers])
    : _answers = <String, CommandResult>{...?answers};

  final Map<String, CommandResult> _answers;
  final Map<String, void Function()> _effects = <String, void Function()>{};

  /// Every command that was run, in order, joined by spaces.
  final List<String> ran = <String>[];

  /// Every command that was run, unjoined.
  final List<Command> commands = <Command>[];

  /// The commands that were run AND had an effect on the rest of this fake machine.
  ///
  /// A caller that wants to know whether a step's work actually took effect here cannot read that
  /// from [ran]: a fake shell records every command, and one with no effect registered leaves the
  /// machine exactly as it was. This is the difference between the two.
  final Set<String> carriedOut = <String>{};

  /// Makes [argv] answer [result] from now on.
  void answer(String argv, CommandResult result) => _answers[argv] = result;

  /// Makes [argv] answer [stdout] at exit code zero.
  void answers(String argv, String stdout) => _answers[argv] = CommandResult(
    exitCode: 0,
    stdout: stdout,
    stderr: '',
    elapsed: Duration.zero,
  );

  /// Makes [argv] change the rest of the fake machine when it runs.
  ///
  /// A real command has an effect, and a step's postcondition is about that effect rather than
  /// about the exit code. Without this a test could only check that a command was issued, which is
  /// the very thing this framework refuses to accept as proof.
  void changes(String argv, void Function() effect) => _effects[argv] = effect;

  /// Makes [argv] answer [exitCode], with [stderr].
  void fails(String argv, {int exitCode = 1, String stderr = ''}) => _answers[argv] = CommandResult(
    exitCode: exitCode,
    stdout: '',
    stderr: stderr,
    elapsed: Duration.zero,
  );

  @override
  Future<CommandResult> run(Command command) async {
    final String key = command.argv.join(' ');
    ran.add(key);
    commands.add(command);
    final void Function()? effect = _effects[key];
    if (effect != null) {
      effect();
      carriedOut.add(key);
    }
    return _answers[key] ??
        const CommandResult(exitCode: 0, stdout: '', stderr: '', elapsed: Duration.zero);
  }
}

/// A file system held in a map.
final class FakeFiles implements Files {
  /// Creates a file system holding [initial].
  FakeFiles([Map<String, String>? initial]) : contents = <String, String>{...?initial};

  /// What each path holds.
  final Map<String, String> contents;

  /// The directories that exist.
  final Set<String> directories = <String>{};

  /// Every path that was written, in order.
  final List<String> written = <String>[];

  /// Every path that was deleted, in order.
  final List<String> deleted = <String>[];

  /// The permission bits each written path was given.
  final Map<String, int> modes = <String, int>{};

  @override
  Future<bool> exists(String path) async =>
      contents.containsKey(path) || directories.contains(path) || _holdsFiles(path);

  /// Whether any file sits under [path].
  ///
  /// A real file system has the directories its files are in, without anybody having created them
  /// separately. Without this a fake seeded with `/var/cache/apt/archives/one.deb` answers that
  /// `/var/cache/apt/archives` is not there, and a step that quite correctly checks the directory
  /// before listing it takes the wrong branch — in the test only, which is the worst kind.
  bool _holdsFiles(String path) => contents.keys.any((String p) => p.startsWith('$path/'));

  @override
  Future<String> read(String path) async {
    final String? content = contents[path];
    if (content == null) {
      throw StateError('no such file: $path');
    }
    return content;
  }

  @override
  Future<List<String>> list(String path) async => <String>[
    for (final String p in contents.keys)
      if (p.startsWith('$path/')) p.substring(path.length + 1),
  ];

  @override
  Future<void> write(String path, String content, {required int mode}) async {
    contents[path] = content;
    modes[path] = mode;
    written.add(path);
  }

  @override
  Future<void> delete(String path) async {
    contents.remove(path);
    directories.remove(path);
    deleted.add(path);
  }

  @override
  Future<void> createDirectory(String path, {required int mode}) async {
    directories.add(path);
    modes[path] = mode;
  }
}

/// A network port that answers from a table.
final class FakeHttp implements Http {
  /// Creates a port that answers according to [answers], keyed by `METHOD url`.
  FakeHttp([Map<String, HttpAnswer>? answers]) : _answers = <String, HttpAnswer>{...?answers};

  final Map<String, HttpAnswer> _answers;

  /// Every request that was sent, in order, as `METHOD url`.
  final List<String> sent = <String>[];

  /// Makes `METHOD url` answer [status] with [body].
  void answers(String key, {int status = 200, String body = ''}) => _answers[key] = HttpAnswer(
    status: status,
    body: body,
    headers: const <String, String>{},
    elapsed: Duration.zero,
  );

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    final String key = '${request.method} ${request.url}';
    sent.add(key);
    return _answers[key] ??
        const HttpAnswer(
          status: 200,
          body: '',
          headers: <String, String>{},
          elapsed: Duration.zero,
        );
  }
}

/// A clock that does not move unless a test moves it.
///
/// Waiting is free here, which is the only reason a step with a five-minute deadline has a test at
/// all. Every sleep is recorded, so a test can assert how long a step would have waited without
/// waiting it.
final class FakeClock implements Clock {
  /// Creates a clock reading [start], or a fixed moment when none is given.
  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026);

  DateTime _now;

  /// Every sleep that was asked for, in order.
  final List<Duration> slept = <Duration>[];

  /// How long the clock has been moved forward in total.
  Duration get elapsed => slept.fold(Duration.zero, (Duration a, Duration b) => a + b);

  @override
  DateTime now() => _now;

  @override
  Future<void> sleep(Duration duration) async {
    slept.add(duration);
    _now = _now.add(duration);
  }

  /// Moves the clock forward without recording a sleep.
  void advance(Duration duration) => _now = _now.add(duration);
}

/// Values that are predictable on purpose, and that no reader could take for a secret.
///
/// Two properties at once, and the second is what a plain counter would lose. A test asserts the
/// exact value a step minted, so the sequence has to repeat — and a fixture that reads like a real
/// credential is one somebody copies into something that then ships with it, so every value here
/// says what it is in the clear.
///
/// What comes out is `fa4e` followed by the draw's number, padded with zeroes to the length asked
/// for. It is hexadecimal, so it stands in wherever a real value would; and it is spelt with a four
/// because `k` is not a hexadecimal digit, which still leaves it readable as the word at a glance.
final class FakeEntropy implements Entropy {
  /// Creates a source whose first draw is numbered one.
  FakeEntropy();

  int _drawn = 0;

  /// How many values have been minted.
  int get drawn => _drawn;

  @override
  String hex(int bytes) {
    if (bytes < 1) {
      throw ArgumentError.value(bytes, 'bytes', 'a secret is at least one byte long');
    }
    _drawn++;
    final String marked = 'fa4e${_drawn.toRadixString(16).padLeft(4, '0')}';
    return marked.padRight(bytes * 2, '0').substring(0, bytes * 2);
  }
}

/// A machine made of the five fakes, ready to hand to a runner.
Machine fakeMachine({
  FakeShell? shell,
  FakeFiles? files,
  FakeHttp? http,
  FakeClock? clock,
  FakeEntropy? entropy,
}) => Machine(
  shell: shell ?? FakeShell(),
  files: files ?? FakeFiles(),
  http: http ?? FakeHttp(),
  clock: clock ?? FakeClock(),
  entropy: entropy ?? FakeEntropy(),
);
