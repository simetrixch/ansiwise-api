import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

import 'support/example_steps.dart';
import 'support/harness.dart';

/// A row chooses the name it publishes under, and a measured value fills one entry of a mapping.
///
/// **Both are the same table read from two sides.** What a program publishes is a table of EFFECTIVE
/// names — the name a step declares unless the row renamed it — against the row that produces each
/// one. A rename writes into that table; a row taking a value reads out of it; and there is one set
/// of rules about which row may produce a value for which other row, asked once whether the value
/// fills a whole argument or one entry of a mapping.
void main() {
  const MeasurementName reading = MeasurementName('reading');
  const MeasurementName first = MeasurementName('first_reading');
  const MeasurementName second = MeasurementName('second_reading');

  ProgramStep row(
    String step,
    Map<String, Object> arguments, {
    Map<String, MeasurementName> reads = const <String, MeasurementName>{},
    Map<MeasurementName, MeasurementName> publish = const <MeasurementName, MeasurementName>{},
    List<String> when = const <String>[],
  }) => ProgramStep(
    step: StepName(step),
    onFailure: OnFailure.exit,
    arguments: Arguments(arguments),
    reads: reads,
    publish: publish,
    when: when.map(PredicateName.new).toList(growable: false),
  );

  Program programOfRows(List<ProgramStep> steps, {Arguments defaults = Arguments.none}) => Program(
    name: const ProgramName('p'),
    roles: const <Role>[Role('master')],
    defaults: defaults,
    steps: steps,
  );

  /// One step that measures a file and publishes one fixed name, one that writes what it was given,
  /// and one that fills the slots of a text out of a mapping.
  Registry registryOfSteps({bool secret = false}) => registryOf(
    steps: <String, (String, Step Function(Arguments))>{
      'measures': (
        'x:1',
        (Arguments a) => MeasuresAndPublishes(file: a.text('file'), publishes: reading),
      ),
      'writes': ('x:2', WritesWhatItWasGiven.fromArguments),
      'fills': ('x:3', FillsSlotsFromAMapping.fromArguments),
    },
    arguments: <String, List<ArgumentSpec>>{
      'measures': const <ArgumentSpec>[
        ArgumentSpec(name: 'file', kind: ArgumentKind.text, describes: 'the file it reads'),
      ],
      'writes': WritesWhatItWasGiven.arguments,
      'fills': FillsSlotsFromAMapping.arguments,
    },
    publishes: <String, List<MeasurementSpec>>{
      'measures': <MeasurementSpec>[
        MeasurementSpec(name: reading, describes: 'what the file says', secret: secret),
      ],
    },
  );

  group('a row chooses the name it publishes under', () {
    test('THE STATE BEFORE: two rows of one step, neither renaming, are refused', () {
      // The measured limit this mechanism lifts. The name a step publishes is fixed by its class, so
      // two rows running it publish one name twice and nothing says which value a row taking it
      // would get. Without this the tests below would prove that renaming works and not that
      // anything needed it.
      expect(
        () => ProgramResolver(registryOfSteps()).resolve(
          programOfRows(<ProgramStep>[
            row('measures', <String, Object>{'file': '/etc/one'}),
            row('measures', <String, Object>{'file': '/etc/two'}),
          ]),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => failure.message,
            'message',
            allOf(
              contains('the measurement "reading" is published by'),
              contains('step 1 measures and step 2 measures'),
            ),
          ),
        ),
      );
    });

    test('renamed apart, each value reaches the row that names it', () async {
      final Harness h = Harness();
      h.files.contents['/etc/one'] = 'alpha\n';
      h.files.contents['/etc/two'] = 'beta\n';

      final ResolvedProgram program = ProgramResolver(registryOfSteps()).resolve(
        programOfRows(<ProgramStep>[
          row(
            'measures',
            <String, Object>{'file': '/etc/one'},
            publish: <MeasurementName, MeasurementName>{reading: first},
          ),
          row(
            'measures',
            <String, Object>{'file': '/etc/two'},
            publish: <MeasurementName, MeasurementName>{reading: second},
          ),
          row(
            'writes',
            <String, Object>{'path': '/etc/from-one'},
            reads: <String, MeasurementName>{'content': first},
          ),
          row(
            'writes',
            <String, Object>{'path': '/etc/from-two'},
            reads: <String, MeasurementName>{'content': second},
          ),
        ]),
      );

      await h.runner.run(program: program, mode: Mode.run, header: h.header());

      expect(h.files.contents['/etc/from-one'], 'alpha');
      expect(h.files.contents['/etc/from-two'], 'beta');
    });

    test('the step publishes the name its class declares, and never learns the row renamed it', () {
      final Measurements taken = Measurements(Redactor.none);
      final MeasurementSink sink = taken.forStep(
        const StepName('measures'),
        const <MeasurementSpec>[MeasurementSpec(name: reading, describes: 'what the file says')],
        publishedAs: const <MeasurementName, MeasurementName>{reading: first},
      );

      sink.publish(reading, 'alpha');

      expect(taken.valueOf(first), 'alpha', reason: 'the sink wrote the name the row chose');
      expect(taken.valueOf(reading), isNull, reason: 'nothing stands under the declared name');
      expect(
        () => sink.publish(first, 'alpha'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError failure) => failure.message.toString(),
            'message',
            contains('publishes what its registry entry declares, and it declares reading'),
          ),
        ),
        reason: 'a step publishing the row-chosen name is publishing one it does not declare',
      );
    });

    test('a rename of a name the step does not publish is refused', () {
      expect(
        () => ProgramResolver(registryOfSteps()).resolve(
          programOfRows(<ProgramStep>[
            row(
              'measures',
              <String, Object>{'file': '/etc/one'},
              publish: const <MeasurementName, MeasurementName>{MeasurementName('readng'): first},
            ),
          ]),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => failure.message,
            'message',
            allOf(
              contains('publishes "readng" under "first_reading"'),
              contains('this step publishes reading'),
            ),
          ),
        ),
      );
    });

    test('two rows renamed onto ONE name are refused again', () {
      // The refusal is about the EFFECTIVE name, so renaming cannot be used to hide the collision it
      // exists to lift.
      expect(
        () => ProgramResolver(registryOfSteps()).resolve(
          programOfRows(<ProgramStep>[
            row(
              'measures',
              <String, Object>{'file': '/etc/one'},
              publish: <MeasurementName, MeasurementName>{reading: first},
            ),
            row(
              'measures',
              <String, Object>{'file': '/etc/two'},
              publish: <MeasurementName, MeasurementName>{reading: first},
            ),
          ]),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => failure.message,
            'message',
            contains('the measurement "first_reading" is published by'),
          ),
        ),
      );
    });

    test('a row that takes a program-wide default keeps its rename', () async {
      // The resolver rebuilds a row field by field when a program-wide default applies to it, and a
      // field forgotten there reaches the rest of the engine as its own default with nothing saying
      // so. A dropped rename would put both rows back on the declared name, so the refusal above
      // fires and this program does not resolve at all.
      final Harness h = Harness();
      h.files.contents['/etc/one'] = 'alpha\n';
      h.files.contents['/etc/two'] = 'beta\n';

      final ResolvedProgram program = ProgramResolver(registryOfSteps()).resolve(
        programOfRows(<ProgramStep>[
          row(
            'measures',
            const <String, Object>{},
            publish: <MeasurementName, MeasurementName>{reading: first},
          ),
          row(
            'measures',
            <String, Object>{'file': '/etc/two'},
            publish: <MeasurementName, MeasurementName>{reading: second},
          ),
          row(
            'writes',
            <String, Object>{'path': '/etc/from-one'},
            reads: <String, MeasurementName>{'content': first},
          ),
        ], defaults: const Arguments(<String, Object>{'file': '/etc/one'})),
      );

      expect(program.steps.first.entry.publish, <MeasurementName, MeasurementName>{
        reading: first,
      }, reason: 'the rebuilt row still carries what the file said about it');

      await h.runner.run(program: program, mode: Mode.run, header: h.header());

      expect(h.files.contents['/etc/from-one'], 'alpha');
    });

    test('the loader reads publish off the row', () {
      final Program program = loadProgram('''
name: p
roles: [master]
steps:
  - step: measures
    on_failure: exit
    file: /etc/one
    publish: {reading: first_reading}
''', where: 'p.yaml');

      expect(program.steps.single.publish, <MeasurementName, MeasurementName>{reading: first});
    });

    test('the loader refuses a name of the wrong shape on either side', () {
      expect(
        () => loadProgram('''
name: p
roles: [master]
steps:
  - step: measures
    on_failure: exit
    publish: {reading: First-Reading}
''', where: 'p.yaml'),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => failure.message,
            'message',
            contains('writes "reading" under "First-Reading", and that is not a measurement name'),
          ),
        ),
      );
    });
  });

  group('one entry of a mapping argument takes its value from a measurement', () {
    Program fillsFromAMeasurement({Object body = const <String, Object?>{'measured': 'reading'}}) =>
        programOfRows(<ProgramStep>[
          row('measures', <String, Object>{'file': '/etc/one'}),
          row('fills', <String, Object>{
            'path': '/etc/out',
            'template': 'token=<run-id>',
            'values': <String, Object?>{'run-id': body},
          }),
        ]);

    test('the value reaches the slot of the text the step writes', () async {
      final Harness h = Harness();
      h.files.contents['/etc/one'] = 'alpha\n';
      final ResolvedProgram program = ProgramResolver(
        registryOfSteps(),
      ).resolve(fillsFromAMeasurement());

      await h.runner.run(program: program, mode: Mode.run, header: h.header());

      expect(h.files.contents['/etc/out'], 'token=alpha');
    });

    test('the row is DECLARED rather than proven, exactly as a measured argument is', () async {
      // Named through the measured ARGUMENTS alone, a row wired only through a mapping entry answers
      // that nothing here is measured — and is stamped proven over a value the fingerprint never
      // saw. The neighbour below is what says this is about the wiring and not about the step.
      final Harness h = Harness();
      h.files.contents['/etc/one'] = 'alpha\n';
      final ResolvedProgram program = ProgramResolver(
        registryOfSteps(),
      ).resolve(fillsFromAMeasurement());

      final RunRecord record = await h.runner.run(
        program: program,
        mode: Mode.run,
        header: h.header(),
      );

      expect(record.steps.last.standing, StepStanding.declared);
      expect(record.fullyProven, isFalse);
    });

    test('THE INNOCENT NEIGHBOUR: the same row with the value written out is proven', () async {
      final Harness h = Harness();
      h.files.contents['/etc/one'] = 'alpha\n';
      final ResolvedProgram program = ProgramResolver(
        registryOfSteps(),
      ).resolve(fillsFromAMeasurement(body: 'alpha'));

      final RunRecord record = await h.runner.run(
        program: program,
        mode: Mode.run,
        header: h.header(),
      );

      expect(h.files.contents['/etc/out'], 'token=alpha');
      expect(record.steps.last.standing, StepStanding.proven);
      expect(record.fullyProven, isTrue);
    });

    test('a dry run does not build the row, and names the entry it cannot know yet', () async {
      final Harness h = Harness();
      h.files.contents['/etc/one'] = 'alpha\n';
      final ResolvedProgram program = ProgramResolver(
        registryOfSteps(),
      ).resolve(fillsFromAMeasurement());

      await h.runner.run(
        program: program,
        mode: Mode.dry,
        header: h.header(mode: Mode.dry),
      );

      expect(h.files.written, isEmpty);
      expect(
        h.recorder.events.whereType<Planned>().last.plan.summary,
        'not known yet: "values" entry "run-id" holds the measurement "reading", which step 1 '
        'measures takes while the run happens',
      );
    });

    /// Two rows that measure two files, renamed apart, and a third whose entry takes the name
    /// [fills] gives it. Which of the two rows produces that value is the ONLY thing a caller
    /// varies.
    String fingerprintOfRowsPublishing({
      required MeasurementName byTheFirstRow,
      required MeasurementName byTheSecondRow,
      required MeasurementName fills,
    }) => fingerprintOf(
      program: ProgramResolver(registryOfSteps()).resolve(
        programOfRows(<ProgramStep>[
          row(
            'measures',
            <String, Object>{'file': '/etc/one'},
            publish: <MeasurementName, MeasurementName>{reading: byTheFirstRow},
          ),
          row(
            'measures',
            <String, Object>{'file': '/etc/two'},
            publish: <MeasurementName, MeasurementName>{reading: byTheSecondRow},
          ),
          row('fills', <String, Object>{
            'path': '/etc/out',
            'template': 'token=<run-id>',
            'values': <String, Object?>{
              'run-id': <String, Object?>{'measured': fills.value},
            },
          }),
        ]),
      ),
      commit: '0000000',
      answers: Arguments.none,
    );

    test('two programs whose entry reads from a DIFFERENT ROW hash differently', () {
      // The value cannot be in the fingerprint — it does not exist when the fingerprint is built —
      // so what has to be in it is the WIRING: the name the entry takes, and the row that produces
      // it. The two programs below are written word for word alike, down to the body of the entry,
      // and differ in one thing: the first reads what step 1 measured off /etc/one, the second what
      // step 2 measured off /etc/two. Hashed alike, a clean dry run of the one admits a real run of
      // the other, and the slot is filled from the other file.
      expect(
        fingerprintOfRowsPublishing(byTheFirstRow: first, byTheSecondRow: second, fills: first),
        isNot(
          fingerprintOfRowsPublishing(byTheFirstRow: second, byTheSecondRow: first, fills: first),
        ),
        reason:
            'the two programs differ only in which row produces the value the entry takes, and the '
            'gate that exists to notice a changed input cannot tell them apart',
      );
    });

    test('THE INNOCENT NEIGHBOUR: the same wiring twice hashes the same', () {
      // Without this the test above would pass over a fingerprint that never comes out equal, and
      // a difference would mean nobody was comparing rather than that the wiring was seen.
      expect(
        fingerprintOfRowsPublishing(byTheFirstRow: first, byTheSecondRow: second, fills: first),
        fingerprintOfRowsPublishing(byTheFirstRow: first, byTheSecondRow: second, fills: first),
      );
    });

    test('an entry naming a measurement nothing publishes is refused', () {
      expect(
        () => ProgramResolver(registryOfSteps()).resolve(
          programOfRows(<ProgramStep>[
            row('fills', <String, Object>{
              'path': '/etc/out',
              'template': 'token=<run-id>',
              'values': <String, Object?>{
                'run-id': <String, Object?>{'measured': 'reading'},
              },
            }),
          ]),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => failure.message,
            'message',
            allOf(
              contains('fills "values" entry "run-id" from the measurement "reading"'),
              contains('no step of this program publishes it'),
            ),
          ),
        ),
      );
    });

    test('an entry taking a SECRET measurement is refused', () {
      expect(
        () => ProgramResolver(registryOfSteps(secret: true)).resolve(fillsFromAMeasurement()),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => failure.message,
            'message',
            allOf(
              contains('that measurement is secret'),
              contains('a mapping entry says nothing about what it holds'),
            ),
          ),
        ),
      );
    });
  });
}
