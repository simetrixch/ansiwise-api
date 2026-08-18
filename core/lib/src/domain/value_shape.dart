/// The shapes a text value may be declared to have, in ONE definition.
///
/// A shape is a name a program file writes — `shape: hostname` — and two different pieces of code
/// have to agree about it: the loader, which refuses a name nobody implements, and the check, which
/// decides whether a value has that shape. Written out in both places, those two drift the moment
/// one of them gains a shape, and the way that failure shows is the worst kind: the loader accepts
/// the declaration and the check silently passes every value.
///
/// So the set is here and neither of them holds a list of its own.
library;

/// One shape a text value may be declared to have.
enum ValueShape {
  /// A name resolvable in the domain name system: labels of letters, digits and hyphens, joined by
  /// dots, with at least two labels.
  ///
  /// A label may not begin or end with a hyphen, and the last label may not be all digits — without
  /// those two, `-.-` and `1.2` are hostnames, and a check that admits them reads as a guarantee it
  /// does not give.
  hostname(r'^(?!-)[a-z0-9-]+(?<!-)(\.(?!-)[a-z0-9-]+(?<!-))*\.(?!-)[a-z]([a-z0-9-]*[a-z0-9])?$'),

  /// An address mail can be delivered to: something, an at sign, and a hostname.
  ///
  /// The local part may not be empty and may hold no space, and the domain part is held to the same
  /// rule as [hostname] — a mailbox whose domain does not resolve is not a mailbox.
  mailbox(
    r'^[^@\s]+@(?!-)[a-z0-9-]+(?<!-)(\.(?!-)[a-z0-9-]+(?<!-))*\.(?!-)[a-z]([a-z0-9-]*[a-z0-9])?$',
  );

  /// Declares a shape and the expression a value of it matches.
  const ValueShape(this._pattern);

  final String _pattern;

  /// The name a program file writes for this shape.
  String get written => name;

  /// Whether [text] has this shape.
  ///
  /// Matched case-insensitively, because a hostname is case-insensitive by its own standard and an
  /// operator who typed one in capitals wrote a valid one.
  bool holds(String text) => RegExp(_pattern, caseSensitive: false).hasMatch(text);

  /// The shape [written] names, or null when nothing here is called that.
  ///
  /// Null and not a throw: the LOADER asks this in order to refuse a program file naming a shape
  /// that does not exist, and that refusal reads better than a stack trace. Everything downstream
  /// has a [ValueShape] rather than a name, so the question cannot be asked again later.
  static ValueShape? named(String written) {
    for (final ValueShape shape in values) {
      if (shape.written == written) {
        return shape;
      }
    }
    return null;
  }

  /// Every shape's name, for a refusal that has to list them.
  static List<String> get allWritten => <String>[
    for (final ValueShape shape in values) shape.written,
  ];
}
