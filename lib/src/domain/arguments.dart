import 'package:meta/meta.dart';

/// What kind of value an argument holds.
enum ArgumentKind {
  /// Text.
  text,

  /// A whole number.
  integer,

  /// True or false.
  flag,

  /// A list of text values.
  textList,

  /// The name of an answer.
  answerName,

  /// A mapping of a name to a small declaration under it.
  ///
  /// For the case a list cannot carry: a row that has to say WHICH of several things each of
  /// several names is filled from. A key on the left, a mapping of named slots on the right, and
  /// nothing that evaluates — no expression, no condition, no reference to another key. The step
  /// that declares one says in its own words which slots it reads and refuses anything else, the
  /// way it refuses an argument it does not declare.
  mapping,
}

/// The condition that determines whether an answer must be provided.
///
/// An answer with a condition is requested only when the [answer] holds the expected value.
/// If the condition does not hold, the answer must not be provided, and if given, it is refused.
@immutable
final class StatedWhen {
  /// Declares a trigger condition for an answer.
  ///
  /// Exactly one of [equals] or [equalsAnswer] must be non-null.
  const StatedWhen({required this.answer, this.equals, this.equalsAnswer})
    : assert((equals == null) != (equalsAnswer == null));

  /// The name of the other answer this one depends on.
  final String answer;

  /// The exact text value the other answer must hold.
  final String? equals;

  /// The name of a third answer whose value the other answer must match.
  final String? equalsAnswer;
}

/// One argument a step accepts, declared by the step and checked before anything runs.
///
/// This is where the safety a compiler cannot give across a configuration boundary is restored. A
/// program file names a step and hands it values; nothing about that is type-checked at build time.
/// It is checked instead at the first gate, against these declarations, and a program that gives a
/// step an argument it does not have is refused before the first mutation.
@immutable
final class ArgumentSpec {
  /// Declares one argument.
  const ArgumentSpec({
    required this.name,
    required this.kind,
    required this.describes,
    this.required = true,
    this.secret = false,
    this.defaultValue,
    this.allowed = const <String>[],
    this.shape,
    this.denied = const <String>[],
    this.statedWhen,
  });

  /// The key a program file writes.
  final String name;

  /// What kind of value it holds.
  final ArgumentKind kind;

  /// What it is for, shown to whoever is filling it in.
  final String describes;

  /// Whether a program must give it.
  final bool required;

  /// Whether the value is a credential or a key.
  ///
  /// Two things follow from it and neither is optional. The client shows a field that does not echo
  /// what is typed, and the value is never sent back out — a description of a program tells a reader
  /// that a secret is set, never what it is.
  final bool secret;

  /// What it is when a program does not give it.
  final Object? defaultValue;

  /// The only values this may hold, or empty where any value of its kind will do.
  ///
  /// Most values are carried rather than decided: a domain, a mailbox, a credential. A few are
  /// DECIDED on — a role is one of two words, a stage one of three — and for those the kind is not
  /// the whole of what is legal. Saying so here rather than inside the step that reads it buys three
  /// things at once:
  ///
  /// - a value outside the set is refused BEFORE the run starts, with the set in the message, rather
  ///   than blocking a step somewhere in the middle of an installation
  /// - the client renders a CHOICE instead of a free-text box, which is the whole promise of building
  ///   the form from the declaration and is least keepable exactly where a typo is most likely
  /// - a check probing every step reads the legal values the way it already reads the kinds, instead
  ///   of carrying a hand-written list of its own that has to agree with the steps
  ///
  /// Only text has such a set: a flag already has two values, and a number or a list of text has no
  /// small closed one worth writing out.
  final List<String> allowed;

  /// A specific shape a text value must have, such as a hostname or a mailbox.
  final String? shape;

  /// Values this argument must never hold, even if they are of the right kind.
  final List<String> denied;

  /// The condition that dictates whether this answer should be asked at all.
  final StatedWhen? statedWhen;

  /// Whether a value stands in for it when a program does not give it.
  bool get hasDefault => defaultValue != null;

  /// Whether [value] is of the kind this argument holds.
  ///
  /// The kind ONLY. Whether it is one of the values this argument may hold is [permits], asked
  /// separately so a wrong kind and a wrong value produce different sentences: "this holds text and
  /// was given an int" and "this holds one of master, slave" are different mistakes, and telling an
  /// operator the first when they made the second sends them looking in the wrong place.
  bool accepts(Object value) => switch (kind) {
    ArgumentKind.text => value is String,
    ArgumentKind.answerName => value is String,
    ArgumentKind.integer => value is int,
    ArgumentKind.flag => value is bool,
    ArgumentKind.textList => value is List<String>,
    ArgumentKind.mapping => value is Map<String, Object?>,
  };

  /// Whether [value] is one of the values this argument may hold.
  ///
  /// True where none are declared: an argument with no closed set permits anything of its kind.
  /// Refuses a value if it is on the denied list.
  bool permits(Object value) {
    if (value is String && denied.contains(value)) {
      return false;
    }
    return allowed.isEmpty || (value is String && allowed.contains(value));
  }
}

/// The values a program gave one step.
///
/// Already validated against the step's declared [ArgumentSpec] list by the time a step sees it, so
/// the accessors here fail loudly on a name the step never declared rather than returning null and
/// letting the mistake travel.
@immutable
final class Arguments {
  /// Holds the validated values for one step.
  const Arguments(this._values);

  /// No arguments.
  static const Arguments none = Arguments(<String, Object>{});

  final Map<String, Object> _values;

  /// Whether [name] was given.
  bool has(String name) => _values.containsKey(name);

  /// The keys a program gave, so the resolver can report one that no step declares.
  Iterable<String> get names => _values.keys;

  /// The raw value of [name], for the resolver to check against a declaration.
  Object? raw(String name) => _values[name];

  /// A copy of these values with [defaults] filled in wherever a key is missing.
  Arguments withDefaults(Map<String, Object> defaults) =>
      Arguments(<String, Object>{...defaults, ..._values});

  /// The text value of [name].
  String text(String name) => _read<String>(name);

  /// The whole number value of [name].
  int integer(String name) => _read<int>(name);

  /// The true-or-false value of [name].
  bool flag(String name) => _read<bool>(name);

  /// The list of text values of [name].
  List<String> textList(String name) => _read<List<String>>(name);

  /// The text value of [name], or null when it was not given.
  String? optionalText(String name) => _values[name] as String?;

  T _read<T>(String name) {
    final Object? value = _values[name];
    if (value == null) {
      throw ArgumentError.value(
        name,
        'name',
        'the step read an argument it did not declare, or the loader let a required one through',
      );
    }
    if (value case final T typed) {
      return typed;
    }
    throw ArgumentError.value(
      name,
      'name',
      'declared as $T but the program gave ${value.runtimeType}',
    );
  }
}
