import 'dart:async';
import 'dart:convert';
// `dart:io` has an `HttpRequest` of its own, and so does this package. The one the test server
// hands out is the platform's; the one the port is given is ours.
import 'dart:io' hide HttpRequest;
import 'dart:io' as io show HttpRequest;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The four ports are the only code in the package that touches the machine, so they are the only
/// code whose tests touch it too. Everything above them is tested against the fakes.
///
/// The child process is Dart running a script written into the temporary directory. Not `echo` and
/// not `cmd /c`: those are two different programs on two platforms, and the property being tested —
/// that an argument arrives as the value it is, whatever is in it — would then be tested against a
/// different thing on each.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ansiwise-ports-');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      // A child that was just killed can still hold a handle for a moment on Windows.
    }
  });

  group('RealShell', () {
    late String script;

    setUp(() async {
      script = p.join(temp.path, 'child.dart');
      await File(script).writeAsString(_childScript);
    });

    test('an argument arrives as the value it is, whatever it holds', () async {
      const List<String> awkward = <String>[
        'a "quoted" value',
        r'$HOME; rm -rf /',
        'one\ntwo',
        r"it's `backticked` & piped |",
      ];

      final CommandResult result = await const RealShell().run(
        Command(Platform.resolvedExecutable, <String>[script, ...awkward]),
      );

      expect(result.exitCode, 0);
      expect(
        result.stdout.split(_separator),
        awkward,
        reason: 'no shell parsed any of it, so none of it could become syntax',
      );
    });

    test('a non-zero exit is data and not a failure', () async {
      final CommandResult result = await const RealShell().run(
        Command(Platform.resolvedExecutable, <String>[script, '--fail']),
      );

      expect(result.exitCode, 3);
      expect(result.ok, isFalse);
      expect(result.stderr, contains('something went wrong'));
    });

    test('the working directory and the environment are honoured', () async {
      final Directory work = await Directory(p.join(temp.path, 'work')).create();

      final CommandResult result = await const RealShell().run(
        Command.detailed(
          Platform.resolvedExecutable,
          arguments: <String>[script, '--context'],
          workingDirectory: work.path,
          environment: const <String, String>{'PASSED_THROUGH': 'from the caller'},
        ),
      );

      final List<String> answered = result.stdout.split(_separator);
      expect(p.basename(answered.first), 'work');
      expect(answered.last, 'from the caller');
    });

    test('a command that runs past its deadline is killed, not left running', () async {
      final String marks = p.join(temp.path, 'marks');

      await expectLater(
        const RealShell().run(
          Command.detailed(
            Platform.resolvedExecutable,
            arguments: <String>[script, '--append-forever', marks],
            timeout: const Duration(milliseconds: 600),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );

      // The child appends every 50ms for as long as it lives. Two samples half a second apart say
      // whether it is still alive: a process that was only abandoned would still be writing.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final int afterKill = await File(marks).length();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(await File(marks).length(), afterKill);
    });

    test('a command that cannot be started at all throws', () async {
      await expectLater(
        const RealShell().run(const Command('no-such-program-anywhere')),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('RealFiles', () {
    test('what was written is what is read back', () async {
      final String path = p.join(temp.path, 'thing.txt');
      await const RealFiles().write(path, 'the content', mode: 420);

      expect(await const RealFiles().read(path), 'the content');
      expect(await const RealFiles().exists(path), isTrue);
    });

    test('a write whose read-back does not match throws', () async {
      final String path = p.join(temp.path, 'surrogate.txt');

      // An unpaired surrogate cannot be encoded, so the file ends up holding the replacement
      // character instead. Every layer under this call reports success: the write returns and the
      // file exists. It is the read-back that says the file does not hold what was asked for.
      await expectLater(
        const RealFiles().write(path, 'before\u{D800}after', mode: 420),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(path).readAsString(), 'before\u{FFFD}after');
    });

    test('a directory is created with its parents, listed by name, and deleted whole', () async {
      final String nested = p.join(temp.path, 'one', 'two');
      await const RealFiles().createDirectory(nested, mode: 493);
      await const RealFiles().write(p.join(nested, 'b.txt'), 'b', mode: 420);
      await const RealFiles().write(p.join(nested, 'a.txt'), 'a', mode: 420);

      expect(await const RealFiles().list(nested), <String>['a.txt', 'b.txt']);

      await const RealFiles().delete(p.join(temp.path, 'one'));
      expect(await const RealFiles().exists(nested), isFalse);
    });

    test('deleting something that is not there does nothing', () async {
      await const RealFiles().delete(p.join(temp.path, 'never-existed'));
    });

    test(
      'the permission bits are the ones asked for',
      () async {
        final String path = p.join(temp.path, 'private.txt');
        await const RealFiles().write(path, 'a secret', mode: 384);

        expect(File(path).statSync().mode & 511, 384, reason: '0600 and nothing else');
      },
      skip: Platform.isWindows ? 'Windows has no POSIX permission bits' : null,
    );
  });

  group('RealHttp', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() async {
      await server.close(force: true);
    });

    String urlOf(String path) => 'http://${server.address.address}:${server.port}$path';

    test('a status the caller did not want comes back as data', () async {
      server.listen((io.HttpRequest request) {
        request.response.statusCode = 404;
        request.response.write('nothing here');
        unawaited(request.response.close());
      }, onError: (Object _) {});

      final HttpAnswer answer = await const RealHttp().send(HttpRequest('GET', urlOf('/missing')));

      expect(answer.status, 404);
      expect(answer.ok, isFalse);
      expect(answer.body, 'nothing here');
    });

    test('the method, headers and body are sent, and the answer comes back whole', () async {
      String? seenMethod;
      String? seenHeader;
      String? seenBody;

      server.listen((io.HttpRequest request) async {
        seenMethod = request.method;
        seenHeader = request.headers.value('x-ansiwise-test');
        seenBody = await utf8.decodeStream(request);
        request.response.headers.set('x-answered-by', 'the test');
        request.response.write('{"ok":true}');
        await request.response.close();
      }, onError: (Object _) {});

      final HttpAnswer answer = await const RealHttp().send(
        HttpRequest(
          'POST',
          urlOf('/things'),
          headers: const <String, String>{'x-ansiwise-test': 'a value'},
          body: '{"name":"one"}',
        ),
      );

      expect(seenMethod, 'POST');
      expect(seenHeader, 'a value');
      expect(seenBody, '{"name":"one"}');
      expect(answer.status, 200);
      expect(answer.body, '{"ok":true}');
      expect(answer.headers['x-answered-by'], 'the test');
    });

    test('a request that runs past its deadline throws', () async {
      // Accepted and then never answered, which is the case a connection timeout alone misses.
      server.listen((io.HttpRequest request) {}, onError: (Object _) {});

      await expectLater(
        const RealHttp().send(
          HttpRequest('GET', urlOf('/silent'), timeout: const Duration(milliseconds: 300)),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('RealClock', () {
    test('the time is UTC', () {
      expect(const RealClock().now().isUtc, isTrue);
    });

    test('a sleep waits at least as long as it was asked to', () async {
      final Stopwatch watch = Stopwatch()..start();
      await const RealClock().sleep(const Duration(milliseconds: 50));
      watch.stop();

      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 45)));
    });
  });
}

/// What the child puts between the values it prints. A character that cannot appear in the values
/// themselves, so an argument holding a newline is still one field.
const String _separator = '\u0001';

const String _childScript = r'''
import 'dart:io';

void main(List<String> arguments) {
  final String first = arguments.isEmpty ? '' : arguments.first;
  switch (first) {
    case '--context':
      stdout.write('${Directory.current.path}\u0001${Platform.environment['PASSED_THROUGH']}');
    case '--fail':
      stderr.writeln('something went wrong');
      exit(3);
    case '--append-forever':
      final File file = File(arguments[1]);
      while (true) {
        file.writeAsStringSync('.', mode: FileMode.append, flush: true);
        sleep(const Duration(milliseconds: 50));
      }
    default:
      stdout.write(arguments.join('\u0001'));
  }
}
''';
