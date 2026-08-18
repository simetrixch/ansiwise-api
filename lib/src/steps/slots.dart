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

  /// A slot that takes a value from a previous state, and whose line is dropped where there is none.
  ///
  /// What it is for: a value that is written by a later act and is therefore ABSENT the first time
  /// the file is made. A pinned version is the shape of it — a fresh installation has nothing
  /// pinned, and a rewrite must hand back whatever was pinned since. Nothing else can state it,
  /// because the value is not the run's to supply: a step argument cannot name what the program does
  /// not hold, and a second template would be the same file twice.
  ///
  /// **Carrying is offered ONLY together with dropping, and the mark `!?` says both halves.** A
  /// carried value that is not there yet is the case carrying exists for, so a mark that carried
  /// without saying what to do about the first write would leave the author with nothing to write
  /// for the one state the file is guaranteed to pass through. Both halves in the mark, at the one
  /// place the value appears, is what makes an absent line a statement of the template's rather than
  /// a silence: the file is written, the step reports done, and the reader of the template can see
  /// why the line is not in it.
  carriedOptional,
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
  String get text => '<$name${_marks[kind]!}>';

  static const Map<SlotKind, String> _marks = <SlotKind, String>{
    SlotKind.required: '',
    SlotKind.optional: '?',
    SlotKind.carriedOptional: '!?',
  };
}

/// A slot: a lower-case name in angle brackets, marked `?` or `!?` or not at all, and nothing that
/// could be an expression.
///
/// **The name admits letters, digits and the hyphen, and NOT the underscore.** A slot name is read
/// by whoever writes a program row, so it reads as one word in one casing: `<upstream-servers>` and
/// never `<upstream_servers>`. Admitting both would make two spellings of one name, and a row that
/// picked the other one would go unfilled while looking correct.
///
/// **`!` on its own is not a mark, and `<name!>` therefore matches nothing here.** Carrying is
/// offered only together with dropping, for the reason [SlotKind.carriedOptional] gives, so the two
/// characters are one mark and not two. A template that writes `<name!>` is in the same position as
/// one that writes `<Stage>`: it named no slot, and what catches it is the caller's [leftoverSlotIn]
/// scan, which is broader than this pattern precisely so that a spelling the grammar does not accept
/// is still reported.
final RegExp slotPattern = RegExp(r'<([a-z][a-z0-9-]*)(!\?|\??)>');

/// The slots [text] carries, each named once, in the order they first appear.
List<Slot> slotsIn(String text) {
  final List<Slot> found = <Slot>[];
  final Set<String> seen = <String>{};
  for (final RegExpMatch match in slotPattern.allMatches(text)) {
    final String name = match.group(1)!;
    final String suffix = match.group(2)!;
    final SlotKind kind = switch (suffix) {
      '?' => SlotKind.optional,
      '!?' => SlotKind.carriedOptional,
      _ => SlotKind.required,
    };

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
///
/// Only the unmarked slots. `<name?>` and `<name!?>` decide whether their LINE is written at all,
/// which is a question about a file and not about a string, so `Template` answers it and this does
/// not.
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
