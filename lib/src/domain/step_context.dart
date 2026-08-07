import 'package:meta/meta.dart';

import '../model/names.dart';
import 'arguments.dart';
import 'clock.dart';
import 'files.dart';
import 'http.dart';
import 'shell.dart';
import 'step_log.dart';

/// Everything a predicate is given in order to answer.
///
/// The four ports are the whole outside world. Nothing else is reachable, which is what makes a
/// predicate testable against a fake machine and unable to change the real one.
@immutable
base class PredicateContext {
  /// Creates the context a predicate is evaluated in.
  const PredicateContext({
    required this.shell,
    required this.files,
    required this.http,
    required this.clock,
    required this.log,
  });

  /// Running a command.
  final Shell shell;

  /// Reading and writing files.
  final Files files;

  /// Sending a request.
  final Http http;

  /// Asking the time and waiting.
  final Clock clock;

  /// Saying something in the record.
  final StepLog log;
}

/// Everything a step is given in order to do its work.
///
/// The ports handed in here are already scoped to this step: whatever they carry out reaches the
/// record attributed to it, and under a dry run they refuse anything the step did not declare as
/// only looking. A step therefore needs no knowledge of the mode it is running in, and cannot get
/// that knowledge wrong.
@immutable
final class StepContext extends PredicateContext {
  /// Creates the context a step runs in.
  const StepContext({
    this.answers = Arguments.none,
    required super.shell,
    required super.files,
    required super.http,
    required super.clock,
    required super.log,
    required this.step,
    required this.arguments,
    required this.facts,
  });

  /// The registered name of the step this context belongs to.
  final StepName step;

  /// The values the program gave this step, already validated against what it declared.
  final Arguments arguments;

  /// What the operator supplied for this run, already checked against the declaration.
  ///
  /// A step reads an answer BY NAME rather than finding it substituted into its arguments.
  /// Substitution would mean a program file that computes, and a file that computes is a file
  /// being debugged instead of the code.
  final Arguments answers;

  /// What the predicates found out about this machine before the run started.
  final Facts facts;
}

/// What the predicates found out about this machine.
///
/// Evaluated once, before the first step, so every step sees the same answers and a run cannot
/// change its mind about the machine halfway through.
@immutable
final class Facts {
  /// Holds the answers the predicates gave.
  const Facts(this._held);

  /// No facts, for a run with no predicates and for tests that need none.
  static const Facts none = Facts(<PredicateName, bool>{});

  final Map<PredicateName, bool> _held;

  /// Whether [predicate] held.
  ///
  /// Throws for a name that was never evaluated, rather than answering false. A step asking about a
  /// condition nobody measured is a defect in the program, and answering it quietly would hide that.
  bool held(PredicateName predicate) {
    final bool? answer = _held[predicate];
    if (answer == null) {
      throw ArgumentError.value(predicate.value, 'predicate', 'was never evaluated for this run');
    }
    return answer;
  }

  /// The names that were evaluated.
  Iterable<PredicateName> get evaluated => _held.keys;
}
