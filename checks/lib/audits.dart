/// The SUITES that drive the audits, and every counter-probe that proves one can go red.
///
/// **The split from `ansiwise_checks.dart` is the whole point of this library.** That one holds what
/// DECIDES: an audit there takes a tree or a registry and returns findings, and it never asserts,
/// never prints and never exits. This one holds what DRIVES: it takes what a package points it at,
/// registers the assertions, states how much was covered, and plants the defects that show each scan
/// really goes red. It reaches `package:test`, which is why it is a library of its own — the
/// deciding half stays importable without a test framework behind it.
///
/// **WHY THE WIRING IS HERE AND NOT IN EACH PACKAGE.** It was in each package, copied. A new package
/// cost roughly two thousand one hundred lines of it before it could hold a single step, which made
/// splitting a package along the line it should be split along more expensive than leaving it wrong.
/// And every copy drifted: one tree's registry-completeness had lost the probe that says an entry
/// pointing at its own declaration is left alone, and one tree's line-endings measured a floor of
/// twenty files where its neighbour measured every Dart file it holds. Nothing reported either.
///
/// **THE COUNTER-PROBES TRAVEL WITH THE AUDIT.** This is what a shared driver is FOR, and it is the
/// part that decays fastest when copied: a probe planting yesterday's shape passes for years while
/// the subject moves away underneath it, and seven copies are seven places for that to happen
/// independently. Here, a probe is updated where the audit is.
///
/// **WHAT STAYS WITH THE PACKAGE.** Its `checks.yaml`; one short file per audit under `test/checks/`
/// saying which audit it runs and what it is pointed at; the fixtures that say how each of its steps
/// meets a fake machine; its ledger of steps a fake machine cannot exercise; its word list; and any
/// audit it alone runs. A package still has to be readable as a package — a harness nobody can read
/// from the package is a harness that judges the package by magic.
///
/// **EVERY AUDIT STATES HOW MUCH IT COVERED.** A driver that reported only pass or fail would take
/// the denominator away, and a check that covered nothing then reads exactly like a check that found
/// nothing. So each audit names its counts in the tests it registers: files read, directives
/// resolved, entries built, steps asked, steps run twice, words searched for.
library;

export 'src/audits/case_sensitivity_audit.dart';
export 'src/audits/composer_purity_audit.dart';
export 'src/audits/declared_answers_audit.dart';
export 'src/audits/declared_checks_audit.dart';
export 'src/audits/dry_safety_audit.dart';
export 'src/audits/exec_confinement_audit.dart';
export 'src/audits/idempotence_audit.dart';
export 'src/audits/line_endings_audit.dart';
export 'src/audits/naming_audit.dart';
export 'src/audits/registry_completeness_audit.dart';
export 'src/audits/reversibility_audit.dart';
export 'src/audits/word_purity_audit.dart';
