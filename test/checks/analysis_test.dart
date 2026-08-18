import 'package:ansiwise_checks_tree/audits.dart';

/// analysis — the analyzer and the formatter are clean over this package's own tree.
///
/// This repository DOES already run both, through its own gate at tool/ci.dart. That is not the
/// same statement. The gate is one program somebody has to start; this is a check the suite carries,
/// so it answers under a plain `dart test`, and so `declared-checks` reports it the day somebody
/// deletes it. Every other package here answers both tools that way, and a framework held to less
/// than what it ships to its plugins is the wrong way round.
void main() => auditAnalysis();
