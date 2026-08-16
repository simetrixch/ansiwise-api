import '../domain/argument_check.dart';
import '../domain/arguments.dart';
import '../domain/measurement.dart';
import '../domain/program.dart';
import '../domain/registry.dart';
import '../domain/resolved_program.dart';
import '../model/failures.dart';
import '../model/names.dart';

/// Finds every name a program writes in the registry, and refuses the program when one is missing.
///
/// This is where the safety a compiler cannot give across a configuration boundary is restored. A
/// program file hands a step some values, and nothing about that is checked when the code is
/// compiled. It is checked here instead, before the first thing is looked at: every step name,
/// every predicate name, every argument key, every argument kind, and every required argument.
///
/// A program that does not resolve is refused whole. Not the first bad entry — all of them, in one
/// message, because an operator fixing a program file one refusal per run is an operator running it
/// five times to learn five things it could have said at once.
final class ProgramResolver {
  /// Creates a resolver against [registry].
  const ProgramResolver(this.registry);

  /// What the names must be found in.
  final Registry registry;

  /// Binds [program] to the registry.
  ///
  /// Throws [ProgramInvalid] listing everything wrong with it.
  ResolvedProgram resolve(Program program) {
    final List<String> problems = <String>[];
    final List<ResolvedStep> resolved = <ResolvedStep>[];
    // Which program-wide defaults some step DECLARES, and which ones actually filled a row. Both
    // are needed because they fail differently: a name nothing declares is a misspelling, and a
    // name every row overrides is dead config. Neither is visible from the file, where both look
    // exactly like a key that decides something.
    final Set<String> defaultsDeclared = <String>{};
    final Set<String> defaultsFilled = <String>{};
    // Built before the rows are walked. Whether a row may take a value from a measurement is a
    // question about the WHOLE program — which row produces it, where that row stands, and what it
    // is gated on — and none of that can be answered from the row in front of us.
    final _Published published = _Published.of(program, registry, problems);

    for (int i = 0; i < program.steps.length; i++) {
      final ProgramStep entry = program.steps[i];
      final String where = '${program.name}[$i] ${entry.step}';

      final RegisteredStep? registered = registry.step(entry.step);
      if (registered == null) {
        problems.add('$where: no step is registered under that name');
        continue;
      }

      // Folded in HERE and not where a step is executed, so everything downstream reads one set of
      // values: the argument check below, the plan, the record, and the fingerprint a run is gated
      // against. A default applied later than this would leave the fingerprint blind to it, and a
      // run would pass the gate of a dry run made under other values.
      final ProgramStep filled = _filled(
        entry,
        registered,
        program.defaults,
        defaultsDeclared,
        defaultsFilled,
        problems,
      );

      for (final String answer in registered.answers) {
        if (program.answers.named(answer) == null) {
          problems.add('$where: reads the answer "$answer", and this program does not declare it');
        }
      }
      for (final ArgumentSpec spec in registered.arguments) {
        if (spec.kind == ArgumentKind.answerName && filled.arguments.has(spec.name)) {
          final String answerName = filled.arguments.text(spec.name);
          if (program.answers.named(answerName) == null) {
            problems.add(
              '$where: the argument "${spec.name}" names the answer "$answerName", and this program does not declare it',
            );
          }
        }
      }
      problems.addAll(
        argumentProblems(
          where: where,
          given: filled.arguments,
          declared: registered.arguments,
          noun: 'argument',
          // An argument the row takes from a measurement is not a missing one. What is wrong with
          // such a wiring is said below, in the words of the wiring — reporting it here as well
          // would tell the operator to write a value on a row that already says where the value
          // comes from.
          filledElsewhere: entry.reads.keys.toSet(),
        ),
      );

      final List<RegisteredPredicate> when = <RegisteredPredicate>[];
      for (final PredicateName name in entry.when) {
        final RegisteredPredicate? predicate = registry.predicate(name);
        if (predicate == null) {
          problems.add('$where: no predicate is registered under "$name"');
          continue;
        }
        when.add(predicate);
      }

      final List<MeasuredArgument> measured = _measured(
        // With the program-wide defaults already folded in, because whether the step can be built
        // while one value is missing depends on the other values it is given.
        filled,
        registered,
        position: i,
        where: where,
        published: published,
        problems: problems,
      );

      resolved.add(
        ResolvedStep(entry: filled, registered: registered, when: when, measured: measured),
      );
    }

    for (final String name in program.defaults.names) {
      if (!defaultsDeclared.contains(name)) {
        problems.add(
          '${program.name}: no step of this program declares an argument named "$name", so the '
          'default written for it fills nothing',
        );
        continue;
      }
      if (!defaultsFilled.contains(name)) {
        problems.add(
          '${program.name}: every row that takes "$name" writes its own, so the default written '
          'for it fills nothing — leave it off a row, or take the default away',
        );
      }
    }

    if (problems.isNotEmpty) {
      throw ProgramInvalid(problems.join('\n'), where: program.name.value);
    }
    return ResolvedProgram(declared: program, steps: resolved);
  }

  /// [entry] with every program-wide default it takes written into its arguments.
  ///
  /// A default is taken when the step DECLARES an argument of that name and the row did not write
  /// one. Declaring is what decides it: handing a step a value it has no argument for would be an
  /// unknown key, and the argument check would refuse the row for a name the row does not carry.
  ///
  /// A default that fills a SECRET argument is refused into [problems] rather than folded in.
  ProgramStep _filled(
    ProgramStep entry,
    RegisteredStep registered,
    Arguments defaults,
    Set<String> declaredSomewhere,
    Set<String> filledSomewhere,
    List<String> problems,
  ) {
    final Map<String, ArgumentSpec> declared = <String, ArgumentSpec>{
      for (final ArgumentSpec spec in registered.arguments) spec.name: spec,
    };
    final Map<String, Object> applicable = <String, Object>{};
    for (final String name in defaults.names) {
      final ArgumentSpec? spec = declared[name];
      if (spec == null) {
        continue;
      }
      if (spec.secret) {
        // A program file ships inside the binary to every installation, so a credential written into
        // one is the same credential everywhere. The loader refuses this for a declared ANSWER for
        // the same reason; without it here, the block added for paths and key names would be the way
        // around that refusal.
        problems.add(
          'the default "$name" fills a secret argument, and a program file ships to every '
          'installation — a credential belongs in a declared answer, never here',
        );
        // Counted as filled as well, or the sweep below would add "every row writes its own" on top
        // of a refusal that has already said what is wrong.
        declaredSomewhere.add(name);
        filledSomewhere.add(name);
        continue;
      }
      declaredSomewhere.add(name);
      // A row that says where the value comes from has decided the same thing as a row that writes
      // it out, so the program-wide default does not reach past it. Without this the row would carry
      // a default nothing ever uses — the measurement fills the argument when the step is built —
      // and the sweep below could not report it, because the default did technically fill a row.
      if (defaults.raw(name) case final Object value
          when entry.arguments.raw(name) == null && !entry.reads.containsKey(name)) {
        applicable[name] = value;
        filledSomewhere.add(name);
      }
    }
    if (applicable.isEmpty) {
      return entry;
    }
    return ProgramStep(
      step: entry.step,
      onFailure: entry.onFailure,
      arguments: entry.arguments.withDefaults(applicable),
      reads: entry.reads,
      when: entry.when,
      undo: entry.undo,
      // Every field of the row is carried, and the only thing standing between them and being
      // silently dropped is that they are listed here. A field added to a row and forgotten in this
      // one place reaches the resolver as its default and nothing anywhere says so: the file states
      // it, the loader parses it, and the run behaves as though the line were not written.
      restsOnAnEarlierStep: entry.restsOnAnEarlierStep,
      keepsOutput: entry.keepsOutput,
    );
  }

  /// Where each argument of [entry] that names a measurement takes its value from.
  ///
  /// Every wiring that does not add up is refused into [problems] and left out of the result, so a
  /// program is only resolved once every one of them is bound to a row that produces it.
  List<MeasuredArgument> _measured(
    ProgramStep entry,
    RegisteredStep registered, {
    required int position,
    required String where,
    required _Published published,
    required List<String> problems,
  }) {
    if (entry.reads.isEmpty) {
      return const <MeasuredArgument>[];
    }
    final Map<String, ArgumentSpec> declared = <String, ArgumentSpec>{
      for (final ArgumentSpec spec in registered.arguments) spec.name: spec,
    };
    // Sorted by the argument name, so the fingerprint's material and every message read the same
    // way whatever order the file happened to write the keys in.
    final List<MapEntry<String, MeasurementName>> readings = entry.reads.entries.toList()
      ..sort(
        (MapEntry<String, MeasurementName> a, MapEntry<String, MeasurementName> b) =>
            a.key.compareTo(b.key),
      );

    final List<MeasuredArgument> measured = <MeasuredArgument>[];
    for (final MapEntry<String, MeasurementName> reading in readings) {
      final String argument = reading.key;
      final MeasurementName measurement = reading.value;
      final String takes = 'takes "$argument" from the measurement "$measurement"';

      final ArgumentSpec? spec = declared[argument];
      if (spec == null) {
        problems.add('$where: $takes, and this step has no argument "$argument"');
        continue;
      }
      if (spec.kind != ArgumentKind.text) {
        problems.add(
          '$where: $takes, and "$argument" holds ${spec.kind.name} — a measurement is text',
        );
        continue;
      }
      if (spec.secret) {
        // The redactor is built from the values that are known before the run starts, and it is the
        // one thing between a credential and a world-readable record. A value arriving in the middle
        // of the run is a value it has never seen, so it would reach the record through the command
        // the step composes and through the plan it prints.
        problems.add(
          '$where: $takes, and "$argument" is secret — what removes a credential from the record is '
          'built before the run, so it could never remove one that arrives during it. A credential '
          'belongs in a declared answer.',
        );
        continue;
      }
      final List<_Publisher> publishers = published.rowsFor(measurement);
      if (publishers.isEmpty) {
        final Iterable<String> names = published.names;
        problems.add(
          '$where: $takes, and no step of this program publishes it — this program publishes '
          '${names.isEmpty ? 'nothing' : names.join(', ')}',
        );
        continue;
      }
      if (publishers.length > 1) {
        // Already reported once against the program, naming both rows. A second message here would
        // say the same thing about the row that happens to read it.
        continue;
      }
      final _Publisher publisher = publishers.first;
      if (publisher.position >= position) {
        problems.add(
          '$where: $takes, and ${publisher.said} publishes it — that row runs after this one, so '
          'the value does not exist yet when this row is built',
        );
        continue;
      }
      final List<PredicateName> ungated = <PredicateName>[
        for (final PredicateName condition in publisher.when)
          if (!entry.when.contains(condition)) condition,
      ];
      if (ungated.isNotEmpty) {
        problems.add(
          '$where: $takes, and ${publisher.said} publishes it only when '
          '${ungated.join(' and ')} holds, which this row does not ask for — so the value may be '
          'missing exactly when this row runs. Put the same condition on this row.',
        );
        continue;
      }

      measured.add(
        MeasuredArgument(
          argument: argument,
          measurement: measurement,
          publisher: publisher.step,
          position: publisher.position,
        ),
      );
    }

    if (measured.isNotEmpty) {
      if (_whyNotBuildable(entry, registered) case final String refusal) {
        problems.add(
          '$where: takes a value from a measurement and cannot be built without it — $refusal. '
          'Everything that examines a program before it runs has to build the step, because the '
          'registry holds a factory and only an instance says whether a run can be taken back. '
          'Read that argument as an optional one, so the step still builds while the value does '
          'not exist yet.',
        );
        return const <MeasuredArgument>[];
      }
    }
    return measured;
  }

  /// Why [entry] cannot be built without the values it measures, or null when it can.
  ///
  /// MEASURED RATHER THAN DECLARED. Whether a step survives the absence of an argument is a property
  /// of its factory and not of its declaration: an argument declared optional and read as a required
  /// one throws exactly the same way. So the step is built, here, where a refusal still costs
  /// nothing — the alternative is a program that resolves and then throws in the endpoint that
  /// describes it and in the sentence that tells the operator what a run cannot take back.
  ///
  /// Every throwable is caught, and an [Error] is the one that matters: a step reading an argument
  /// that is not there throws [ArgumentError]. It is caught to be REPORTED, which is the whole of
  /// this method.
  String? _whyNotBuildable(ProgramStep entry, RegisteredStep registered) {
    final Map<String, Object> defaults = <String, Object>{
      for (final ArgumentSpec spec in registered.arguments)
        if (spec.defaultValue case final Object value) spec.name: value,
    };
    try {
      registered.create(entry.arguments.withDefaults(defaults));
      return null;
    } on Object catch (failure) {
      return failure.toString();
    }
  }
}

/// Which row of a program publishes which measurement.
final class _Published {
  const _Published(this._rows);

  /// Reads [program] against [registry], refusing a name two rows publish into [problems].
  factory _Published.of(Program program, Registry registry, List<String> problems) {
    final Map<MeasurementName, List<_Publisher>> rows = <MeasurementName, List<_Publisher>>{};
    for (int i = 0; i < program.steps.length; i++) {
      final ProgramStep entry = program.steps[i];
      final RegisteredStep? registered = registry.step(entry.step);
      if (registered == null) {
        // The row itself is refused where the steps are walked. Saying it twice would make one
        // misspelled step name look like two problems.
        continue;
      }
      for (final MeasurementSpec spec in registered.publishes) {
        rows
            .putIfAbsent(spec.name, () => <_Publisher>[])
            .add(_Publisher(position: i, step: entry.step, when: entry.when));
      }
    }

    for (final MapEntry<MeasurementName, List<_Publisher>> each in rows.entries) {
      if (each.value.length > 1) {
        // Refused even where nothing reads it yet. Two rows publishing one name make the value
        // depend on which of them ran last, and the row that starts reading it tomorrow would be
        // admitted against a wiring the file never states.
        problems.add(
          '${program.name}: the measurement "${each.key}" is published by '
          '${each.value.map((_Publisher p) => p.said).join(' and ')}, so nothing says which value a '
          'row taking it would get',
        );
      }
    }
    return _Published(rows);
  }

  final Map<MeasurementName, List<_Publisher>> _rows;

  /// The rows that publish [name], which is none, one, or the ambiguity refused above.
  List<_Publisher> rowsFor(MeasurementName name) => _rows[name] ?? const <_Publisher>[];

  /// Everything this program publishes, for a refusal that has to say what there was.
  Iterable<String> get names => _rows.keys.map((MeasurementName name) => name.value);
}

/// One row that publishes a measurement.
final class _Publisher {
  const _Publisher({required this.position, required this.step, required this.when});

  /// Where it stands in the program, counted from zero.
  final int position;

  /// The step it names.
  final StepName step;

  /// The conditions that decide whether it runs at all.
  final List<PredicateName> when;

  /// How a refusal names it, counting from one because a person reading a file counts that way.
  String get said => 'step ${position + 1} $step';
}
