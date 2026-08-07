import '../domain/argument_check.dart';
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

    for (int i = 0; i < program.steps.length; i++) {
      final ProgramStep entry = program.steps[i];
      final String where = '${program.name}[$i] ${entry.step}';

      final RegisteredStep? registered = registry.step(entry.step);
      if (registered == null) {
        problems.add('$where: no step is registered under that name');
        continue;
      }

      for (final String answer in registered.answers) {
        if (program.answers.named(answer) == null) {
          problems.add('$where: reads the answer "$answer", and this program does not declare it');
        }
      }
      problems.addAll(
        argumentProblems(
          where: where,
          given: entry.arguments,
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

      resolved.add(ResolvedStep(entry: entry, registered: registered, when: when));
    }

    if (problems.isNotEmpty) {
      throw ProgramInvalid(problems.join('\n'), where: program.name.value);
    }
    return ResolvedProgram(declared: program, steps: resolved);
  }
}
