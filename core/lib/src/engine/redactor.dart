/// Removes secret values from everything on its way into the record.
///
/// The record is written to a file an operator reads without elevated rights, and it is exported
/// and pasted into messages when something has gone wrong. That is only safe if a secret cannot be
/// in it, and the only way to be sure of that is to have one place it must pass through.
///
/// This is that place. Every port reports through the recorder, and the recorder redacts. No step
/// can write to the record another way, so no step can forget.
final class Redactor {
  /// Creates a redactor that hides [secrets].
  ///
  /// Values shorter than [minimumLength] are ignored. A short secret would match ordinary text
  /// everywhere and turn the record into a page of markers, which is a worse outcome than the risk
  /// it removes — and a secret that short is a defect to fix rather than to hide.
  Redactor(Iterable<String> secrets, {this.minimumLength = 8})
    : _secrets = secrets.where((String s) => s.length >= minimumLength).toList(growable: false)
        ..sort((String a, String b) => b.length.compareTo(a.length));

  /// A redactor that hides nothing, for a run that holds no secrets.
  static final Redactor none = Redactor(const <String>[]);

  /// What replaces a secret. Fixed text rather than a variable number of stars, so that the length
  /// of the value is not readable from the record either.
  static const String marker = '[redacted]';

  /// The shortest value that is worth hiding.
  final int minimumLength;

  /// Longest first, so that a secret containing another secret is replaced whole rather than being
  /// broken into a marker and a leftover fragment.
  final List<String> _secrets;

  /// Whether anything is being hidden.
  bool get isEmpty => _secrets.isEmpty;

  /// Returns [text] with every known secret replaced by [marker].
  ///
  /// Replaces the value wherever it appears rather than dropping the line that carries it. A
  /// dropped line takes its context with it, and the context is what an operator needs when a
  /// command failed while handling a credential.
  String hide(String text) {
    if (_secrets.isEmpty || text.isEmpty) {
      return text;
    }
    String result = text;
    for (final String secret in _secrets) {
      if (result.contains(secret)) {
        result = result.replaceAll(secret, marker);
      }
    }
    return result;
  }

  /// Returns [values] with every known secret replaced by [marker].
  List<String> hideAll(Iterable<String> values) => values.map(hide).toList(growable: false);

  /// Returns [headers] with every value redacted whose name names a credential.
  ///
  /// Names and not values, because a credential that arrives in a header is often assembled at the
  /// call site and was never registered as a secret. The rule is deliberately blunt: anything
  /// called authorization, cookie, or ending in key, secret or password.
  Map<String, String> hideHeaders(Map<String, String> headers) => <String, String>{
    for (final MapEntry<String, String> e in headers.entries)
      e.key: _isCredentialHeader(e.key) ? marker : hide(e.value),
  };

  static bool _isCredentialHeader(String name) {
    final String n = name.toLowerCase();
    return n == 'authorization' ||
        n == 'cookie' ||
        n == 'set-cookie' ||
        n == 'proxy-authorization' ||
        n.endsWith('-key') ||
        n.endsWith('-secret') ||
        n.endsWith('-password') ||
        n.endsWith('-credential');
  }
}
