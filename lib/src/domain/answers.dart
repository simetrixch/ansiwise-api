import 'package:meta/meta.dart';

import '../model/failures.dart';
import 'argument_check.dart';
import 'arguments.dart';

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

    final List<String> problems = argumentProblems(
      where: program,
      given: Arguments(present),
      declared: specs,
      noun: 'answer',
    );
    if (problems.isNotEmpty) {
      throw AnswersRejected(problems.join('\n'));
    }

    return Arguments(present).withDefaults(<String, Object>{
      for (final ArgumentSpec spec in specs)
        if (spec.hasDefault) spec.name: spec.defaultValue!,
    });
  }
}

extension on Iterable<ArgumentSpec> {
  ArgumentSpec? get firstOrNull {
    final Iterator<ArgumentSpec> it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
