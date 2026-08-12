import 'arguments.dart';

/// Checks values against the specifications that declare them, and names every problem at once.
///
/// Two callers check the same thing for the same reason, and this is here so they cannot drift: a
/// program file hands a STEP its arguments, and an operator hands a PROGRAM its answers. Neither is
/// checked when the code is compiled — one crosses a configuration boundary, the other crosses the
/// wire — so both are checked here, before anything is looked at or touched.
///
/// Every problem, never the first: an operator fixing one refusal per run is an operator running it
/// five times to learn five things it could have been told at once.
///
/// [filledElsewhere] names what this check cannot see and the caller has already accounted for. One
/// case has it: a program row saying that an argument's value is measured during the run. Such a
/// name is not a missing value, and reporting it as one would send an operator to write a value on a
/// row that already says where its value comes from.
List<String> argumentProblems({
  required String where,
  required Arguments given,
  required List<ArgumentSpec> declared,
  required String noun,
  Set<String> filledElsewhere = const <String>{},
}) {
  final List<String> problems = <String>[];
  final Set<String> known = declared.map((ArgumentSpec s) => s.name).toSet();

  final RegExp hostnamePattern = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$');
  final RegExp mailboxPattern = RegExp(r'^[^@]+@[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+$');

  bool checkShape(String shape, String text) {
    if (shape == 'hostname') return hostnamePattern.hasMatch(text);
    if (shape == 'mailbox') return mailboxPattern.hasMatch(text);
    return true; // Should be prevented by loader
  }

  for (final ArgumentSpec spec in declared) {
    final Object? value = given.raw(spec.name);
    
    final StatedWhen? trigger = spec.statedWhen;
    bool shouldBeAsked = true;
    if (trigger != null) {
      final Object? triggerValue = given.raw(trigger.answer);
      if (trigger.equals != null) {
        shouldBeAsked = triggerValue.toString() == trigger.equals;
      } else {
        shouldBeAsked = triggerValue == given.raw(trigger.equalsAnswer!);
      }
    }

    if (value != null && !shouldBeAsked) {
      problems.add('$where: "${spec.name}" is given but its trigger does not hold');
    }

    if (value == null) {
      // A default is an answer nobody had to give, so a missing value with one behind it is not a
      // missing value at all.
      if (shouldBeAsked && spec.required && !spec.hasDefault && !filledElsewhere.contains(spec.name)) {
        problems.add('$where: needs the $noun "${spec.name}" — ${spec.describes}');
      }
      continue;
    }
    if (!spec.accepts(value)) {
      problems.add(
        '$where: "${spec.name}" holds ${spec.kind.name}, and was given ${value.runtimeType}',
      );
      continue;
    }

    if (spec.shape != null) {
      if (spec.kind == ArgumentKind.text) {
        if (!checkShape(spec.shape!, value as String)) {
          problems.add('$where: "${spec.name}" is of the wrong shape (must be ${spec.shape})');
        }
      } else if (spec.kind == ArgumentKind.textList) {
        for (final String item in value as List<String>) {
          if (!checkShape(spec.shape!, item.trim())) {
            problems.add('$where: "${spec.name}" item "$item" is of the wrong shape (must be ${spec.shape})');
          }
        }
      }
    }

    // Asked only once the kind is right: "holds one of master, slave" said about an int would be
    // true and useless.
    if (!spec.permits(value)) {
      if (value is String && spec.denied.contains(value)) {
        problems.add(
          '$where: "${spec.name}" must not be one of ${spec.denied.join(', ')}, and was given "$value"',
        );
      } else {
        problems.add(
          '$where: "${spec.name}" holds one of ${spec.allowed.join(', ')}, and was given "$value"',
        );
      }
    }
  }
  for (final String name in given.names) {
    if (!known.contains(name)) {
      problems.add('$where: has no $noun "$name"');
    }
  }
  return problems;
}
