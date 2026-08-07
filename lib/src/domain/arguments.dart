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

  /// Whether a value stands in for it when a program does not give it.
  bool get hasDefault => defaultValue != null;

  /// Whether [value] is of the kind this argument holds.
  bool accepts(Object value) => switch (kind) {
    ArgumentKind.text => value is String,
    ArgumentKind.integer => value is int,
    ArgumentKind.flag => value is bool,
    ArgumentKind.textList => value is List<String>,
  };
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
