/// From which step of a program there is no way back, decided before the run.
///
/// THE DATA WAS ALWAYS THERE AND NOBODY SAID IT. Every step already answers whether it can be taken
/// back, and a program row can now switch a step's undo off. What was missing is the sentence: an
/// operator reading a list of thirty steps, each carrying a `reversible` flag, has to find the
/// boundary themselves — and the moment they need it is the moment a run has gone wrong, which is
/// the worst moment to be counting.
///
/// WHAT THE BOUNDARY IS. The engine unwinds from the newest applied step backwards. It stops being
/// able to at the FIRST step it cannot take back: everything after that one stands, whatever
/// happens later, because the unwind cannot reach past it. So the boundary is that first step, and
/// everything from it onward is what a run would leave behind.
///
/// TWO REASONS A STEP IS PAST IT, and an operator is told which. A step may be irreversible by its
/// own nature, and then it says why — a value minted once, a file whose history has run out, a mail
/// already sent. Or the program may have switched its undo off, and then the answer is that somebody
/// decided so for this installation.
///
/// A STEP THAT CHANGES NOTHING IS NOT A BOUNDARY. An observing step measures and refuses; there is
/// nothing to take back and nothing it leaves behind, so it never moves the line.
library;

import '../domain/resolved_program.dart';
import '../domain/step.dart';
import '../model/names.dart';

/// Why a step cannot be taken back.
enum Irreversibility {
  /// The step itself says it cannot, and gives its own reason.
  byNature,

  /// The program says `undo: false` for this row.
  byDecision,
}

/// A step a run cannot take back, and why.
final class NoWayBack {
  /// Records that [step], at [position] in the program, cannot be taken back.
  const NoWayBack({
    required this.step,
    required this.position,
    required this.because,
    required this.reason,
  });

  /// The registered name, which is what a record and a screen both show.
  final StepName step;

  /// Where it stands in the program, counted from zero.
  final int position;

  /// Which of the two reasons applies.
  final Irreversibility because;

  /// What an operator is told.
  ///
  /// The step's own words where it is irreversible by nature, because "no undo was written" tells an
  /// operator nothing they can weigh and "the address pool a running cluster is using is gone" tells
  /// them everything.
  final String reason;

  @override
  String toString() => '$step: $reason';
}

/// Everything [program] could not take back, in the order the steps run.
///
/// Built by asking each step, which means building it — the registry holds a factory and not an
/// instance, and whether a step can be undone is a property of the class rather than of the file.
List<NoWayBack> whatStands(ResolvedProgram program) {
  final List<NoWayBack> standing = <NoWayBack>[];
  for (int position = 0; position < program.steps.length; position += 1) {
    final ResolvedStep resolved = program.steps[position];
    final Step step = resolved.registered.create(resolved.argumentsWithDefaults);

    // Measuring is not doing. An observing step leaves nothing behind, so it is not something a run
    // would fail to take back.
    if (step is ObservingStep) {
      continue;
    }
    if (step is! ReversibleStep) {
      standing.add(
        NoWayBack(
          step: resolved.entry.step,
          position: position,
          because: Irreversibility.byNature,
          reason: step is IrreversibleStep
              ? step.irreversibleReason
              : 'the step does not say how it could be taken back',
        ),
      );
      continue;
    }
    if (!resolved.entry.undo) {
      standing.add(
        NoWayBack(
          step: resolved.entry.step,
          position: position,
          because: Irreversibility.byDecision,
          reason:
              'this program says undo: false for this step, so what it does stands even though the '
              'step could take it back',
        ),
      );
    }
  }
  return standing;
}

/// The first step of [program] past which a run cannot be unwound, or null when every step can.
///
/// The FIRST and not the list, because that is the boundary: the unwind walks backwards and stops at
/// the earliest thing it cannot reverse, so everything from there onward stands together.
NoWayBack? pointOfNoReturn(ResolvedProgram program) {
  final List<NoWayBack> standing = whatStands(program);
  return standing.isEmpty ? null : standing.first;
}

/// One sentence an operator reads before starting, or null when the whole run can be taken back.
///
/// Written for somebody who has never opened a shell, which is who this framework is for. It names
/// the step, where it stands, and what it is that cannot be undone — not the fact that no undo
/// exists, which is a statement about our code rather than about their machine.
String? pointOfNoReturnSaid(ResolvedProgram program) {
  final NoWayBack? boundary = pointOfNoReturn(program);
  if (boundary == null) {
    return null;
  }
  final int human = boundary.position + 1;
  final int of = program.steps.length;
  return 'from step $human of $of, ${boundary.step}, this run cannot be taken back: '
      '${boundary.reason}';
}
