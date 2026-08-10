/// The audits that decide whether a plugin holds this framework's contract.
///
/// **An audit takes a tree or a registry and RETURNS findings.** It never asserts, never prints and
/// never exits. That is what lets a counter-probe drive the same audit over a tree it planted, and
/// what keeps a check from being a shell script with Dart syntax.
///
/// **What is here and what stays with the plugin.** Here: what decides. With the plugin: the wiring
/// that points an audit at that plugin's own registry and tree, the fixtures that say how each of
/// its steps meets a fake machine, and every counter-probe — because a counter-probe plants a defect
/// in a particular tree.
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
