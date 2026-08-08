/// analysis — the analyzer and the formatter are clean for every Dart package of this tree.
///
/// `dart analyze --fatal-infos --fatal-warnings` with this repository's analysis_options is not a
/// style pass. strict-casts, strict-inference and strict-raw-types are on, so an implicit cast, an
/// inferred `dynamic` and a raw generic are each a type the author never chose and each stops the
/// build; unused_import, unused_local_variable and dead_code are raised to errors, which is the
/// no-leftovers rule of this project enforced by a tool rather than by a reviewer. `dart format
/// --set-exit-if-changed` is what keeps a diff about the change instead of about the whitespace.
///
/// THIS CANNOT BE A TEST OF THE PACKAGE IT JUDGES. A test is compiled by the analysis it is meant
/// to fail on, so the day the package stops analysing, the check meant to say so is the thing that
/// did not compile: either the package analyses and the test has nothing to report, or it does not
/// and the test never starts. It is a program the gate runs instead — `dart run tool/analysis.dart`
/// — and that is outside the suite without being outside Dart.
///
/// What it decides is here and what prints it is tool/analysis.dart, so the whole sequence can be
/// driven by a test against a scripted toolchain on a machine with neither tool installed. Reading
/// the two tools correctly is the part that rots silently, and test/checks/analysis_check_test.dart
/// is what holds it: a scripted answer for the parsing, and the real analyzer and formatter over a
/// planted package for the day either tool changes what it writes.
library;

import 'dart_packages.dart';
import 'dart_toolchain.dart';

/// How much weight the analyzer gives an issue.
///
/// All three count. `--fatal-infos --fatal-warnings` is what makes this repository's
/// analysis_options mean what it says: with strict-casts, strict-inference and strict-raw-types on,
/// an implicit cast, an inferred `dynamic` and a raw generic are each reported as an info, and each
/// is a type the author never chose.
enum AnalyzerSeverity {
  /// The code does not compile, or breaks a rule raised to an error.
  error,

  /// Something the analyzer reports as a warning by default.
  warning,

  /// Something the analyzer reports as an info by default.
  info,
}

/// One thing wrong with a package, as one of the two tools reported it.
///
/// A value with the tool's answer taken apart rather than the line it wrote, so a caller can count
/// the errors, group by package or print them however it likes without parsing anything a second
/// time.
sealed class AnalysisFinding {
  const AnalysisFinding(this.package);

  /// The package it is about, as its manifest names it.
  final String package;
}

/// The analyzer reported something.
final class AnalyzerIssue extends AnalysisFinding {
  /// Records an issue in [package], reported at [severity].
  const AnalyzerIssue(super.package, {required this.severity, required this.message});

  /// How much weight the analyzer gave it.
  final AnalyzerSeverity severity;

  /// What it said, without the severity it said it at.
  final String message;

  @override
  String toString() => '$package: ${severity.name} - $message';
}

/// The formatter would rewrite a file.
final class FormatterChange extends AnalysisFinding {
  /// Records that [file] of [package] is not formatted.
  const FormatterChange(super.package, this.file);

  /// The file, as the formatter named it.
  final String file;

  @override
  String toString() => '$package: dart format would change $file';
}

/// What the analyzer and the formatter made of a set of packages.
final class AnalysisReading {
  /// Records [findings] over the packages named in [judged].
  const AnalysisReading({required this.findings, required this.judged});

  /// Everything the two tools reported, analyzer before formatter, package by package.
  final List<AnalysisFinding> findings;

  /// The packages that were asked about, in the order they were asked.
  final List<String> judged;

  /// Whether the tools found nothing AND were pointed at something.
  ///
  /// A run over no package finds nothing for the same reason a run over a clean one does, and the
  /// two must not read the same: an empty tree is the one outcome that looks like a pass and is
  /// not.
  bool get green => findings.isEmpty && judged.isNotEmpty;

  /// What this run decided, in the one line a person reads.
  String get verdictLine {
    if (judged.isEmpty) {
      return 'analysis: FAIL — no Dart package was found to judge, so this check measured nothing';
    }
    if (findings.isNotEmpty) {
      return 'analysis: FAIL — ${findings.length} finding(s) above';
    }
    return 'analysis: OK — dart analyze --fatal-infos --fatal-warnings and dart format '
        '--output=none --set-exit-if-changed are clean for all ${judged.length} Dart package(s)';
  }
}

/// The check itself, over the packages and the toolchain it is given.
final class AnalysisCheck {
  /// Asks [toolchain] about each of [packages].
  const AnalysisCheck({required this.toolchain, required this.packages});

  /// How the two tools are started.
  final DartToolchain toolchain;

  /// What is judged.
  final List<DartPackage> packages;

  /// Runs both tools over every package.
  ///
  /// EVERY PACKAGE AND BOTH TOOLS RUN EVEN AFTER AN EARLIER ONE REPORTED SOMETHING. One finding
  /// hiding the rest is how the next run turns up a second problem that was there all along.
  Future<AnalysisReading> run() async {
    final List<AnalysisFinding> findings = <AnalysisFinding>[];
    final List<String> judged = <String>[];

    for (final DartPackage package in packages) {
      judged.add(package.name);
      findings.addAll(
        analyzerIssuesIn(
          await toolchain.analyze(directory: package.directory),
          package: package.name,
        ),
      );
      findings.addAll(
        formatterChangesIn(
          await toolchain.format(directory: package.directory),
          package: package.name,
        ),
      );
    }

    return AnalysisReading(findings: findings, judged: judged);
  }
}

/// Every issue in what the analyzer wrote about [package], one per line.
///
/// The exit status is not read: the analyzer answers 1, 2 and 3 for different severities and 0 for
/// a run that found nothing, and what this reports is the issues themselves. It writes a header and
/// a count around them, and neither is an issue.
List<AnalyzerIssue> analyzerIssuesIn(ToolRun run, {required String package}) => <AnalyzerIssue>[
  for (final String line in run.output.split('\n'))
    if (_issueLine.firstMatch(line.trimRight()) case final RegExpMatch match)
      if (match.group(1) case final String severity)
        if (match.group(2) case final String message)
          AnalyzerIssue(
            package,
            severity: AnalyzerSeverity.values.byName(severity),
            message: message.trim(),
          ),
];

/// Every file of [package] the formatter would change, one per line.
List<FormatterChange> formatterChangesIn(ToolRun run, {required String package}) =>
    <FormatterChange>[
      for (final String line in run.output.split('\n'))
        if (_changedLine.firstMatch(line.trimRight())?.group(1) case final String file)
          FormatterChange(package, file),
    ];

final RegExp _issueLine = RegExp(r'^\s*(error|warning|info) - (.*)$');

final RegExp _changedLine = RegExp(r'^Changed (.+)$');
