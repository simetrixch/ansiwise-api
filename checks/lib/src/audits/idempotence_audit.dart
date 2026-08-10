/// The suite that drives [Idempotence] over one registry, with its counter-probe.
library;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import '../declared_answers.dart';
import '../idempotence.dart';
import '../registry_reading.dart';
import '../step_under_probe.dart';

/// Runs the idempotence audit over [registry], arranging the fake with [fixtures].
///
/// [notCoveredByAFakeMachine] is the package's LEDGER: the steps a fake machine cannot exercise,
/// each named because an audit that quietly covers nothing reads like a pass. The assertion against
/// it is exact in both directions — a step that gains a fixture has to leave the ledger, and a
/// fixture that stopped working turns the tree red instead of quietly moving one more step into it.
///
/// [answers] is what a program file would give the steps. Left out, it is read from what the
/// installation's programs declare for the answers THIS registry's steps say they read.
///
/// WHAT IT STATES: the whole census. How many steps were run twice, and how many of them were
/// applied and then satisfied, only measure, or could not be exercised at all. There is no bucket
/// that means "probably fine": a step counted as passing because the fake could not exercise it is
/// the failure this audit exists to prevent.
Future<void> auditIdempotence(
  Registry registry, {
  required Map<String, Fixture> fixtures,
  required Set<String> notCoveredByAFakeMachine,
  Arguments? answers,
}) async {
  final Idempotence check = Idempotence(
    registry: registry,
    answers: answers ?? (await answersDeclaredBy(registry)).values,
    fixtures: fixtures,
  );
  final IdempotenceReading reading = await check.runEveryStep();

  // Which steps only measure, read off the built objects rather than written down by hand. A bucket
  // asserted against a hand-written list would have to be kept in step by somebody; asserted against
  // the kinds the registry really builds, it goes red the day the observing branch stops recognising
  // an observing step, and needs nothing from the package.
  final List<String> observingByKind = <String>[
    for (final RegistryEntry entry in RegistryReading.of(registry).entries)
      if (entry.kind == StepKind.observing) entry.name,
  ]..sort();

  test('${reading.coverage.length} of ${registry.steps.length} step(s) were run twice', () {
    expect(
      reading.coverage,
      hasLength(registry.steps.length),
      reason: 'some step was never run, so nothing about its second run was measured',
    );
  });

  test('every fixture names a step this registry holds', () {
    // A fixture keyed on a step that is no longer here is IGNORED rather than reported, so a step
    // moving to another package leaves its arrangement behind, where it reads as coverage and is
    // none. That is how eight of them survived a package split with nothing going red.
    expect(
      fixtures.keys.where((String name) => !registry.steps.containsKey(StepName(name))),
      isEmpty,
      reason: 'a fixture for a step that is not here arranges a machine no check ever meets',
    );
  });

  test('no registered step was seen to do its work twice', () {
    expect(
      reading.findings,
      isEmpty,
      reason:
          "the shape is exact: the step's check answers Satisfied the second time, before any work, "
          'so the engine never calls apply again',
    );
  });

  test('${reading.exercisedNames.length} step(s) were applied against a fake machine and were '
      'satisfied afterwards, and ${reading.observingNames.length} only measure', () {
    expect(
      reading.observingNames,
      orderedEquals(observingByKind),
      reason:
          'the observing bucket no longer holds exactly the steps the registry builds as observing, '
          'so that bucket is measuring something other than what it says',
    );
    expect(
      reading.exercisedNames.length +
          reading.observingNames.length +
          reading.notCoveredNames.length,
      registry.steps.length,
      reason:
          'a step landed in none of the buckets this audit reports, so the census does not add up '
          'and something was measured by nothing',
    );
  });

  test('${reading.notCoveredNames.length} step(s) are NOT COVERED, and they are exactly the ones '
      'this package names', () {
    // A skip is not silent and it is not a pass. Naming them in a ledger the audit asserts against
    // is what makes a step added tomorrow bring its fixture or force somebody to write its name
    // there — and what makes a fixture that stopped working turn the tree red instead of quietly
    // moving one more step into the list.
    expect(
      reading.notCoveredNames,
      orderedEquals(notCoveredByAFakeMachine.toList()..sort()),
      reason:
          'a step a fake machine cannot exercise has not been shown to be idempotent by anything; '
          'either arrange the fake for it, or name it in the ledger',
    );
  });

  group('counter-probe', () {
    // Four steps written here, run through the same machinery. The third is the one this whole audit
    // is shaped around: a step whose work is left behind by a command must come back NOT COVERED and
    // never exercised — because a fake shell answers every command the same way before and after, so
    // its check would answer the same both times for a reason that has nothing to do with the step
    // being idempotent. Collapse the two into one and this is what says so. The fourth is the same
    // shape over the network, which is the only machine some packages ever reach.

    test('a step that would work twice is caught', () async {
      expect(
        await _runTwice(const DoesItsWorkEveryTime()),
        isA<WouldRepeat>(),
        reason: 'a step planted here writes on every run and its check never notices',
      );
    });

    test('a step whose second run is a no-op is exercised', () async {
      expect(
        await _runTwice(const WritesOnlyOnce()),
        isA<Exercised>(),
        reason: 'a step planted here writes once and is satisfied afterwards',
      );
    });

    test('a step the fake machine cannot exercise is not counted as passing', () async {
      expect(
        await _runTwice(const WorksThroughACommand()),
        isA<NotCovered>(),
        reason:
            'a step planted here leaves its postcondition behind with a command the fake shell does '
            'not carry out, and counting that as a pass is the failure this audit exists to prevent',
      );
    });

    test('a step whose work goes over the network is not counted as passing either', () async {
      expect(
        await _runTwice(const WorksThroughARequest()),
        isA<NotCovered>(),
        reason:
            'a step planted here leaves its postcondition behind with a POST the fake network does '
            'not carry out, and a package whose every step works that way would otherwise look '
            'proven',
      );
    });

    test('a fixture that carries the command out makes the same step measurable', () async {
      // The other half of the third: with the fake arranged the way a real machine would be, the
      // same step IS exercised. Without this, an audit that answered NOT COVERED to everything would
      // pass the tests above.
      expect(
        await _runTwice(
          const WorksThroughACommand(),
          fixture: (FakeShell shell, FakeFiles files, FakeHttp http) {
            shell.changes('touch ${WorksThroughACommand.path}', () {
              shell.answers('test -e ${WorksThroughACommand.path}', 'there');
            });
          },
        ),
        isA<Exercised>(),
        reason: 'FakeShell.changes is what lets a postcondition actually become true',
      );
    });

    test('a step that only measures is recognised as one', () async {
      expect(
        await _runTwice(const OnlyMeasuresTheMachine()),
        isA<OnlyMeasures>(),
        reason:
            'the observing branch is what the bucket above is asserted against, and a step that only '
            'measures came back as something else',
      );
    });
  });
}

Future<Coverage> _runTwice(Step step, {Fixture? fixture}) =>
    runTwice(const StepName('planted'), step, Arguments.none, fixture: fixture);

/// Where the planted steps write, so they cannot read each other's file.
const String _plantedPath = '/etc/planted';

/// A step that writes every time it is run and never notices that it has.
final class DoesItsWorkEveryTime extends ReversibleStep<bool> {
  /// Creates the planted step.
  const DoesItsWorkEveryTime();

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.diff(_plantedPath, before: '', after: 'again');

  @override
  Future<void> apply(StepContext context) async =>
      context.files.write(_plantedPath, 'again', mode: 0x180);

  @override
  Future<bool> capture(StepContext context) => context.files.exists(_plantedPath);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (!captured) {
      await context.files.delete(_plantedPath);
    }
  }
}

/// A step that writes once and answers satisfied from then on.
final class WritesOnlyOnce extends ReversibleStep<bool> {
  /// Creates the planted step.
  const WritesOnlyOnce();

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(_plantedPath)) {
      return const CheckResult.ready();
    }
    return await context.files.read(_plantedPath) == 'once'
        ? const CheckResult.satisfied('the file already holds what this step writes')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.diff(_plantedPath, before: '', after: 'once');

  @override
  Future<void> apply(StepContext context) async =>
      context.files.write(_plantedPath, 'once', mode: 0x180);

  @override
  Future<bool> capture(StepContext context) => context.files.exists(_plantedPath);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (!captured) {
      await context.files.delete(_plantedPath);
    }
  }
}

/// A step whose postcondition a real command would leave behind, and a fake one never does.
final class WorksThroughACommand extends ReversibleStep<bool> {
  /// Creates the planted step.
  const WorksThroughACommand();

  /// The marker the command leaves behind.
  static const String path = '/etc/planted-by-a-command';

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult marker = await context.shell.run(
      const Command.observing('test', <String>['-e', path]),
    );
    return marker.trimmed == 'there'
        ? const CheckResult.satisfied('the marker is there')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(<String>['touch', path]);

  @override
  Future<void> apply(StepContext context) async {
    await context.shell.run(const Command('touch', <String>[path]));
  }

  @override
  Future<bool> capture(StepContext context) async {
    final CommandResult marker = await context.shell.run(
      const Command.observing('test', <String>['-e', path]),
    );
    return marker.trimmed == 'there';
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(const Command('rm', <String>['-f', path]));
  }
}

/// A step whose postcondition a real request would leave behind, and a fake one never does.
final class WorksThroughARequest extends IrreversibleStep {
  /// Creates the planted step.
  const WorksThroughARequest();

  /// Where it reads and writes, so the two requests are about one thing.
  static const String url = 'http://127.0.0.1:9/planted';

  @override
  String get irreversibleReason =>
      'what stood under that key before is overwritten and is held nowhere else';

  @override
  Future<CheckResult> check(StepContext context) async {
    final HttpAnswer found = await context.http.send(const HttpRequest('GET', url));
    return found.body == 'there'
        ? const CheckResult.satisfied('the entry is there')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.nothing('would post the entry');

  @override
  Future<void> apply(StepContext context) async {
    await context.http.send(const HttpRequest('POST', url, body: '{}'));
  }
}

/// A step that changes nothing on any run and answers the same thing twice.
final class OnlyMeasuresTheMachine extends ObservingStep {
  /// Creates the planted step.
  const OnlyMeasuresTheMachine();

  @override
  Future<CheckResult> check(StepContext context) async {
    await context.files.exists(_plantedPath);
    return const CheckResult.satisfied('it only looked');
  }
}
