import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

/// The port a step mints a credential through, from both sides.
///
/// The real one is the rare case of an implementation that IS testable: what it produces cannot be
/// asserted, but everything around the value can — its length, its alphabet, and the one property
/// the whole port exists for, that two draws differ.
void main() {
  group('the real source', () {
    test('writes two hexadecimal characters per byte', () {
      expect(RealEntropy().hex(32).length, 64);
      expect(RealEntropy().hex(1).length, 2);
    });

    test('writes nothing but lower-case hexadecimal', () {
      // The alphabet is the reason this port answers in hex at all: the value ends up inside a
      // connection string, an environment variable and an SQL statement, and a quote or a backslash
      // in it breaks at the third place it is pasted rather than the first.
      expect(RealEntropy().hex(64), matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('a byte below sixteen is padded rather than shortening the value', () {
      // Without the pad this is silent: a value is occasionally one character short, which is
      // nothing anyone notices and four bits of strength every time it happens.
      final Entropy source = RealEntropy();
      for (int i = 0; i < 200; i++) {
        expect(source.hex(8).length, 16);
      }
    });

    test('two draws differ, which is the whole of the port', () {
      // 32 bytes, so a collision here means the generator is not one.
      expect(RealEntropy().hex(32), isNot(RealEntropy().hex(32)));
    });

    test('a length below one byte is refused rather than answered with nothing', () {
      expect(() => RealEntropy().hex(0), throwsArgumentError);
      expect(() => RealEntropy().hex(-1), throwsArgumentError);
    });
  });

  group('the fake source', () {
    test('repeats, so a test can assert what a step minted', () {
      expect(FakeEntropy().hex(8), FakeEntropy().hex(8));
    });

    test('answers differently on each draw, so two secrets of one run are not one secret', () {
      final FakeEntropy source = FakeEntropy();
      expect(source.hex(8), isNot(source.hex(8)));
      expect(source.drawn, 2);
    });

    test('says in its own value that it is not a secret', () {
      // A fixture that reads like a credential is one somebody copies into something that then
      // ships with it. This one cannot be mistaken, and it is still hexadecimal, so it stands in
      // wherever a real value would.
      expect(FakeEntropy().hex(8), startsWith('fa4e'));
      expect(FakeEntropy().hex(8), matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('keeps the length the caller asked for', () {
      expect(FakeEntropy().hex(32).length, 64);
      expect(FakeEntropy().hex(2).length, 4);
    });

    test('refuses what the real one refuses', () {
      expect(() => FakeEntropy().hex(0), throwsArgumentError);
    });
  });

  test('a step is handed the port and a predicate is not', () {
    // The distinction is deliberate and this is what holds it: a predicate is evaluated once for
    // the whole run and answers a question, so one that drew a random value would make the plan a
    // run printed differ from the run that followed it.
    final Machine machine = fakeMachine();
    expect(machine.entropy, isA<Entropy>());
    expect(
      StepContext(
        shell: machine.shell,
        files: machine.files,
        http: machine.http,
        clock: machine.clock,
        entropy: machine.entropy,
        log: const _SaysNothing(),
        step: const StepName('any'),
        arguments: Arguments.none,
        facts: Facts.none,
      ).entropy.hex(4),
      'fa4e0001',
    );
  });
}

/// A log for the one test that has to build a context and has nothing to say in it.
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
