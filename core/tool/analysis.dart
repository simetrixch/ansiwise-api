/// The analyzer and the formatter, over every Dart package of this repository.
///
/// ```
/// dart run tool/analysis.dart
/// ```
///
/// The one check of this repository that is not a test, because it judges the analysis that
/// compiles the tests: a package it should have failed is a package whose suite does not run at
/// all. Everything it decides is in [AnalysisCheck] and [AnalysisReading]; this is the composition
/// root — it finds the packages, chooses the real toolchain, prints what came back and answers with
/// a status.
library;

import 'dart:io';

import 'gate/analysis_check.dart';
import 'gate/dart_packages.dart';
import 'gate/paths.dart';
import 'gate/real_dart_toolchain.dart';

/// Judges every package of this repository and answers non-zero when anything is wrong.
Future<void> main() async {
  final AnalysisReading reading = await AnalysisCheck(
    toolchain: const RealDartToolchain(),
    packages: dartPackagesIn(packageOfToolScript(Platform.script)),
  ).run();

  for (final AnalysisFinding finding in reading.findings) {
    stdout.writeln('  finding: $finding');
  }

  if (reading.green) {
    stdout.writeln(reading.verdictLine);
    return;
  }
  stderr.writeln(reading.verdictLine);
  exitCode = 1;
}
