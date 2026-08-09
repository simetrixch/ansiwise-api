import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// A step that says it can be taken back has to keep what it overwrites.
///
/// THE COMPILER HOLDS THE FIRST HALF. `ReversibleStep<T>` declares `capture`, so a step that does
/// not answer what was there does not exist — there is nothing to plant and nothing to probe. What
/// the compiler cannot show is the ORDER and the HANDOVER: that the capture runs before the apply
/// that would destroy what it is reading, and that the undo is given that value rather than being
/// free to go and look again.
///
/// WHY LOOKING AGAIN IS THE DEFECT. An undo runs while a run is failing, minutes after the apply,
/// with every later step's work on the machine in between. `install_packages` in this platform's
/// plugin removed the packages it found installed at undo time, believing they were the ones it had
/// installed — so a machine that already carried one had it taken away while the run was cleaning
/// up after an unrelated failure. Its author had written the correct rule in a comment directly
/// above the code that did not hold it.
void main() {
  /// A program of one write followed by a step that ends the run, so the write is unwound.
  ResolvedProgram writeThenFail() =>
      ProgramResolver(
        registryOf(
          steps: <String, (String, Step Function(Arguments))>{
            'writes': ('x:1', (Arguments a) => WritesAFile(path: '/one', content: 'after')),
            'fails': ('x:2', (Arguments a) => const Blocks('the disk went away')),
          },
        ),
      ).resolve(
        programOf('p', <(String, OnFailure, List<String>)>[
          ('writes', OnFailure.exit, <String>[]),
          ('fails', OnFailure.exit, <String>[]),
        ]),
      );

  group('a file that was already there', () {
    test('is put back as it was, not deleted', () async {
      final Harness h = Harness(files: FakeFiles(<String, String>{'/one': 'before'}));
      await h.runner.run(program: writeThenFail(), mode: Mode.run, header: h.header());

      expect(
        h.files.contents['/one'],
        'before',
        reason:
            'the undo was handed what the capture read, so it restored rather than guessing that '
            'the file was this step\'s to remove',
      );
    });

    test('and the run really did overwrite it in between', () async {
      // Without this the test above passes for a step that never wrote at all, which would make it
      // agree with exactly the defect it is here to catch.
      final Harness h = Harness(files: FakeFiles(<String, String>{'/one': 'before'}));
      await h.runner.run(program: writeThenFail(), mode: Mode.run, header: h.header());

      expect(h.files.written, contains('/one'), reason: 'the apply ran, and then was taken back');
    });
  });

  group('a file that was not there', () {
    test('is deleted, because the capture said there was nothing to put back', () async {
      final Harness h = Harness();
      await h.runner.run(program: writeThenFail(), mode: Mode.run, header: h.header());

      expect(h.files.contents.containsKey('/one'), isFalse);
      expect(h.files.deleted, contains('/one'));
    });
  });

  group('the order', () {
    test('the capture reads what was there and not what the apply left', () async {
      // The whole property in one assertion. If the capture ran after the apply it would read
      // "after", the undo would write "after" back, and the file would end the run holding what the
      // failed run put there — which is the state an undo exists to prevent.
      final Harness h = Harness(files: FakeFiles(<String, String>{'/one': 'before'}));
      await h.runner.run(program: writeThenFail(), mode: Mode.run, header: h.header());

      expect(h.files.contents['/one'], isNot('after'));
    });
  });

  group('the two modes that change nothing', () {
    test('a dry run captures without the capture reaching the machine', () async {
      // The capture runs in every mode, so it is inside the dry-run guarantee rather than beside
      // it: a capture that read a file by writing a temporary one would break that guarantee at the
      // one place nobody looks, because it is preparation for taking work back and not the work.
      final Harness h = Harness(files: FakeFiles(<String, String>{'/one': 'before'}));
      await h.runner.run(
        program: writeThenFail(),
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(h.files.written, isEmpty);
      expect(h.files.deleted, isEmpty);
      expect(h.files.contents['/one'], 'before');
    });
  });
}
