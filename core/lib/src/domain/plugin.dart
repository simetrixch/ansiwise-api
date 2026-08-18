import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/failures.dart';
import '../model/names.dart';
import 'registry.dart';

/// What this framework can be taught, and the only way it learns anything about a particular world.
///
/// The framework knows how to run a program transactionally: check, plan, apply, check again, unwind
/// on failure. It knows nothing about what a step *does* — not a package manager, not a cluster, not
/// a secret store. Everything of that kind arrives here, in a plugin, and a check turns the tree red
/// if a word of it ever appears in the framework's own directories.
///
/// A plugin is compiled in rather than loaded. Dart ahead of time has no way to load code that was
/// not compiled with the binary, so "which plugins exist" is a fact of the build. What configuration
/// decides is which of the compiled-in ones are **active**, and that is a real decision: a binary
/// carrying three plugins runs the steps of the one named in its configuration and refuses the names
/// of the other two, so a program file cannot reach a step nobody turned on.
@immutable
abstract interface class Plugin {
  /// The name a configuration file writes to activate this plugin.
  ///
  /// Lower case with hyphens, matching the repository the plugin lives in, so the name in a
  /// configuration and the name of the thing it turns on are the same word.
  String get name;

  /// What this plugin teaches the framework: its steps, and the predicates they are gated on.
  Registry get registry;
}

/// The plugins a binary was built with, and the composition of the active ones into one registry.
///
/// Held apart from the binary's own entry point so it can be tested by calling it, which is what
/// makes "an unknown name is refused" a test rather than an intention.
@immutable
final class PluginSet {
  /// Creates the set from what the binary was compiled with.
  const PluginSet(this.available);

  /// Every plugin compiled into this binary, active or not.
  final List<Plugin> available;

  /// The names of everything compiled in, in the order they were given, for an error to list.
  List<String> get names => <String>[for (final Plugin plugin in available) plugin.name];

  /// Composes the plugins named in [active] into the one registry a catalogue is resolved against.
  ///
  /// Throws [PluginRejected] naming every problem at once, so a configuration is fixed in one pass
  /// rather than one error per attempt.
  Registry activate(List<String> active) {
    final List<String> problems = <String>[];

    if (active.isEmpty) {
      problems.add(
        'no plugin is active, so no step exists and every program would be refused\n'
        'name at least one of: ${names.join(', ')}',
      );
    }

    final Set<String> seen = <String>{};
    final List<Plugin> chosen = <Plugin>[];
    for (final String name in active) {
      if (!seen.add(name)) {
        problems.add('"$name" is activated twice');
        continue;
      }
      final Plugin? found = available.where((Plugin p) => p.name == name).firstOrNull;
      if (found == null) {
        // The distinction an operator needs, and the one a bare "unknown plugin" hides: the name is
        // not misspelled config, it is a plugin this BINARY was not built with. What follows is a
        // different build, not a different line in a file.
        problems.add(
          '"$name" is not compiled into this binary\n'
          'it carries: ${names.isEmpty ? "no plugins at all" : names.join(', ')}',
        );
        continue;
      }
      chosen.add(found);
    }

    // Two active plugins claiming one name would make which step runs depend on the order they were
    // listed in. Named as a problem rather than resolved by a rule nobody can see.
    final Map<String, List<String>> claimants = <String, List<String>>{};
    for (final Plugin plugin in chosen) {
      for (final StepName step in plugin.registry.steps.keys) {
        claimants.putIfAbsent(step.value, () => <String>[]).add(plugin.name);
      }
    }
    for (final MapEntry<String, List<String>> entry in claimants.entries) {
      if (entry.value.length > 1) {
        problems.add('the step "${entry.key}" is brought by ${entry.value.join(' and ')}');
      }
    }

    final Map<String, List<String>> predicateClaimants = <String, List<String>>{};
    for (final Plugin plugin in chosen) {
      for (final PredicateName predicate in plugin.registry.predicates.keys) {
        predicateClaimants.putIfAbsent(predicate.value, () => <String>[]).add(plugin.name);
      }
    }
    for (final MapEntry<String, List<String>> entry in predicateClaimants.entries) {
      if (entry.value.length > 1) {
        problems.add('the predicate "${entry.key}" is brought by ${entry.value.join(' and ')}');
      }
    }

    if (problems.isNotEmpty) {
      throw PluginRejected(problems.join('\n'));
    }

    return Registry(
      steps: <StepName, RegisteredStep>{
        for (final Plugin plugin in chosen) ...plugin.registry.steps,
      },
      predicates: <PredicateName, RegisteredPredicate>{
        for (final Plugin plugin in chosen) ...plugin.registry.predicates,
      },
    );
  }
}
