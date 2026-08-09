import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/analysis_check.dart';
import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/dart_toolchain.dart';
import '../../tool/gate/fake_dart_toolchain.dart';
import '../../tool/gate/real_dart_toolchain.dart';

/// The counter-probe of the one check that cannot be a test of this package.
///
/// `tool/analysis.dart` judges the package this file is compiled into, so it is a program rather
/// than a test: a test would be compiled by the analysis it is meant to fail on, and the day the
/// package stops analysing, the check meant to say so is the thing that did not compile.
///
/// What is left over is everything that CAN be proven without judging this package, and it is in
/// two halves. The first hands the check an answer and reads what it decided; it needs no toolchain
/// at all, and it is what catches a rule that stopped matching the shape either tool writes. The
/// second runs the REAL analyzer and the REAL formatter over packages written here, one carrying a
/// defect and one carrying none, and asserts that both go red on the first and stay silent on the
/// second. A green gate over a repository nobody looked at is what a check rots into, and the only
/// thing that rules it out is watching the tools report something.
void main() {
  group('what the check makes of an answer', () {
    test('the analyzer output is read one issue per line, with its severity', () {
      final List<AnalyzerIssue> issues = analyzerIssuesIn(
        const ToolRun(
          exitCode: 3,
          output:
              'Analyzing planted...\n'
              '  error - lib/planted.dart:2:19 - A value of type String cannot be assigned - '
              'invalid_assignment\n'
              'warning - lib/planted.dart:5:7 - The value of the local variable is not used - '
              'unused_local_variable\n'
              '   info - lib/planted.dart:3:3 - Unused import - unused_import\n'
              '3 issues found.\n',
        ),
        package: 'planted',
      );

      expect(
        issues,
        hasLength(3),
        reason: 'the analyzer writes a header and a count around its issues, and neither is one',
      );
      expect(
        issues.map((AnalyzerIssue issue) => issue.severity),
        <AnalyzerSeverity>[AnalyzerSeverity.error, AnalyzerSeverity.warning, AnalyzerSeverity.info],
        reason:
            'all three are fatal here — with --fatal-infos --fatal-warnings an implicit cast is '
            'reported as an info and is still a type the author never chose',
      );
      expect(issues.first.message, startsWith('lib/planted.dart:2:19'));
      expect(issues.first.package, 'planted');
    });

    test('a clean analyzer run reports nothing', () {
      expect(
        analyzerIssuesIn(
          const ToolRun(exitCode: 0, output: 'Analyzing planted...\nNo issues found!\n'),
          package: 'planted',
        ),
        isEmpty,
        reason: 'this rule reports every line, so it would turn every package red',
      );
    });

    test('the formatter output names the files it would change', () {
      expect(
        formatterChangesIn(
          const ToolRun(
            exitCode: 1,
            output: 'Changed lib/planted.dart\nFormatted 3 files (1 changed) in 0.04 seconds.\n',
          ),
          package: 'planted',
        ).map((FormatterChange change) => change.file),
        <String>['lib/planted.dart'],
        reason: 'the summary line is not a change, and the changed file is what a person opens',
      );
    });

    test('a formatter run that would change nothing reports nothing', () {
      expect(
        formatterChangesIn(
          const ToolRun(exitCode: 0, output: 'Formatted 3 files (0 changed) in 0.04 seconds.\n'),
          package: 'planted',
        ),
        isEmpty,
      );
    });
  });

  group('what the check does with the toolchain', () {
    test('both tools are asked about every package, in order', () async {
      final FakeDartToolchain toolchain = FakeDartToolchain();
      await AnalysisCheck(toolchain: toolchain, packages: _packages(<String>['one', 'two'])).run();

      expect(toolchain.calls.map((ToolCall call) => call.what), <String>[
        'analyze',
        'format',
        'analyze',
        'format',
      ]);
    });

    test('a package the analyzer refused is still handed to the formatter', () async {
      final AnalysisReading reading = await AnalysisCheck(
        toolchain: FakeDartToolchain(
          answers: <String, ToolRun>{
            'analyze': const ToolRun(
              exitCode: 3,
              output: '  error - lib/a.dart:2:19 - A value of type String - invalid_assignment\n',
            ),
            'format': const ToolRun(exitCode: 1, output: 'Changed lib/a.dart\n'),
          },
        ),
        packages: _packages(<String>['one']),
      ).run();

      expect(reading.findings, hasLength(2));
      expect(reading.findings.whereType<AnalyzerIssue>(), hasLength(1));
      expect(reading.findings.whereType<FormatterChange>(), hasLength(1));
      expect(
        reading.green,
        isFalse,
        reason: 'one finding hiding the rest is how the next run turns up a second problem',
      );
    });

    test('a clean reading says what it proved and over how many packages', () async {
      final AnalysisReading reading = await AnalysisCheck(
        toolchain: FakeDartToolchain(),
        packages: _packages(<String>['one', 'two']),
      ).run();

      expect(reading.green, isTrue);
      expect(reading.verdictLine, startsWith('analysis: OK — '));
      expect(reading.verdictLine, contains('all 2 Dart package(s)'));
    });

    test('a reading with findings counts them rather than repeating them', () {
      const AnalysisReading reading = AnalysisReading(
        findings: <AnalysisFinding>[FormatterChange('planted', 'lib/a.dart')],
        judged: <String>['planted'],
      );
      expect(reading.verdictLine, 'analysis: FAIL — 1 finding(s) above');
    });

    test('a run over no package at all is red, not quietly green', () {
      const AnalysisReading reading = AnalysisReading(
        findings: <AnalysisFinding>[],
        judged: <String>[],
      );
      expect(
        reading.green,
        isFalse,
        reason:
            'a run over nothing finds nothing for the same reason a run over a clean package does, '
            'and the two must not read the same',
      );
      expect(reading.verdictLine, contains('measured nothing'));
    });
  });

  group('counter-probe: the real tools still go red', () {
    // Both directions, or the probe proves nothing: the planted defect has to be reported AND the
    // correct neighbour has to be left alone, because a tool answering "everything is wrong" would
    // satisfy the red half on its own and turn every package red.

    late Directory broken;
    late Directory clean;

    setUpAll(() {
      broken = Directory.systemTemp.createTempSync('ansiwise-gate-broken-');
      clean = Directory.systemTemp.createTempSync('ansiwise-gate-clean-');
      Directory('${broken.path}/lib').createSync(recursive: true);
      Directory('${clean.path}/lib').createSync(recursive: true);
      File('${broken.path}/pubspec.yaml').writeAsStringSync('name: planted_broken\n');
      File('${clean.path}/pubspec.yaml').writeAsStringSync('name: planted_clean\n');
      File('${clean.path}/lib/planted.dart').writeAsStringSync(_acceptedByBoth);
    });

    tearDownAll(() {
      broken.deleteSync(recursive: true);
      clean.deleteSync(recursive: true);
    });

    test('a planted assignment of text to an int is reported', () async {
      File('${broken.path}/lib/planted.dart').writeAsStringSync(_refusedByTheAnalyzer);
      expect(
        analyzerIssuesIn(
          await const RealDartToolchain().analyze(directory: broken.path),
          package: 'planted_broken',
        ),
        isNotEmpty,
        reason: 'this check cannot go red on the analyzer, so its silence means nothing',
      );
    });

    test('a file with nothing wrong in it is not reported', () async {
      expect(
        analyzerIssuesIn(
          await const RealDartToolchain().analyze(directory: clean.path),
          package: 'planted_clean',
        ),
        isEmpty,
        reason: 'this check would turn every package red',
      );
    });

    test('a deliberately unformatted file is reported', () async {
      // The same directory, replanted: the analyzer's defect is a compile error and the formatter
      // parses before it decides, so a file that does not parse would answer the formatter's half
      // of this probe with silence for the wrong reason.
      File('${broken.path}/lib/planted.dart').writeAsStringSync(_rewrittenByTheFormatter);
      expect(
        formatterChangesIn(
          await const RealDartToolchain().format(directory: broken.path),
          package: 'planted_broken',
        ),
        isNotEmpty,
        reason: 'this check cannot go red on the formatter',
      );
    });

    test('an already formatted file is not reported as needing a change', () async {
      expect(
        formatterChangesIn(
          await const RealDartToolchain().format(directory: clean.path),
          package: 'planted_clean',
        ),
        isEmpty,
      );
    });
  });
}

/// One package per name, in that order, each in a scratch directory of its own.
List<DartPackage> _packages(List<String> names) {
  final Directory scratch = Directory.systemTemp.createTempSync('ansiwise-analysis-check-');
  addTearDown(() => scratch.deleteSync(recursive: true));
  return <DartPackage>[
    for (final String name in names) DartPackage(directory: '${scratch.path}/$name', name: name),
  ];
}

const String _refusedByTheAnalyzer =
    'void main() {\n'
    '  final int planted = "this is text, and the analyzer refuses the assignment";\n'
    '  print(planted);\n'
    '}\n';

const String _rewrittenByTheFormatter = 'void main(){int   planted=1;print(planted);}\n';

const String _acceptedByBoth = 'void main() {\n  print(1);\n}\n';
