/// The one notation for a value that cannot be written down where it is needed: a marked slot.
///
/// A slot is a NAME in angle brackets — `<stage>`, `<version>`, `<master-domain>` — standing where
/// exactly one value belongs. No expression, no condition and no loop, so what a reader has in
/// front of them is the text that will be used, never a language for producing it. Every filling
/// anywhere goes through here — a program row's argument, a pinned release url, a template beside
/// the programs — which is what makes it ONE notation with one grammar for every plugin at once,
/// instead of each package teaching the reader its own.
///
/// **What still looks like a slot after filling is for the caller to refuse, and [leftoverSlotIn]
/// is deliberately broader than [slotPattern].** A misspelled or mis-cased name — `<Stage>`,
/// `<verison>` — matches no declared slot, so a scan that only knew the grammar would wave it
/// through to the tool the text is bound for, where it is taken as content. The scan therefore
/// reports ANYTHING between angle brackets. The one text that must not be scanned this way is
/// another tool's arbitrary content, where angle brackets can be legitimate — such a caller fills
/// its declared slot and judges nothing else.
library;

/// The types of slots a template may declare.
enum SlotKind {
  /// A slot that must hold a value from the program.
  required,

  /// A slot that may hold a value, and whose line is dropped if not.
  optional,

  /// A slot that takes a value from a previous state, never from the program.
  carried,
}

/// A parsed slot with its name and kind.
class Slot {
  /// The name of the slot.
  final String name;

  /// The kind of the slot, derived from its suffix.
  final SlotKind kind;

  /// Creates a slot.
  const Slot(this.name, this.kind);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Slot && runtimeType == other.runtimeType && name == other.name && kind == other.kind;

  @override
  int get hashCode => name.hashCode ^ kind.hashCode;

  /// The raw text representation of this slot, e.g. `<name?>`.
  String get text =>
      '<$name${kind == SlotKind.optional
          ? '?'
          : kind == SlotKind.carried
          ? '!'
          : ''}>';
}

/// A slot: a lower-case name in angle brackets, possibly suffixed with ? or !, and nothing that could be an expression.
final RegExp slotPattern = RegExp(r'<([a-z][a-z0-9_-]*)([?!]?)>');

/// The slots [text] carries, each named once, in the order they first appear.
List<Slot> slotsIn(String text) {
  final List<Slot> found = <Slot>[];
  final Set<String> seen = <String>{};
  for (final RegExpMatch match in slotPattern.allMatches(text)) {
    final String name = match.group(1)!;
    final String suffix = match.group(2)!;
    final SlotKind kind = suffix == '?'
        ? SlotKind.optional
        : suffix == '!'
        ? SlotKind.carried
        : SlotKind.required;

    // For slots with the same name but different suffixes (unlikely but possible), we just add them
    final String key = '$name$suffix';
    if (!seen.contains(key)) {
      seen.add(key);
      found.add(Slot(name, kind));
    }
  }
  return found;
}

/// [text] with the slot named by each entry of [values] holding that entry's value.
/// This only replaces regular required slots. ? and ! slots need line-dropping logic and are handled in Template.
///
/// A name with no slot in [text] is left for the caller to judge: an argument is free to use any
/// part of what a run holds, while a template refuses a value with nowhere to go — that law
/// belongs to the caller, not to the notation.
String filledSlots(String text, Map<String, String> values) {
  String written = text;
  for (final MapEntry<String, String> value in values.entries) {
    written = written.replaceAll('<${value.key}>', value.value);
  }
  return written;
}

/// The first thing in [text] that still looks like a slot, or null when nothing does.
String? leftoverSlotIn(String text) => _anySlot.firstMatch(text)?.group(0);

/// Any `<...>` at all, for the refusal that catches a name nothing filled — including one the
/// grammar would not accept, which is exactly what a misspelling looks like.
final RegExp _anySlot = RegExp('<[^<>]*>');
