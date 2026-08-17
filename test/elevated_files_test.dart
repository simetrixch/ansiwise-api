import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// Reaching a path only root may reach, through the port that exists to record it.
///
/// **Why this is not "run the whole thing as root".** Half of what a deployment writes lives where
/// only root may write. The two ways out without this were both worse: run every step as root, which
/// makes `elevated` on a command mean nothing and every other boundary meaningless; or reach for the
/// shell with `cat` and `tee`, which takes file work out of the port that refuses it under a dry run
/// and records it when it happens.
void main() {
  group('a run given no way to act as root', () {
    // The case the configuration read at start-up is in: it is read before anything knows where an
    // elevation password would come from, and it needs none.
    const RealFiles unprivileged = RealFiles();

    test('refuses an elevated read BY NAME, rather than failing on a permission error', () async {
      expect(
        () => unprivileged.read('/etc/subject/settings', elevated: true),
        throwsA(isA<ElevationUnavailable>()),
      );
    });

    test('refuses an elevated write the same way', () async {
      expect(
        () => unprivileged.write('/etc/subject/settings', 'x', mode: 0x180, elevated: true),
        throwsA(isA<ElevationUnavailable>()),
      );
    });

    test('THE INNOCENT NEIGHBOUR: an ordinary read is not refused', () async {
      // Without this, a file system that refused everything would satisfy both assertions above and
      // no run could read its own configuration.
      expect(() => unprivileged.exists('/etc/subject/settings'), returnsNormally);
    });
  });

  group('what a dry run does with it', () {
    // ELEVATION SAYS WHAT MAY BE REACHED, NEVER WHETHER ANYTHING CHANGES. Reading something only
    // root may read is still a read, and a dry run performs it; writing is refused whether elevated
    // or not.
    FakeFiles seeded() => FakeFiles(<String, String>{'/etc/subject/settings': 'ON=true\n'});

    PlanningFiles planning(FakeFiles inner) =>
        PlanningFiles(inner, step: const StepName('under_test'));

    test(
      'an elevated READ is carried through, and the fake records that it was elevated',
      () async {
        final FakeFiles inner = seeded();

        expect(await planning(inner).read('/etc/subject/settings', elevated: true), 'ON=true\n');
        expect(inner.asRoot, contains('/etc/subject/settings'));
      },
    );

    test('an elevated WRITE is still refused, exactly as an ordinary one is', () async {
      expect(
        () => planning(seeded()).write('/etc/subject/settings', 'x', mode: 0x180, elevated: true),
        throwsA(isA<MutationRefused>()),
      );
    });
  });

  group('what the fake records', () {
    test('an ordinary call is NOT recorded as elevated', () async {
      // The assertion that makes the record above worth anything: without it every path would be in
      // the list and a test could not tell a step that knows it needs root from one that does not.
      final FakeFiles inner = FakeFiles(<String, String>{'/tmp/ordinary': 'x'});

      await inner.read('/tmp/ordinary');

      expect(inner.asRoot, isEmpty);
    });
  });
}
