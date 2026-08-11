import 'package:meta/meta.dart';

import '../model/names.dart';
import '../model/on_failure.dart';
import 'answers.dart';
import 'arguments.dart';

/// An ordered list of steps, and what each of them is allowed to cost.
///
/// A program is declared as data and never as code. It names steps, gives them arguments, puts
/// named conditions in front of some of them, and says what a failure costs. It cannot compute: no
/// loops, no expressions, no templating, no precedence between sources. The moment a program file
/// can compute, the thing being debugged is the file rather than the code, which is the state this
/// framework exists to avoid.
@immutable
final class Program {
  /// Creates a program.
  const Program({
    required this.name,
    required this.roles,
    required this.steps,
    this.answers = DeclaredAnswers.none,
    this.defaults = Arguments.none,
  });

  /// Its name, which is also the sub-command that runs it.
  final ProgramName name;

  /// The machine roles it applies to.
  ///
  /// A program run against a machine whose role is not in here is refused at the first gate, before
  /// anything is looked at.
  final List<Role> roles;

  /// The steps, in the order they run.
  final List<ProgramStep> steps;

  /// What an operator has to supply before this can run.
  ///
  /// Declared here rather than known by whatever starts the run, which is what lets one client
  /// stand in front of any plugin: it renders a form from this and hard-codes no field.
  final DeclaredAnswers answers;

  /// Values this program gives to every step that takes them and was not given them on its own row.
  ///
  /// **What this is for.** Several steps of one program regularly need the same value — where the
  /// profile of this installation stands, which key inside it holds an address, which permissions an
  /// argument file is written with. Writing it on every row means writing it thirty times, and the
  /// failure that follows is not the typing: it is the day one of them changes and twenty-nine rows
  /// are edited. The thirtieth is then wrong, and nothing reports it, because a row carrying a stale
  /// value is a valid row.
  ///
  /// **It is still data.** A map of names to values, resolved once against the registry before the
  /// run begins. There is no expression in it, nothing is computed from anything, and a reader sees
  /// the text that will be used.
  ///
  /// **A row always wins.** A value written on the row is what that step gets; this only fills what
  /// the row left out. The order is therefore row, then this, then what the step itself declares as
  /// its default — narrowest first, so nothing here can reach past a decision somebody made.
  ///
  /// **A name here that no step of this program declares is REFUSED**, with the program, before
  /// anything runs. A misspelled key would otherwise sit in the file filling nothing, and the run
  /// would go ahead on the step's own default while the file says something else.
  final Arguments defaults;

  /// Whether this program may be run against a machine of [role].
  bool appliesTo(Role role) => roles.contains(role);
}

/// One entry in a program: which step, with what, when, and what a failure costs.
@immutable
final class ProgramStep {
  /// Creates one entry in a program.
  const ProgramStep({
    required this.step,
    required this.onFailure,
    this.arguments = Arguments.none,
    this.reads = const <String, MeasurementName>{},
    this.when = const <PredicateName>[],
    this.undo = true,
  });

  /// The registered name of the step.
  final StepName step;

  /// What a failure of this step costs the run.
  ///
  /// Required, with no default. A default would be a policy nobody chose, applied to the step
  /// somebody forgot to think about — and the steps nobody thought about are exactly the ones whose
  /// failure policy turns out to be wrong.
  final OnFailure onFailure;

  /// The values this step is given.
  final Arguments arguments;

  /// Which of this step's arguments take their value from a measurement, and from which one.
  ///
  /// Keyed by the ARGUMENT the step declares, valued by the NAME an earlier row of this program
  /// publishes. In a file it is written where the value would stand — `resolvers: {measured:
  /// host.upstream_resolvers}` — so a reader sees on the row itself that this value comes off the
  /// machine rather than out of the file.
  ///
  /// **A named slot and nothing more.** The row names one measurement and takes the whole of it. It
  /// cannot be part of a larger string, cannot be tested, cannot be combined with another, and
  /// cannot appear twice in one value. Every one of those would be an expression, and a program file
  /// that can compute is a program file being debugged instead of the code.
  ///
  /// **What the resolver refuses about it**, before anything runs: an argument the step does not
  /// declare, one that does not hold text, one declared secret, a name no row of this program
  /// publishes, a name published by a row that runs later, a name published by a row that a
  /// condition may skip while this row runs, and a step that cannot be built at all while the value
  /// is missing — which is what everything examining a program before it runs has to do.
  final Map<String, MeasurementName> reads;

  /// The conditions that must all hold for this step to run.
  ///
  /// Combined with and, never with or. A condition that needs an or is two named conditions too
  /// few — and a program file that can express or is one expression away from being able to
  /// compute.
  final List<PredicateName> when;

  /// Whether this entry may be taken back when a later step ends the run.
  ///
  /// **True by default, and the operator is who turns it off.** A step that CAN be undone is not
  /// always a step that SHOULD be: taking a package manager's cache back onto a machine somebody has
  /// since been working on, or restoring a configuration a person edited in the meantime, is a
  /// correct undo doing damage. What is right there is a decision about one installation, so it is
  /// made in the program file rather than in the step.
  ///
  /// **It never makes an irreversible step reversible.** It only takes an undo away. A step that
  /// cannot be undone at all says so through its class, and no line in a program file changes that.
  ///
  /// **And it is said before the run, not afterwards.** A step whose undo is switched off is part of
  /// what the run cannot take back, so it moves the point of no return exactly as an irreversible
  /// step does — and an operator reads that boundary before deciding to start.
  final bool undo;
}
