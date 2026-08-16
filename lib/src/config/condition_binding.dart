import 'package:meta/meta.dart';

import '../domain/argument_check.dart';
import '../domain/arguments.dart';
import '../domain/registry.dart';
import '../model/failures.dart';
import '../model/names.dart';

/// One condition an installation names: which generic condition it is, and what it is told.
///
/// Data and nothing else. Which of these values the condition actually accepts, and what kind each
/// of them holds, is not known here — only the registry knows that, so it is [bindConditions] that
/// answers it.
@immutable
final class ConditionBinding {
  /// Names the generic condition and the values bound to it.
  const ConditionBinding({required this.predicate, required this.values});

  /// The registered name of the generic condition this is one use of.
  final String predicate;

  /// What it is told, as named slots each holding exactly one value.
  ///
  /// Nothing here evaluates: no expression, no condition, no reference to another key. A slot holds
  /// the value that stands in the file and no other.
  final Map<String, Object> values;
}

/// [registry] with every condition [named] declares bound into it under the name it chose.
///
/// **This is where the generic condition a plugin brought becomes the concrete one a program row may
/// write.** The plugin registered "the key is true in that file" and could not say which file; the
/// program row wrote `when: [subject_enabled]` and could not say it either. The installation's own
/// configuration says both at once, here, before a single program is resolved.
///
/// [where] is the file the conditions were read from, so every refusal below sends the operator to
/// the place they have to edit.
///
/// Throws [PluginRejected] naming every problem at once, because an operator fixing one refusal per
/// run is an operator running it five times to learn five things.
Registry bindConditions({
  required Registry registry,
  required Map<String, ConditionBinding> named,
  required String where,
}) {
  if (named.isEmpty) {
    return registry;
  }

  final List<String> problems = <String>[];
  final Map<PredicateName, RegisteredPredicate> bound = <PredicateName, RegisteredPredicate>{};

  for (final MapEntry<String, ConditionBinding> entry in named.entries) {
    final PredicateName name = PredicateName(entry.key);
    final ConditionBinding binding = entry.value;
    final String said = '$where: the condition "${entry.key}"';

    if (registry.predicates.containsKey(name)) {
      // Two things under one name would make which condition a row means depend on the order they
      // were composed in, which is not something the file states and not something a reader could
      // work out.
      problems.add(
        '$said is already registered by a plugin, so nothing would say which of the two a program '
        'row means — give this one another name',
      );
      continue;
    }

    final RegisteredPredicate? generic = registry.predicate(PredicateName(binding.predicate));
    if (generic == null) {
      problems.add(
        '$said is "${binding.predicate}", and nothing is registered under that name\n'
        'this binary carries: ${_written(registry)}',
      );
      continue;
    }
    if (!generic.takesArguments) {
      problems.add(
        '$said is "${binding.predicate}", which is told nothing and is already a condition a '
        'program row may write — name it directly rather than binding it here',
      );
      continue;
    }

    final Map<String, Object> defaults = <String, Object>{
      for (final ArgumentSpec spec in generic.arguments)
        if (spec.defaultValue case final Object value) spec.name: value,
    };
    final Arguments values = Arguments(binding.values).withDefaults(defaults);
    final List<String> wrong = argumentProblems(
      where: said,
      given: values,
      declared: generic.arguments,
      noun: 'value',
    );
    if (wrong.isNotEmpty) {
      problems.addAll(wrong);
      continue;
    }

    bound[name] = generic.boundTo(name, values);
  }

  if (problems.isNotEmpty) {
    throw PluginRejected(problems.join('\n'));
  }

  return Registry(
    steps: registry.steps,
    predicates: <PredicateName, RegisteredPredicate>{...registry.predicates, ...bound},
  );
}

/// The conditions [registry] holds, for a refusal that has to say what there was.
String _written(Registry registry) {
  final List<String> names = <String>[
    for (final RegisteredPredicate each in registry.predicates.values)
      if (each.takesArguments) each.name.value,
  ]..sort();
  return names.isEmpty ? 'no condition that is told what to look at' : names.join(', ');
}
