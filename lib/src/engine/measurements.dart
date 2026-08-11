import '../domain/measurement.dart';
import '../model/names.dart';

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
  /// Creates the collection one run publishes into.
  Measurements();

  final Map<MeasurementName, String> _values = <MeasurementName, String>{};

  /// The sink [step] publishes through, accepting the names [declares] and no others.
  ///
  /// Scoped to one step so the framework, and not the step, decides what a name means: a step
  /// publishing a name its registry entry does not declare would be publishing something no
  /// resolution could have checked, and the row that reads it would have been admitted against a
  /// wiring that was never there.
  MeasurementSink forStep(StepName step, List<MeasurementSpec> declares) =>
      _StepMeasurements(this, step, declares);

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
final class _StepMeasurements implements MeasurementSink {
  const _StepMeasurements(this._into, this._step, this._declares);

  final Measurements _into;
  final StepName _step;
  final List<MeasurementSpec> _declares;

  @override
  void publish(MeasurementName name, String value) {
    if (!_declares.any((MeasurementSpec spec) => spec.name == name)) {
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
    _into._values[name] = value;
  }
}
