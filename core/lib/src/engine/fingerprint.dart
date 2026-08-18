import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/arguments.dart';
import '../domain/registry.dart';
import '../domain/resolved_program.dart';

/// What makes two runs the same input.
///
/// The gate refuses a real run unless a clean dry run exists for exactly this value, so what goes
/// into it decides what an operator is allowed to change between the two. Each part is here for a
/// reason a reader should not have to guess:
///
/// - **the program's name** — the obvious one
/// - **every argument every step resolved to**, defaults included, because a default that changed
///   in the code between the dry run and the real one is a changed input even though nobody typed
///   anything
/// - **every ANSWER the program declared**, because a step reads answers by name out of the run and
///   they decide what it does: which branch is cut, which configuration file is written, which
///   machine is treated as the master. A dry run of one installation would otherwise admit a real
///   run of another
/// - **whether each row may be taken back**, because a row whose undo is switched off moves the
///   point of no return, and the operator read that boundary off the dry run
/// - **the WIRING of every argument whose value is measured while the run happens** — the name it
///   takes, and the row that produces it. The value itself cannot be here: it does not exist yet
///   when this is computed. What the material therefore states is exactly which arguments were left
///   out and where each of them will come from, so a row rewired between two runs cannot hash like
///   the one before it. A row is only ever bound to a measurement the resolver found an earlier row
///   publishing, and only ever on an argument the step declares — which is what makes walking the
///   DECLARED arguments below enough to see every wiring there is
/// - **every condition a row is gated on, and what that condition was pointed at** — a generic
///   condition is named by the installation and told what to look at there, so the name alone says
///   only half of what decides whether a row runs
/// - **the commit** the branch is on, because the same program at a different commit is a different
///   set of steps
///
/// What is deliberately NOT in it: the time, the run's own id, and the machine's own name. Those
/// differ between any two runs, and including them would mean no dry run ever satisfied the gate.
///
/// **A value cannot forge a field.** Every part is written with its length in front of it, so a
/// value carrying a newline is one value and not the start of another. Written as plain lines, a
/// step declaring text `a` and text `b` would fingerprint `a: "1\nb=2"` exactly like `a: "1"` with
/// `b: "2"` — two different runs, one hash, and the gate cannot tell them apart. Both are ordinary
/// quoted YAML scalars, so this is not a theoretical shape.
///
/// **What this still rests on:** a step's behaviour comes entirely from its declared arguments and
/// the answers it names. A step that reaches for a value from neither — a constant baked into its
/// constructor, something read from the environment — is invisible here, and two runs that differ
/// only in that value would fingerprint the same. That is the remaining way the gate can be fooled,
/// and it is a defect in the step: those are the two ways a value reaches a step, and a step taking
/// a third is a step nothing can gate.
String fingerprintOf({
  required ResolvedProgram program,
  required String commit,
  required Arguments answers,
}) {
  final StringBuffer material = StringBuffer();
  _field(material, 'program', program.declared.name.value);
  _field(material, 'commit', commit);

  // Sorted by the name the PROGRAM declared, so an answer file listing them in another order is the
  // same input. A declared answer that was not given is written as absent rather than skipped: an
  // answer going missing between the dry run and the real one is a changed input, and skipping it
  // would make the two hash alike.
  for (final ArgumentSpec spec in _sortedByName(program.declared.answers.specs)) {
    _valued(material, 'answer.${spec.name}', answers.raw(spec.name) ?? spec.defaultValue);
  }

  for (final ResolvedStep step in program.steps) {
    _field(material, 'step', step.entry.step.value);
    _field(material, 'on_failure', step.entry.onFailure.name);
    _field(material, 'undo', step.entry.undo.toString());
    for (final ArgumentSpec spec in _sortedByName(step.registered.arguments)) {
      // A value measured DURING the run cannot be in here, and what stands in its place is the
      // WIRING: which measurement fills this argument, and which row produces it. That is what
      // keeps two runs whose wiring differs from sharing a hash — rewiring a row to another
      // measurement, or to the same name published by another row, writes different material.
      // Without it the wiring would be nowhere in the material and a binary rebuilt with a row
      // rewired would fingerprint identically.
      //
      // The value is NOT written beside it, not even the step's own default. That default is what
      // makes the row examinable before the run; it is not what the step will run with, and writing
      // it would say the gate had seen a value it never sees.
      if (step.measurementFor(spec.name) case final MeasuredArgument measured) {
        _field(material, 'argument.${spec.name}.measured', measured.measurement.value);
        _field(
          material,
          'argument.${spec.name}.measured.from',
          '${measured.position}:${measured.publisher.value}',
        );
        continue;
      }
      final Object? given = step.entry.arguments.raw(spec.name);
      _valued(material, 'argument.${spec.name}', given ?? spec.defaultValue);
    }
    for (final RegisteredPredicate predicate in step.when) {
      _field(material, 'when', predicate.name.value);
      // What the condition was pointed at, where an installation pointed it. The name alone would
      // make two installations that gate on the same word and read different facts hash alike, and
      // then a clean dry run of one would admit a real run of the other. Sorted, so the order the
      // configuration file happened to write the keys in is not part of the input.
      for (final String value in predicate.bound.names.toList()..sort()) {
        _valued(material, 'when.${predicate.name.value}.$value', predicate.bound.raw(value));
      }
    }
  }

  return sha256.convert(utf8.encode(material.toString())).toString();
}

/// Writes one part of the material so nothing inside it can be read as a boundary.
///
/// The length is in BYTES rather than characters, because that is what is hashed — a character count
/// would let two values of different byte length share a prefix on a multi-byte character.
void _field(StringBuffer material, String name, String value) {
  final int nameBytes = utf8.encode(name).length;
  final int valueBytes = utf8.encode(value).length;
  material.write('$nameBytes:$name$valueBytes:$value');
}

/// Writes [name] against [value], or records that there was none.
///
/// **Absence is a different FIELD, not a reserved value.** An answer nobody gave and an answer given
/// as nothing lead a step to do different things, so the two must not hash alike - and any marker
/// written in the value's place would be a value some run could legitimately hold.
///
/// **A LIST is written entry by entry, and never as one string.** `['a', 'b'].toString()` and
/// `['a, b'].toString()` are both `[a, b]`, so a list written through `toString` hashes two different
/// runs alike: a gate demanding two commands, and a gate demanding one command whose name happens to
/// contain a comma. The length in front of a field guards the boundary between FIELDS; this is the
/// boundary between ENTRIES, and it needs its own.
void _valued(StringBuffer material, String name, Object? value) {
  if (value == null) {
    _field(material, '$name.absent', '');
    return;
  }
  if (value case final List<Object?> entries) {
    // The count goes in as well. Without it a list holding one empty entry and a list holding none
    // would write the same nothing, and they are different values.
    _field(material, '$name.count', entries.length.toString());
    for (int at = 0; at < entries.length; at += 1) {
      _valued(material, '$name.$at', entries[at]);
    }
    return;
  }
  _field(material, name, value.toString());
}

List<ArgumentSpec> _sortedByName(List<ArgumentSpec> specs) {
  // Sorted, so that reordering a step's declared arguments in the code does not change the
  // fingerprint of a program nobody touched.
  final List<ArgumentSpec> copy = List<ArgumentSpec>.of(specs)
    ..sort((ArgumentSpec a, ArgumentSpec b) => a.name.compareTo(b.name));
  return copy;
}
