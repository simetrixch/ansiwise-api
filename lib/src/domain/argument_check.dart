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
List<String> argumentProblems({
  required String where,
  required Arguments given,
  required List<ArgumentSpec> declared,
  required String noun,
}) {
  final List<String> problems = <String>[];
  final Set<String> known = declared.map((ArgumentSpec s) => s.name).toSet();

  for (final ArgumentSpec spec in declared) {
    final Object? value = given.raw(spec.name);
    if (value == null) {
      // A default is an answer nobody had to give, so a missing value with one behind it is not a
      // missing value at all.
      if (spec.required && !spec.hasDefault) {
        problems.add('$where: needs the $noun "${spec.name}" — ${spec.describes}');
      }
      continue;
    }
    if (!spec.accepts(value)) {
      problems.add(
        '$where: "${spec.name}" holds ${spec.kind.name}, and was given ${value.runtimeType}',
      );
    }
  }
  for (final String name in given.names) {
    if (!known.contains(name)) {
      problems.add('$where: has no $noun "$name"');
    }
  }
  return problems;
}
