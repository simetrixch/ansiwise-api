/// Building one registered step, and running it outside a run.
///
/// A check asks a step a question the engine would ask it — what would you plan, are you already
/// satisfied — without a runner, a record or a machine. What it needs for that is the same three
/// things every time: values for the arguments the step declares, somewhere for the step to say
/// things, and a [StepContext] holding a set of ports the check chose.
library;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';

import 'finding.dart';

/// Arranges [FakeShell], [FakeFiles] and [FakeHttp] for one step.
///
/// A blank fake cannot exercise most steps: it records a command and does not carry it out, so a
/// postcondition a real command would leave behind never becomes true. A fixture arranges the fake
/// the way the real machine would be, which is what lets a check measure the step at all.
///
/// The map of them belongs to the PLUGIN — which step needs which arrangement is knowledge about
/// that plugin's steps. Only the shape is here, because the audits take it as an argument.
typedef Fixture = void Function(FakeShell shell, FakeFiles files, FakeHttp http);

/// What a probe hands a step for a text argument with no default.
///
/// Named rather than written twice: a fixture arranges the fake for the values the CHECK hands the
/// step, so a fixture and [plausibleArguments] disagreeing about this one character is a fixture
/// that arranges the wrong file and a step that comes back not covered for no visible reason.
const String plausibleText = 'x';

/// A value for every argument [specs] declares.
///
/// A default wins wherever there is one, because that is the value a program that says nothing about
/// the argument would run with — the case worth probing. Where the declaration names the values it
/// may hold, the first of them is taken: a step that DECIDES on such a value refuses anything
/// outside the set, correctly, and handing it the generic 'x' would measure the probe rather than
/// the step. Everything else gets the simplest value of its kind. No step may read an argument it
/// did not declare, so this is enough to build any of them that keeps to its own declaration; one
/// that does not fails to build, and a check reports that rather than passing over the step.
Arguments plausibleArguments(List<ArgumentSpec> specs) {
  final Map<String, Object> values = <String, Object>{};
  for (final ArgumentSpec spec in specs) {
    values[spec.name] =
        spec.defaultValue ??
        (spec.allowed.isNotEmpty ? spec.allowed.first : null) ??
        switch (spec.kind) {
          ArgumentKind.text => plausibleText,
          ArgumentKind.answerName => plausibleText,
          ArgumentKind.integer => 1,
          ArgumentKind.flag => false,
          ArgumentKind.textList => const <String>['x'],
        };
  }
  return Arguments(values);
}

/// The step [entry] builds from [plausibleArguments], or null when it cannot be built that way.
///
/// [onFailure] is given a finding naming the step and the reason. Every throwable is caught,
/// including an [Error]: a step that reads an argument it never declared throws [ArgumentError], and
/// that is precisely the defect worth reporting rather than letting one entry end the walk and say
/// nothing about the rest.
Step? buildStep(RegisteredStep entry, void Function(Finding failure) onFailure) {
  try {
    return entry.create(plausibleArguments(entry.arguments));
  } on Object catch (failure) {
    onFailure(
      Finding(
        entry.name.value,
        'could not be built from the arguments it declares itself, so nothing about it was '
        'measured — $failure',
      ),
    );
    return null;
  }
}

/// What a step said while a check was running it.
///
/// Kept rather than printed: a step's own notes would otherwise land in the middle of a test run's
/// output and be read as its own.
final class CollectedLog implements Logger {
  /// Everything the step said, in order.
  final List<String> said = <String>[];

  @override
  void debug(String message) {
    said.add(message);
  }

  @override
  void info(String message) {
    said.add(message);
  }

  @override
  void warn(String message) {
    said.add(message);
  }

  @override
  void error(String message) {
    said.add(message);
  }
}

/// The context a check hands [step], carrying the ports it chose.
///
/// [Facts.none] because no predicate is evaluated here: a step that asks about one it did not have
/// evaluated throws, which is a defect in the step and is reported as such.
///
/// [publishes] is what the step's registry entry declares it measures, and [measurements] is where
/// those go. A step that measures does it inside its check, which is exactly what an audit runs — so
/// a context with nowhere to publish would turn every such step into a failure about the probe
/// rather than about the step. Passing a collection in is how a check reads what was published.
StepContext probeContext({
  required StepName step,
  required Arguments arguments,
  required Arguments answers,
  required Shell shell,
  required Files files,
  required Http http,
  required Clock clock,
  required Entropy entropy,
  required Logger log,
  List<MeasurementSpec> publishes = const <MeasurementSpec>[],
  Measurements? measurements,
}) => StepContext(
  shell: shell,
  files: files,
  http: http,
  clock: clock,
  entropy: entropy,
  log: log,
  step: step,
  arguments: arguments,
  answers: answers,
  measurements: (measurements ?? Measurements()).forStep(step, publishes),
  facts: Facts.none,
);

/// What a [CheckResult] answered, as one line, so two answers can be compared and reported.
String describeCheck(CheckResult result) => switch (result) {
  Ready() => 'ready',
  Satisfied(:final String because) => 'satisfied: $because',
  Blocked(:final String reason) => 'blocked: $reason',
};
