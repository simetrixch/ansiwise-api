import 'dart:io' show ProcessException;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// A wait put to a machine that cannot answer it yet.
///
/// **Why this file exists.** A wait is always on something an earlier step brings about, so the tool
/// it asks with is regularly not on the machine when the question is first put. That case reached
/// the shell as an exception and escaped: the step neither held nor failed, it disappeared, and the
/// run stopped on a stack trace where the truthful answer was "not yet".
///
/// It was found on a real machine and could not have been found anywhere else. A fake shell answers
/// an argv without the executable needing to exist, so every suite was green over a program that
/// stopped at its fourth step of fifty-five — in the mode whose whole purpose is to measure a machine
/// before anything is done to it.
void main() {
  test('a wait whose tool is not on the machine is not over, and does not throw', () async {
    final CheckResult answer = await const _WaitsForTheAbsent().check(_machine());

    expect(
      answer,
      isA<Ready>(),
      reason:
          'the tool an earlier step installs is not there yet, which is exactly the state this '
          'mode is pointed at — the wait is not over, and that is a measurement rather than a crash',
    );
  });

  test('a wait that CAN be asked and is not over is also not over', () async {
    // The innocent neighbour. Without it, a check that swallowed everything would look identical.
    expect(await const _WaitsForSomethingFalse().check(_machine()), isA<Ready>());
  });

  test('a wait that is over is satisfied', () async {
    expect(await const _WaitsForSomethingTrue().check(_machine()), isA<Satisfied>());
  });

  test('the deadline says WHY it could not be asked, not that nothing answered', () async {
    Object? thrown;
    try {
      await const _WaitsForTheAbsent().apply(_machine());
    } on Object catch (why) {
      thrown = why;
    }

    expect(thrown, isA<WaitedTooLong>());
    expect(
      '$thrown',
      contains('no-such-executable'),
      reason:
          'told only that the thing did not come up, an operator goes looking at the thing. The '
          'reason the question could not be put names the row instead',
    );
  });
}

StepContext _machine() => StepContext(
  shell: FakeShell(),
  files: FakeFiles(),
  http: FakeHttp(),
  clock: FakeClock(),
  entropy: FakeEntropy(),
  log: const _SilentLog(),
  step: const StepName('under_test'),
  arguments: Arguments.none,
  answers: Arguments.none,
  facts: Facts.none,
);

/// A wait whose asking throws, the way a missing executable does on a real machine.
final class _WaitsForTheAbsent extends ObservingStep with WaitStep {
  const _WaitsForTheAbsent();

  @override
  Duration get deadline => Duration.zero;

  @override
  Duration get interval => Duration.zero;

  @override
  String get waitingFor => 'the thing to come up';

  @override
  Future<bool> holds(StepContext context) async =>
      throw const ProcessException('no-such-executable', <String>['status'], 'No such file');
}

final class _WaitsForSomethingFalse extends ObservingStep with WaitStep {
  const _WaitsForSomethingFalse();

  @override
  Duration get deadline => Duration.zero;

  @override
  Duration get interval => Duration.zero;

  @override
  String get waitingFor => 'the thing to come up';

  @override
  Future<bool> holds(StepContext context) async => false;
}

final class _WaitsForSomethingTrue extends ObservingStep with WaitStep {
  const _WaitsForSomethingTrue();

  @override
  Duration get deadline => Duration.zero;

  @override
  Duration get interval => Duration.zero;

  @override
  String get waitingFor => 'the thing to come up';

  @override
  Future<bool> holds(StepContext context) async => true;
}

final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
