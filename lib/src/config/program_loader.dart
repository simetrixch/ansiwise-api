/// Reads a program file into the data the resolver binds to the registry.
///
/// A program file is data and never logic, so this loader is deliberately dumb: it reads keys and
/// values, and it refuses everything it does not recognise. There is no loop, no expression, no
/// templating, no variable substitution, no include, and no anchor or alias that lets one part of a
/// file stand for another. A key nobody declared is refused rather than ignored — a loader that
/// ignores what it does not know turns a typo into a setting that silently went missing.
///
/// What it does not do is check a step's arguments against what that step declares. That is the
/// resolver's job, against the registry, and doing it twice would mean two places to keep in step.
library;

import 'package:yaml/yaml.dart';

import '../domain/answers.dart';
import '../domain/arguments.dart';
import '../domain/program.dart';
import '../model/failures.dart';
import '../model/names.dart';
import '../model/on_failure.dart';

/// Turns the text of a program file into a [Program].
///
/// [where] is the file it came from, and it is what a refusal is reported against.
///
/// Throws [ProgramInvalid] listing everything wrong with the file at once, one problem per line,
/// each carrying the line number wherever the parser gives one. An operator fixing a file one
/// refusal per run is an operator running it five times to learn five things.
Program loadProgram(String yaml, {required String where}) {
  final YamlNode root;
  try {
    root = loadYamlNode(yaml);
  } on YamlException catch (broken) {
    // Text that does not parse has no structure left to look for further problems in, so this is
    // the one refusal that reports a single thing. A duplicate key arrives here too: the parser
    // refuses it while composing the document, before there is anything to inspect.
    final int? line = broken.span?.start.line;
    throw ProgramInvalid(
      line == null ? broken.message : 'line ${line + 1}: ${broken.message}',
      where: where,
    );
  }

  final _Refusals refusals = _Refusals();
  _refuseAnchors(root, refusals);

  if (root is! YamlMap) {
    refusals.add(root.span.start.line, 'a program is a map with the keys "name", "roles", "steps"');
    refusals.refuse(where);
  }

  _refuseUnknownKeys(root, refusals);
  final ProgramName? name = _name(root, refusals);
  final List<Role> roles = _roles(root, refusals);
  final List<ProgramStep> steps = _steps(root, refusals);
  final DeclaredAnswers answers = _answers(root, refusals);

  // [_name] returns null only where it has already recorded a refusal, so the second half of this
  // condition never produces an empty message — and past it the name is a value rather than a
  // maybe, which is what lets the program be built without a null check.
  if (refusals.any || name == null) {
    refusals.refuse(where);
  }
  return Program(name: name, roles: roles, steps: steps, answers: answers);
}

/// What an operator has to supply, as the file declares it.
///
/// Absent means a program that needs nothing, which is a normal thing to be — every problem found
/// here is recorded and the reading continues, so a file with three bad declarations is told about
/// all three.
DeclaredAnswers _answers(YamlMap document, _Refusals refusals) {
  final YamlNode? node = document.nodes['answers'];
  if (node == null) {
    return DeclaredAnswers.none;
  }
  if (node is! YamlList) {
    refusals.add(node.span.start.line, '"answers" is a list of declarations');
    return DeclaredAnswers.none;
  }

  final List<ArgumentSpec> specs = <ArgumentSpec>[];
  final Set<String> seen = <String>{};
  for (final YamlNode entry in node.nodes) {
    final int line = entry.span.start.line;
    if (entry is! YamlMap) {
      refusals.add(line, 'an answer is a map with "name", "kind" and "describes"');
      continue;
    }
    for (final MapEntry<Object?, YamlNode> pair in entry.nodes.entries) {
      if (pair.key case YamlScalar(value: final String key)) {
        if (!_answerKeys.contains(key)) {
          refusals.add(_lineOf(pair.key) ?? line, 'an answer has no key "$key"');
        }
      }
    }

    final Object? name = entry['name'];
    if (name is! String || name.isEmpty) {
      refusals.add(line, 'an answer needs a "name"');
      continue;
    }
    if (!seen.add(name)) {
      // Two declarations under one name would make which one the form asks depend on order, and
      // the second silently wins wherever a map is built from them.
      refusals.add(line, 'the answer "$name" is declared twice');
      continue;
    }

    final Object? kind = entry['kind'];
    final ArgumentKind? resolved = kind is String ? _answerKinds[kind] : null;
    if (resolved == null) {
      refusals.add(line, '"$name" needs a "kind": ${_answerKinds.keys.join(', ')}');
      continue;
    }

    final Object? describes = entry['describes'];
    if (describes is! String || describes.isEmpty) {
      // Without it the form shows a bare field name to somebody who has never seen this system,
      // which is the whole failure this declaration exists to prevent.
      refusals.add(line, '"$name" needs "describes" — it is what the form shows the operator');
      continue;
    }

    final Object? isRequired = entry['required'];
    if (isRequired != null && isRequired is! bool) {
      refusals.add(line, '"$name": "required" is true or false');
      continue;
    }
    final Object? isSecret = entry['secret'];
    if (isSecret != null && isSecret is! bool) {
      refusals.add(line, '"$name": "secret" is true or false');
      continue;
    }

    final Object? fallback = entry['default'];
    if (fallback != null && isSecret == true) {
      // A default for a secret is a credential written into a file that ships to every
      // installation, which is the one thing this framework must never make easy.
      refusals.add(line, '"$name" is secret, so it cannot have a default');
      continue;
    }
    // The values this answer may hold, where it is one of a small closed set. Only text has one:
    // a flag already has two values, and a number or a list of text has no small closed set worth
    // writing out — so declaring one on those is refused rather than quietly ignored.
    final Object? permitted = entry['allowed'];
    final List<String> allowed = <String>[];
    if (permitted != null) {
      if (resolved != ArgumentKind.text) {
        refusals.add(line, '"$name" holds ${resolved.name}, and only text may name allowed values');
        continue;
      }
      if (permitted is! YamlList || permitted.isEmpty) {
        refusals.add(line, '"$name": "allowed" is a non-empty list of the values it may hold');
        continue;
      }
      for (final Object? each in permitted) {
        if (each is! String || each.isEmpty) {
          refusals.add(line, '"$name": "$each" is not a value it could hold');
          continue;
        }
        allowed.add(each);
      }
    }

    final Object? unwrapped = fallback is YamlList
        ? <String>[for (final Object? v in fallback) '$v']
        : fallback;
    if (unwrapped != null) {
      final ArgumentSpec probe = ArgumentSpec(
        name: name,
        kind: resolved,
        describes: describes,
        allowed: allowed,
      );
      if (!probe.accepts(unwrapped)) {
        refusals.add(
          line,
          '"$name" holds ${resolved.name}, and its default is ${unwrapped.runtimeType}',
        );
        continue;
      }
      // A default outside the set the same declaration names is a value the file itself calls
      // illegal, standing in wherever a program says nothing about the answer.
      if (!probe.permits(unwrapped)) {
        refusals.add(
          line,
          '"$name" holds one of ${allowed.join(', ')}, and its default is "$unwrapped"',
        );
        continue;
      }
    }

    specs.add(
      ArgumentSpec(
        name: name,
        kind: resolved,
        describes: describes,
        required: isRequired as bool? ?? true,
        secret: isSecret as bool? ?? false,
        defaultValue: unwrapped,
        allowed: allowed,
      ),
    );
  }
  return DeclaredAnswers(specs);
}

/// The keys a program file may write at the top level.
const Set<String> _programKeys = <String>{'name', 'roles', 'steps', 'answers'};

/// The keys one answer declaration may write.
const Set<String> _answerKeys = <String>{
  'name',
  'kind',
  'describes',
  'required',
  'secret',
  'default',
  'allowed',
};

/// The kinds an answer may declare, as a program file writes them.
const Map<String, ArgumentKind> _answerKinds = <String, ArgumentKind>{
  'text': ArgumentKind.text,
  'integer': ArgumentKind.integer,
  'flag': ArgumentKind.flag,
  'text_list': ArgumentKind.textList,
};

/// The keys of a step entry the loader reads. Every other key of an entry is an argument.
const Set<String> _stepKeys = <String>{'step', 'on_failure', 'when', 'undo'};

/// The whole vocabulary of `on_failure:`, as a program file writes it.
const Map<String, OnFailure> _policies = <String, OnFailure>{
  'die': OnFailure.die,
  'issue': OnFailure.issue,
  'warn': OnFailure.warn,
};

/// One thing wrong with a file, and where in it.
final class _Problem {
  const _Problem(this.line, this.found, this.what);

  /// The source line, as the parser counts it, from zero.
  final int line;

  /// How many problems were already found when this one was, which orders two on the same line.
  final int found;

  /// What is wrong there.
  final String what;
}

/// Everything wrong with one file, collected so all of it can be said in one refusal.
final class _Refusals {
  final List<_Problem> _problems = <_Problem>[];

  /// Whether anything has been refused.
  bool get any => _problems.isNotEmpty;

  /// Records [what], at the source line the parser counts from zero.
  void add(int line, String what) => _problems.add(_Problem(line, _problems.length, what));

  /// Throws everything collected so far as one refusal against [where].
  ///
  /// Sorted by line, so the refusal reads down the file the operator has open. That is not the
  /// order the problems were found in: anchors are looked for in one walk of the whole tree before
  /// a single key is read, and an entry is read after the keys above it whatever line it is on.
  /// [_Problem.found] breaks the tie between two problems on one line, because [List.sort] gives no
  /// promise about equal elements.
  Never refuse(String where) {
    final List<_Problem> ordered = _problems.toList()
      ..sort((_Problem a, _Problem b) {
        final int byLine = a.line.compareTo(b.line);
        return byLine != 0 ? byLine : a.found.compareTo(b.found);
      });
    throw ProgramInvalid(
      ordered.map((_Problem p) => 'line ${p.line + 1}: ${p.what}').join('\n'),
      where: where,
    );
  }
}

/// Refuses every anchor and every alias in the tree under [root].
///
/// The `yaml` package resolves aliases while parsing and reports nothing about them afterwards, so
/// there is no flag to read. Two things it does leave are enough. The parser expands a node's span
/// backwards over its `&anchor`, so an anchored node is the one whose source text starts with `&` —
/// which no plain scalar may. And an alias is loaded as the very node the anchor registered, so the
/// same object stands at both places and one report covers the pair.
///
/// The identity set is also what stops this walking forever: `&a [*a]` builds a list that contains
/// itself, because the anchor is registered before the children are read.
void _refuseAnchors(YamlNode root, _Refusals refusals) {
  final Set<YamlNode> seen = Set<YamlNode>.identity();
  final List<YamlNode> pending = <YamlNode>[root];

  while (pending.isNotEmpty) {
    final YamlNode node = pending.removeLast();
    if (!seen.add(node)) {
      continue;
    }
    if (node.span.text.startsWith('&')) {
      refusals.add(
        node.span.start.line,
        'an anchor or alias — a program file is data, and an alias lets one part of it stand for '
        'another',
      );
    }
    if (node is YamlList) {
      pending.addAll(node.nodes);
    } else if (node is YamlMap) {
      for (final MapEntry<Object?, YamlNode> pair in node.nodes.entries) {
        if (pair.key case final YamlNode key) {
          pending.add(key);
        }
        pending.add(pair.value);
      }
    }
  }
}

/// Refuses every top-level key that is not one of [_programKeys].
void _refuseUnknownKeys(YamlMap document, _Refusals refusals) {
  for (final MapEntry<Object?, YamlNode> pair in document.nodes.entries) {
    final int line = _lineOf(pair.key) ?? pair.value.span.start.line;
    if (pair.key case YamlScalar(value: final String key)) {
      if (!_programKeys.contains(key)) {
        refusals.add(
          line,
          'a program does not have a key "$key" — it has "name", "roles", "steps"',
        );
      }
      continue;
    }
    refusals.add(line, 'a key is text, and the file gives something else');
  }
}

/// The declared program name, or null when there is none to read.
///
/// Null means a refusal has already been recorded, which is what [loadProgram] leans on to build
/// the program without a null check.
ProgramName? _name(YamlMap document, _Refusals refusals) {
  final YamlNode? node = document.nodes['name'];
  if (node == null) {
    refusals.add(document.span.start.line, 'the file has no "name"');
    return null;
  }
  if (node.value case final String written) {
    if (ProgramName.isValid(written)) {
      return ProgramName(written);
    }
    refusals.add(
      node.span.start.line,
      '"$written" is not a program name — lower case letters, digits and dashes, starting with a '
      'letter',
    );
    return null;
  }
  refusals.add(node.span.start.line, '"name" is text, and the file gives ${_kindOf(node)}');
  return null;
}

/// The machine roles the program applies to.
List<Role> _roles(YamlMap document, _Refusals refusals) {
  final YamlNode? node = document.nodes['roles'];
  if (node == null) {
    refusals.add(document.span.start.line, 'the file has no "roles"');
    return const <Role>[];
  }
  if (node is! YamlList) {
    refusals.add(
      node.span.start.line,
      '"roles" is a list of role names, and the file gives ${_kindOf(node)}',
    );
    return const <Role>[];
  }
  if (node.nodes.isEmpty) {
    // Roles are what the first gate matches a machine against, so an empty list is a program no
    // machine can ever be given.
    refusals.add(node.span.start.line, '"roles" is empty, and no machine would match it');
    return const <Role>[];
  }

  final List<Role> roles = <Role>[];
  for (final YamlNode element in node.nodes) {
    if (element.value case final String written) {
      roles.add(Role(written));
      continue;
    }
    refusals.add(
      element.span.start.line,
      '"roles" holds role names, and the file gives ${_kindOf(element)}',
    );
  }
  return roles;
}

/// The entries of the program, in the order they are written.
List<ProgramStep> _steps(YamlMap document, _Refusals refusals) {
  final YamlNode? node = document.nodes['steps'];
  if (node == null) {
    refusals.add(document.span.start.line, 'the file has no "steps"');
    return const <ProgramStep>[];
  }
  if (node is! YamlList) {
    refusals.add(
      node.span.start.line,
      '"steps" is a list of entries, and the file gives ${_kindOf(node)}',
    );
    return const <ProgramStep>[];
  }
  if (node.nodes.isEmpty) {
    refusals.add(
      node.span.start.line,
      '"steps" is empty, and a program with no steps does nothing',
    );
    return const <ProgramStep>[];
  }

  final List<ProgramStep> steps = <ProgramStep>[];
  for (int i = 0; i < node.nodes.length; i++) {
    final ProgramStep? entry = _step(node.nodes[i], i, refusals);
    if (entry != null) {
      steps.add(entry);
    }
  }
  return steps;
}

/// One entry of the program, or null when it could not be read.
///
/// Every part of the entry is read even after one of them has been refused, so a single run reports
/// the bad step name and the missing failure policy together rather than one per run.
ProgramStep? _step(YamlNode node, int index, _Refusals refusals) {
  if (node is! YamlMap) {
    refusals.add(
      node.span.start.line,
      'steps[$index] is not a map — an entry names a step and gives it values',
    );
    return null;
  }

  final StepName? step = _stepName(node, index, refusals);
  final String label = step == null ? 'steps[$index]' : 'steps[$index] $step';
  final OnFailure? onFailure = _onFailure(node, label, refusals);
  final List<PredicateName> when = _when(node, label, refusals);
  final bool undo = _undo(node, label, refusals);
  final Arguments arguments = _arguments(node, label, refusals);

  if (step == null || onFailure == null) {
    return null;
  }
  return ProgramStep(
    step: step,
    onFailure: onFailure,
    arguments: arguments,
    when: when,
    undo: undo,
  );
}

/// Whether this entry may be taken back, which is true unless the file says otherwise.
///
/// The one key of an entry that HAS a default, and that is the opposite of how `on_failure` is
/// treated on purpose. A failure policy nobody chose gets applied to the step nobody thought about,
/// which is exactly the step whose policy turns out to be wrong — so it is required. Undo is the
/// other way round: a step that can be taken back should be, and switching that off is a decision
/// somebody makes about ONE installation. So the file says so where it is meant and stays quiet
/// everywhere else, and a reader who sees the key knows somebody decided.
bool _undo(YamlMap entry, String label, _Refusals refusals) {
  final YamlNode? node = entry.nodes['undo'];
  if (node == null) {
    return true;
  }
  if (node.value case final bool written) {
    return written;
  }
  refusals.add(
    node.span.start.line,
    '$label: "undo" is true or false, and the file gives ${_kindOf(node)}',
  );
  return true;
}

/// The registered step name an entry writes, or null when it is missing or malformed.
StepName? _stepName(YamlMap entry, int index, _Refusals refusals) {
  final YamlNode? node = entry.nodes['step'];
  if (node == null) {
    refusals.add(entry.span.start.line, 'steps[$index] has no "step"');
    return null;
  }
  if (node.value case final String written) {
    if (StepName.isValid(written)) {
      return StepName(written);
    }
    refusals.add(
      node.span.start.line,
      'steps[$index]: "$written" is not a step name — lower case letters, digits and underscores, '
      'starting with a letter',
    );
    return null;
  }
  refusals.add(
    node.span.start.line,
    'steps[$index]: "step" is text, and the file gives ${_kindOf(node)}',
  );
  return null;
}

/// What a failure of this entry costs the run.
///
/// There is no default. A default would be a policy nobody chose, applied to the step somebody
/// forgot to think about, and those are the steps whose failure policy turns out to be wrong.
OnFailure? _onFailure(YamlMap entry, String label, _Refusals refusals) {
  final YamlNode? node = entry.nodes['on_failure'];
  if (node == null) {
    refusals.add(entry.span.start.line, '$label has no "on_failure" — say die, issue or warn');
    return null;
  }
  if (node.value case final String written) {
    final OnFailure? policy = _policies[written];
    if (policy != null) {
      return policy;
    }
    refusals.add(
      node.span.start.line,
      '$label: "on_failure" is "$written", and it is one of die, issue or warn',
    );
    return null;
  }
  refusals.add(
    node.span.start.line,
    '$label: "on_failure" is one of die, issue or warn, and the file gives ${_kindOf(node)}',
  );
  return null;
}

/// The conditions that must all hold for this entry to run.
List<PredicateName> _when(YamlMap entry, String label, _Refusals refusals) {
  final YamlNode? node = entry.nodes['when'];
  if (node == null) {
    return const <PredicateName>[];
  }
  if (node is! YamlList) {
    refusals.add(
      node.span.start.line,
      '$label: "when" is a list of predicate names, and the file gives ${_kindOf(node)}',
    );
    return const <PredicateName>[];
  }

  final List<PredicateName> when = <PredicateName>[];
  for (final YamlNode element in node.nodes) {
    if (element.value case final String written) {
      if (PredicateName.isValid(written)) {
        when.add(PredicateName(written));
      } else {
        refusals.add(
          element.span.start.line,
          '$label: "$written" is not a predicate name — lower case letters, digits and '
          'underscores, starting with a letter',
        );
      }
      continue;
    }
    refusals.add(
      element.span.start.line,
      '$label: "when" holds predicate names, and the file gives ${_kindOf(element)}',
    );
  }
  return when;
}

/// Everything the entry says that is not [_stepKeys], as the values the step is given.
///
/// The values keep the types YAML gave them, so text stays a [String] and a whole number stays an
/// [int]. Whether the step declares the key at all, and whether the kind is the one it declared, is
/// checked against the registry afterwards.
Arguments _arguments(YamlMap entry, String label, _Refusals refusals) {
  final Map<String, Object> values = <String, Object>{};
  for (final MapEntry<Object?, YamlNode> pair in entry.nodes.entries) {
    if (pair.key case YamlScalar(value: final String key)) {
      if (_stepKeys.contains(key)) {
        continue;
      }
      final Object? value = _argument(pair.value, key, label, refusals);
      if (value != null) {
        values[key] = value;
      }
      continue;
    }
    refusals.add(
      _lineOf(pair.key) ?? pair.value.span.start.line,
      '$label: an argument name is text, and the file gives something else',
    );
  }
  return Arguments(values);
}

/// One argument value, or null when it is of a shape no step can hold.
Object? _argument(YamlNode node, String key, String label, _Refusals refusals) {
  if (node is YamlList) {
    // The only list an argument can hold is a list of text, so the element type is fixed here
    // rather than left as a list of whatever the file happened to write. A list built as
    // `List<Object>` would fail the registry's kind check with a message about a type nobody wrote.
    final List<String> texts = <String>[];
    bool whole = true;
    for (final YamlNode element in node.nodes) {
      if (element.value case final String text) {
        texts.add(text);
        continue;
      }
      refusals.add(
        element.span.start.line,
        '$label: the list "$key" holds text, and one entry is ${_kindOf(element)}',
      );
      whole = false;
    }
    return whole ? texts : null;
  }
  if (node is YamlMap) {
    refusals.add(node.span.start.line, '$label: "$key" is a map, and no argument holds a map');
    return null;
  }
  if (node.value case final Object value) {
    return value;
  }
  refusals.add(node.span.start.line, '$label: "$key" has no value');
  return null;
}

/// What [node] is, in the words a refusal uses.
String _kindOf(YamlNode node) {
  if (node is YamlList) {
    return 'a list';
  }
  if (node is YamlMap) {
    return 'a map';
  }
  return switch (node.value) {
    null => 'nothing',
    String _ => 'text',
    int _ => 'a whole number',
    double _ => 'a decimal number',
    bool _ => 'true or false',
    _ => 'something else',
  };
}

/// The source line of [node] counted from zero, or null when it is not a node at all.
int? _lineOf(Object? node) => node is YamlNode ? node.span.start.line : null;
