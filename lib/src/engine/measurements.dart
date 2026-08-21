import '../domain/measurement.dart';
import '../model/names.dart';
import 'redactor.dart';

/// What the steps of one run measured, under the names they published them by.
///
/// One of these belongs to one run. It is filled as the steps go, and read by the engine when it
/// builds a later row that takes one of the values — never by a step, which is why the sink handed
/// out below can only put values in.
///
/// **The engine reads it in the mode that changes things and in no other.** In a test and in a dry
/// run the row that produces a value has not done its work, so whatever a step measured on the way
/// to its own answer describes the machine as it stands rather than as the run will leave it. Using
/// it there would put a value in the plan that the real run re-measures and need not honour, so the
/// plan says the value is not known yet instead.
final class Measurements {
  /// Creates the collection one run publishes into, registering with the run's redactor whatever is
  /// published under a spec that declares itself secret.
  Measurements(this._redactor);

  /// The one thing between a credential and a world-readable record, shared with every surface of
  /// this run.
  final Redactor _redactor;

  final Map<MeasurementName, String> _values = <MeasurementName, String>{};

  /// The sink [step] publishes through, accepting the names [declares] and no others, and writing
  /// each of them under the name [publishedAs] gives it.
  ///
  /// Scoped to one step so the framework, and not the step, decides what a name means: a step
  /// publishing a name its registry entry does not declare would be publishing something no
  /// resolution could have checked, and the row that reads it would have been admitted against a
  /// wiring that was never there.
  ///
  /// **[publishedAs] is where a row's rename takes effect, and a step never learns of it.** The step
  /// publishes the name its class declares, always and in every program; the sink writes the name
  /// this row chose. A step told which name it was running under would be a step that could act on
  /// it, and which name a value stands under is a fact about a program rather than about a machine.
  StepMeasurements forStep(
    StepName step,
    List<MeasurementSpec> declares, {
    Map<MeasurementName, MeasurementName> publishedAs = const <MeasurementName, MeasurementName>{},
  }) => StepMeasurements(this, step, declares, publishedAs);

  /// What was published under [name], or null when nothing has been.
  String? valueOf(MeasurementName name) => _values[name];

  /// The names published so far, for a refusal that has to say what there was.
  Iterable<MeasurementName> get published => _values.keys;
}

/// The sink one step publishes through.
///
/// A second publication of the same name by the same step overwrites the first. A step measures in
/// its check, and its check runs again after its apply — so the same name arriving twice is one step
/// looking twice, and the later reading is the one that describes the machine the next row acts on.
///
/// **It also remembers what went through IT**, which is what [publishedByThisRow] answers and what
/// [Measurements] cannot. The collection above is run-wide and cumulative, so asking it whether a
/// name holds a value answers yes for a value an EARLIER row published — and a postcondition read
/// off that would pass a row that published nothing at all.
final class StepMeasurements implements MeasurementSink {
  /// Creates the sink one step publishes through, which [Measurements.forStep] is what builds.
  StepMeasurements(this._into, this._step, this._declares, this._publishedAs);

  final Measurements _into;
  final StepName _step;
  final List<MeasurementSpec> _declares;
  final Map<MeasurementName, MeasurementName> _publishedAs;
  final Set<MeasurementName> _published = <MeasurementName>{};

  /// The names this one step really published, under the names the row publishes them by.
  ///
  /// Empty until the step publishes something, whatever any earlier row of the same run put into the
  /// collection behind it.
  Set<MeasurementName> get publishedByThisRow => Set<MeasurementName>.unmodifiable(_published);

  @override
  void publish(MeasurementName name, String value) {
    final MeasurementSpec? spec = _declaring(name);
    if (spec == null) {
      final Iterable<String> declared = _declares.map((MeasurementSpec s) => s.name.value);
      throw ArgumentError.value(
        name.value,
        'name',
        '$_step publishes what its registry entry declares, and it declares '
            '${declared.isEmpty ? 'nothing' : declared.join(', ')}',
      );
    }
    if (value.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        '$_step published "${name.value}" as nothing — a step that read nothing publishes nothing '
            'and refuses through its check, because a row taking this value cannot tell an empty '
            'reading from a missing one',
      );
    }
    if (spec.secret) {
      // BEFORE the value is stored, so nothing the engine does with the measurement afterwards can
      // carry it in the clear: no later row is built with it yet, and no line the engine writes
      // about a row that takes it has been written.
      //
      // What this does NOT reach is what the step already did with the value on its way here.
      // A port records as it goes — RecordingShell writes a command's output where the command
      // failed or the row said keep_output, RecordingLogger writes a line as it is logged — and
      // nothing can be taken out of a line already written. So a step publishes what it measured
      // before it logs it or hands it to another port, and this call is the earliest point at which
      // the framework knows the value exists.
      _into._redactor.register(value);
    }
    final MeasurementName published = _publishedAs[name] ?? name;
    _into._values[published] = value;
    _published.add(published);
  }

  /// The spec that declares [name], or null when the step's registry entry does not.
  MeasurementSpec? _declaring(MeasurementName name) {
    for (final MeasurementSpec spec in _declares) {
      if (spec.name == name) {
        return spec;
      }
    }
    return null;
  }
}
