import '../domain/argument_check.dart';
import '../domain/arguments.dart';
import '../domain/program.dart';
import '../domain/registry.dart';
import '../domain/resolved_program.dart';
import '../model/failures.dart';
import '../model/names.dart';

/// Finds every name a program writes in the registry, and refuses the program when one is missing.
///
/// This is where the safety a compiler cannot give across a configuration boundary is restored. A
/// program file hands a step some values, and nothing about that is checked when the code is
/// compiled. It is checked here instead, before the first thing is looked at: every step name,
/// every predicate name, every argument key, every argument kind, and every required argument.
///
/// A program that does not resolve is refused whole. Not the first bad entry — all of them, in one
/// message, because an operator fixing a program file one refusal per run is an operator running it
/// five times to learn five things it could have said at once.
final class ProgramResolver {
  /// Creates a resolver against [registry].
  const ProgramResolver(this.registry);

  /// What the names must be found in.
  final Registry registry;

  /// Binds [program] to the registry.
  ///
  /// Throws [ProgramInvalid] listing everything wrong with it.
  ResolvedProgram resolve(Program program) {
    final List<String> problems = <String>[];
    final List<ResolvedStep> resolved = <ResolvedStep>[];
    // Which program-wide defaults some step DECLARES, and which ones actually filled a row. Both
    // are needed because they fail differently: a name nothing declares is a misspelling, and a
    // name every row overrides is dead config. Neither is visible from the file, where both look
    // exactly like a key that decides something.
    final Set<String> defaultsDeclared = <String>{};
    final Set<String> defaultsFilled = <String>{};

    for (int i = 0; i < program.steps.length; i++) {
      final ProgramStep entry = program.steps[i];
      final String where = '${program.name}[$i] ${entry.step}';

      final RegisteredStep? registered = registry.step(entry.step);
      if (registered == null) {
        problems.add('$where: no step is registered under that name');
        continue;
      }

      // Folded in HERE and not where a step is executed, so everything downstream reads one set of
      // values: the argument check below, the plan, the record, and the fingerprint a run is gated
      // against. A default applied later than this would leave the fingerprint blind to it, and a
      // run would pass the gate of a dry run made under other values.
      final ProgramStep filled = _filled(
        entry,
        registered,
        program.defaults,
        defaultsDeclared,
        defaultsFilled,
        problems,
      );

      for (final String answer in registered.answers) {
        if (program.answers.named(answer) == null) {
          problems.add('$where: reads the answer "$answer", and this program does not declare it');
        }
      }
      problems.addAll(
        argumentProblems(
          where: where,
          given: filled.arguments,
          declared: registered.arguments,
          noun: 'argument',
        ),
      );

      final List<RegisteredPredicate> when = <RegisteredPredicate>[];
      for (final PredicateName name in entry.when) {
        final RegisteredPredicate? predicate = registry.predicate(name);
        if (predicate == null) {
          problems.add('$where: no predicate is registered under "$name"');
          continue;
        }
        when.add(predicate);
      }

      resolved.add(ResolvedStep(entry: filled, registered: registered, when: when));
    }

    for (final String name in program.defaults.names) {
      if (!defaultsDeclared.contains(name)) {
        problems.add(
          '${program.name}: no step of this program declares an argument named "$name", so the '
          'default written for it fills nothing',
        );
        continue;
      }
      if (!defaultsFilled.contains(name)) {
        problems.add(
          '${program.name}: every row that takes "$name" writes its own, so the default written '
          'for it fills nothing — leave it off a row, or take the default away',
        );
      }
    }

    if (problems.isNotEmpty) {
      throw ProgramInvalid(problems.join('\n'), where: program.name.value);
    }
    return ResolvedProgram(declared: program, steps: resolved);
  }

  /// [entry] with every program-wide default it takes written into its arguments.
  ///
  /// A default is taken when the step DECLARES an argument of that name and the row did not write
  /// one. Declaring is what decides it: handing a step a value it has no argument for would be an
  /// unknown key, and the argument check would refuse the row for a name the row does not carry.
  ///
  /// A default that fills a SECRET argument is refused into [problems] rather than folded in.
  ProgramStep _filled(
    ProgramStep entry,
    RegisteredStep registered,
    Arguments defaults,
    Set<String> declaredSomewhere,
    Set<String> filledSomewhere,
    List<String> problems,
  ) {
    final Map<String, ArgumentSpec> declared = <String, ArgumentSpec>{
      for (final ArgumentSpec spec in registered.arguments) spec.name: spec,
    };
    final Map<String, Object> applicable = <String, Object>{};
    for (final String name in defaults.names) {
      final ArgumentSpec? spec = declared[name];
      if (spec == null) {
        continue;
      }
      if (spec.secret) {
        // A program file ships inside the binary to every installation, so a credential written into
        // one is the same credential everywhere. The loader refuses this for a declared ANSWER for
        // the same reason; without it here, the block added for paths and key names would be the way
        // around that refusal.
        problems.add(
          'the default "$name" fills a secret argument, and a program file ships to every '
          'installation — a credential belongs in a declared answer, never here',
        );
        // Counted as filled as well, or the sweep below would add "every row writes its own" on top
        // of a refusal that has already said what is wrong.
        declaredSomewhere.add(name);
        filledSomewhere.add(name);
        continue;
      }
      declaredSomewhere.add(name);
      if (defaults.raw(name) case final Object value when entry.arguments.raw(name) == null) {
        applicable[name] = value;
        filledSomewhere.add(name);
      }
    }
    if (applicable.isEmpty) {
      return entry;
    }
    return ProgramStep(
      step: entry.step,
      onFailure: entry.onFailure,
      arguments: entry.arguments.withDefaults(applicable),
      when: entry.when,
      undo: entry.undo,
    );
  }
}
