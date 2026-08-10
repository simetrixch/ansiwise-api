import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// A machine that needs no such file at all is not the same as a file that already holds the right
/// thing.
///
/// The second is what the check answers by comparing. The first is the machine having no business
/// with this file: a routing rule set where nothing is steered, a registry mirror where there is no
/// registry to mirror. There is nothing to write, nothing to plan, and nothing an undo could take
/// back.
///
/// WITHOUT THIS a step in that position could not use [FileStep] at all — `contentFor` must answer
/// with text and there is no text that means "no file" — so it wrote its own check, plan and apply
/// instead. Six steps of this platform's plugin did exactly that, which is eighteen methods
/// differing from the mixin only in this one case.
void main() {
  FakeFiles files = FakeFiles();

  StepContext contextOn(FakeFiles on) {
    files = on;
    return StepContext(
      shell: FakeShell(),
      files: on,
      http: FakeHttp(),
      clock: FakeClock(),
      entropy: FakeEntropy(),
      log: const _SaysNothing(),
      step: const StepName('under_test'),
      arguments: Arguments.none,
      facts: Facts.none,
    );
  }

  group('a machine that needs the file', () {
    test('is measured by comparing, as before', () async {
      final _Rules step = _Rules(needed: true);
      final StepContext context = contextOn(FakeFiles(<String, String>{'/one': 'old'}));

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(files.contents['/one'], _Rules.text);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('plans the difference', () async {
      final StepPlan plan = await _Rules(
        needed: true,
      ).plan(contextOn(FakeFiles(<String, String>{'/one': 'old'})));

      expect(plan, isA<DiffPlan>());
      expect((plan as DiffPlan).after, _Rules.text);
    });
  });

  group('a machine that needs no such file', () {
    test('is satisfied, and the operator is told why', () async {
      final CheckResult answer = await _Rules(needed: false).check(contextOn(FakeFiles()));

      expect(answer, isA<Satisfied>());
      expect((answer as Satisfied).because, _Rules.notHere);
    });

    test('plans nothing, carrying the same reason', () async {
      final StepPlan plan = await _Rules(needed: false).plan(contextOn(FakeFiles()));

      expect(plan, isA<NothingPlan>());
      expect((plan as NothingPlan).because, _Rules.notHere);
    });

    test('writes nothing when the apply runs anyway', () async {
      // The engine only applies a step whose check answered Ready, so this cannot happen through a
      // run. It is asserted because the mixin is what a plugin author overrides one method of, and
      // an apply that wrote regardless would put a file on a machine whose own check had just said
      // it has no business with one.
      await _Rules(needed: false).apply(contextOn(FakeFiles()));

      expect(files.written, isEmpty);
      expect(files.contents, isEmpty);
    });

    test('is not asked what the content would be', () async {
      // The case this exists for is a machine where the content cannot be composed at all — the
      // rules name an interface that was not found. A mixin that asked anyway would throw on the
      // one machine the answer is meant to spare.
      final _Rules step = _Rules(needed: false);
      final StepContext context = contextOn(FakeFiles());

      await step.check(context);
      await step.plan(context);
      await step.apply(context);

      expect(step.composed, isFalse, reason: 'contentFor was reached on a machine with no file');
    });
  });

  group('a step that says nothing about it', () {
    test('behaves exactly as it did before', () async {
      // The default answers null, so every FileStep written before this existed is unchanged.
      expect(await const _Plain().check(contextOn(FakeFiles())), isA<Ready>());
      expect(await const _Plain().plan(contextOn(FakeFiles())), isA<DiffPlan>());
    });
  });
}

/// A file step whose machine may or may not have anything to do with it.
final class _Rules extends IrreversibleStep with FileStep {
  _Rules({required this.needed});

  /// What it writes where there is something to write.
  static const String text = 'the rules\n';

  /// Why a machine may have no business with this file.
  static const String notHere = 'nothing is steered on this machine, so no rules are needed';

  final bool needed;

  /// Whether [contentFor] was reached.
  bool composed = false;

  @override
  String get irreversibleReason => 'it is a probe';

  @override
  String pathFor(StepContext context) => '/one';

  @override
  int get mode => 0x1a4;

  @override
  Future<String?> nothingToWriteReason(StepContext context) async => needed ? null : notHere;

  @override
  Future<String> contentFor(StepContext context) async {
    composed = true;
    return text;
  }
}

/// A file step from before this existed, which must be unaffected.
final class _Plain extends IrreversibleStep with FileStep {
  const _Plain();

  @override
  String get irreversibleReason => 'it is a probe';

  @override
  String pathFor(StepContext context) => '/two';

  @override
  int get mode => 0x1a4;

  @override
  Future<String> contentFor(StepContext context) async => 'x';
}

/// A log for a test that has to build a context and has nothing to say in it.
final class _SaysNothing implements Logger {
  const _SaysNothing();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
