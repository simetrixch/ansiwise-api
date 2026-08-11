/// The audits that decide whether a plugin holds this framework's contract.
///
/// **An audit takes a tree or a registry and RETURNS findings.** It never asserts, never prints and
/// never exits. That is what lets a counter-probe drive the same audit over a tree it planted, and
/// what keeps a check from being a shell script with Dart syntax.
///
/// **What is here, what is in `audits.dart`, and what stays with the plugin.** Here: what decides.
/// In `audits.dart` beside it: the SUITE that drives each of these over what a package points it at,
/// states how much it covered, and plants the defect that proves it can go red. With the plugin: one
/// short file per audit saying which audit it runs and against what, the fixtures that say how each
/// of its steps meets a fake machine, its ledger of steps a fake machine cannot exercise, and its
/// word list.
///
/// **Why it is a package beside the framework rather than part of it.** An audit walks files, so it
/// needs `dart:io`, and the framework's exec-confinement rule forbids that outside
/// `infrastructure/` for everything that SHIPS. This ships nothing: it is development tooling, a dev
/// dependency, never compiled into a binary and never carried onto a machine. So the rule that keeps
/// a step from leaving the framework stays exactly as strict as it was.
///
/// **Why it is not copied per plugin.** It was, and the copies drifted — measurably. `SourceTree`
/// existed in two repositories and one of them had gained the ability to plant a non-text file,
/// which is how a check that reads content is shown to step past a binary. The other could not, so
/// it had no counter-probe for that case, and nothing reported the gap. A check nobody copied is
/// the purest form of a check that was skipped: it does not go red, it is simply absent.
library;

export 'src/composer_purity.dart';
export 'src/config_validity.dart';
export 'src/declared_answers.dart';
export 'src/declared_checks.dart';
export 'src/directive_case.dart';
export 'src/dry_safety.dart';
export 'src/exec_confinement.dart';
export 'src/finding.dart';
export 'src/idempotence.dart';
export 'src/installation_programs.dart';
export 'src/line_endings.dart';
export 'src/naming.dart';
export 'src/registry_completeness.dart';
export 'src/registry_reading.dart';
export 'src/reversibility.dart';
export 'src/source_tree.dart';
export 'src/step_under_probe.dart';
export 'src/word_purity.dart';
