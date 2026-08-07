import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/arguments.dart';
import '../domain/registry.dart';
import '../domain/resolved_program.dart';

/// What makes two runs the same input.
///
/// The gate refuses a real run unless a clean dry run exists for exactly this value, so what goes
/// into it decides what an operator is allowed to change between the two. Three things go in, and
/// each is here for a reason a reader should not have to guess:
///
/// - **the program's name** — the obvious one
/// - **every argument every step resolved to**, defaults included, because a default that changed
///   in the code between the dry run and the real one is a changed input even though nobody typed
///   anything
/// - **the commit** the branch is on, because the same program at a different commit is a different
///   set of steps
///
/// What is deliberately NOT in it: the time, the run's own id, and the machine's own name. Those
/// differ between any two runs, and including them would mean no dry run ever satisfied the gate.
///
/// **What this rests on:** a step's behaviour comes entirely from its declared arguments. A step
/// that reaches for a value it did not declare — a constant baked into its constructor, something
/// read from the environment — is invisible here, and two runs that differ only in that value would
/// fingerprint the same. That is the one way the gate can be fooled, and it is a defect in the step
/// rather than in this function: the registry builds every step from its arguments, and there is no
/// other way in.
String fingerprintOf({required ResolvedProgram program, required String commit}) {
  final StringBuffer material = StringBuffer()
    ..writeln(program.declared.name.value)
    ..writeln(commit);

  for (final ResolvedStep step in program.steps) {
    material
      ..writeln(step.entry.step.value)
      ..writeln(step.entry.onFailure.name);
    for (final ArgumentSpec spec in _sortedByName(step.registered.arguments)) {
      final Object? given = step.entry.arguments.raw(spec.name);
      material.writeln('${spec.name}=${given ?? spec.defaultValue}');
    }
    for (final RegisteredPredicate predicate in step.when) {
      material.writeln('when=${predicate.name.value}');
    }
  }

  return sha256.convert(utf8.encode(material.toString())).toString();
}

List<ArgumentSpec> _sortedByName(List<ArgumentSpec> specs) {
  // Sorted, so that reordering a step's declared arguments in the code does not change the
  // fingerprint of a program nobody touched.
  final List<ArgumentSpec> copy = List<ArgumentSpec>.of(specs)
    ..sort((ArgumentSpec a, ArgumentSpec b) => a.name.compareTo(b.name));
  return copy;
}
