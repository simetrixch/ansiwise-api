import 'package:meta/meta.dart';

import '../model/failures.dart';
import 'argument_check.dart';
import 'arguments.dart';
import 'derivation.dart';

/// What a program has to be told before it can run, declared by the program and nothing else.
///
/// This is the difference between an argument and an answer, and it is the whole reason the client
/// has no hard-coded fields: a program file writes a step's ARGUMENTS itself, and an operator
/// supplies the program's ANSWERS. The domain name of the installation, the mailbox an alert goes
/// to, the credential a repository is cloned with — nobody can put those in a file that ships to
/// every installation.
///
/// So a program declares what it needs, and the client renders a form from that declaration. Adding
/// an input is a line in a program file; the client does not change, and a client standing in front
/// of a different plugin shows that plugin's questions instead. There is no list of fields anywhere
/// in the app, because a list of fields in the app is a list that is wrong for every deployment but
/// the one it was written against.
///
/// **An answer is never substituted into a program file.** A step that needs one reads it by name
/// out of its context. Substitution would mean a program file that computes, and a file that
/// computes is a file being debugged instead of the code.
@immutable
final class DeclaredAnswers {
  /// Declares what a program needs.
  const DeclaredAnswers(this.specs);

  /// A program that needs nothing.
  static const DeclaredAnswers none = DeclaredAnswers(<ArgumentSpec>[]);

  /// The declarations, in the order the program file wrote them — which is the order the form asks.
  final List<ArgumentSpec> specs;

  /// The names whose values must never reach a log, a plan or a run record.
  List<String> get secretNames => <String>[
    for (final ArgumentSpec spec in specs)
      if (spec.secret) spec.name,
  ];

  /// The declaration named [name], or null.
  ArgumentSpec? named(String name) => specs.where((ArgumentSpec s) => s.name == name).firstOrNull;

  /// Checks what an operator supplied and fills in the defaults.
  ///
  /// Throws [AnswersRejected] naming every problem at once — a missing required answer, one of the
  /// wrong kind, one nobody declared. This runs before the gate and before the first step, because
  /// an installation stopped halfway for a value somebody could have typed at the start is the
  /// worst of both.
  Arguments validate(Map<String, Object?> given, {required String program}) {
    final Map<String, Object> present = <String, Object>{
      for (final MapEntry<String, Object?> e in given.entries)
        if (e.value != null) e.key: e.value!,
    };

    // A derived answer follows from one already answered, so supplying it is supplying a second
    // version of the same fact — and a pair that does not match is exactly what deriving it is for.
    final List<String> supplied = <String>[
      for (final ArgumentSpec spec in specs)
        if (spec.isDerived && present.containsKey(spec.name)) spec.name,
    ];
    if (supplied.isNotEmpty) {
      throw AnswersRejected(
        '$program: ${supplied.join(', ')} '
        '${supplied.length == 1 ? 'is worked out' : 'are worked out'} from another answer and '
        '${supplied.length == 1 ? 'cannot be' : 'cannot be'} given as well',
      );
    }

    final List<String> problems = argumentProblems(
      where: program,
      given: Arguments(present),
      // EVERY declaration, including the ones nobody supplies. Filtering them out here would also
      // take them out of the set of names this program knows, and supplying one would then be
      // refused as an answer nobody declared — which is a true sentence about the wrong thing. That
      // an answer with a fallback cannot be MISSING is said where missing is decided.
      declared: specs,
      noun: 'answer',
    );
    if (problems.isNotEmpty) {
      throw AnswersRejected(problems.join('\n'));
    }

    final Arguments answered = Arguments(present).withDefaults(<String, Object>{
      for (final ArgumentSpec spec in specs)
        if (spec.hasDefault) spec.name: spec.defaultValue!,
    });

    return _derived(_fallenBack(answered, program: program), program: program);
  }

  /// [answered] with every answer nobody supplied filled from the answer it falls back to.
  ///
  /// Runs BEFORE the derivations, so an answer may be worked out from one that fell back — the
  /// fallback is what an operator would have typed, and a derivation reads what is there.
  Arguments _fallenBack(Arguments answered, {required String program}) {
    final List<String> problems = <String>[];
    final Map<String, Object> filled = <String, Object>{};

    for (final ArgumentSpec spec in specs) {
      final String? from = spec.defaultFrom;
      if (from == null || answered.raw(spec.name) != null) {
        continue;
      }
      final ArgumentSpec? source = named(from);
      if (source == null) {
        problems.add(
          '$program: "${spec.name}" falls back to "$from", and this program declares no such answer',
        );
        continue;
      }
      if (source.defaultFrom != null) {
        problems.add(
          '$program: "${spec.name}" falls back to "$from", which falls back in its turn — a chain '
          'is where an order of evaluation starts to matter, and reading the file would then mean '
          'working one out',
        );
        continue;
      }
      final Object? value = answered.raw(from);
      if (value == null) {
        problems.add(
          '$program: "${spec.name}" falls back to "$from", and nothing answered that either',
        );
        continue;
      }
      filled[spec.name] = value;
    }

    if (problems.isNotEmpty) {
      throw AnswersRejected(problems.join('\n'));
    }
    return answered.withDefaults(filled);
  }

  /// [answered] with every derived answer worked out and put beside the rest.
  ///
  /// Done HERE and not during the run, because this is the one point every later reader passes
  /// through: the fingerprint a real run is admitted against, the record, the gate and the steps all
  /// read what comes out of this method. A value worked out later would be outside the fingerprint,
  /// and a real run would then be admitted against a dry run that had used different values.
  ///
  /// One pass and not a chain. A derived answer is worked out from a SUPPLIED one, never from
  /// another derived one: a chain is where an order of evaluation starts to matter, and an order of
  /// evaluation is the beginning of the language a program file may not become.
  Arguments _derived(Arguments answered, {required String program}) {
    final List<String> problems = <String>[];
    final Map<String, Object> worked = <String, Object>{};

    for (final ArgumentSpec spec in specs) {
      final Derivation? how = spec.derivation;
      if (how == null) {
        continue;
      }
      final ArgumentSpec? source = named(how.from);
      if (source == null) {
        problems.add(
          '$program: "${spec.name}" is worked out from "${how.from}", and this program declares no '
          'such answer',
        );
        continue;
      }
      if (source.isDerived) {
        problems.add(
          '$program: "${spec.name}" is worked out from "${how.from}", which is itself worked out — '
          'a derived answer follows from one somebody supplied, so that no order of evaluation has '
          'to be understood to read the file',
        );
        continue;
      }
      final Object? value = answered.raw(how.from);
      if (value is! String) {
        problems.add(
          '$program: "${spec.name}" is worked out from "${how.from}", which holds no text — '
          '${value == null ? 'nothing answered it' : 'it holds ${value.runtimeType}'}',
        );
        continue;
      }
      // The SECOND source, for a rule that reads a pair. Held to exactly what the first is held to,
      // and the count is checked here rather than at the rule: a rule that reads a pair and is
      // given one name would otherwise work out a relation against the empty string, which answers
      // "false" and looks like a measurement.
      if (how.rule.sources == 2) {
        final String? second = how.and;
        if (second == null) {
          problems.add(
            '$program: "${spec.name}" is worked out by "${how.rule.written}", which reads a PAIR of '
            'answers, and only one was named — write the other under "and"',
          );
          continue;
        }
        final ArgumentSpec? other = named(second);
        if (other == null) {
          problems.add(
            '$program: "${spec.name}" is worked out from "$second", and this program declares no '
            'such answer',
          );
          continue;
        }
        if (other.isDerived) {
          problems.add(
            '$program: "${spec.name}" is worked out from "$second", which is itself worked out — '
            'a derived answer follows from one somebody supplied, so that no order of evaluation '
            'has to be understood to read the file',
          );
          continue;
        }
        final Object? otherValue = answered.raw(second);
        if (otherValue is! String) {
          problems.add(
            '$program: "${spec.name}" is worked out from "$second", which holds no text — '
            '${otherValue == null ? 'nothing answered it' : 'it holds ${otherValue.runtimeType}'}',
          );
          continue;
        }
        worked[spec.name] = how.rule.applyTo(value, otherValue);
        continue;
      }
      if (how.and != null) {
        problems.add(
          '$program: "${spec.name}" names a second answer under "and", and "${how.rule.written}" '
          'reads one answer — a name nothing reads would sit there looking as though it did',
        );
        continue;
      }
      worked[spec.name] = how.rule.applyTo(value);
    }

    if (problems.isNotEmpty) {
      throw AnswersRejected(problems.join('\n'));
    }
    return answered.withDefaults(worked);
  }
}

extension on Iterable<ArgumentSpec> {
  ArgumentSpec? get firstOrNull {
    final Iterator<ArgumentSpec> it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
