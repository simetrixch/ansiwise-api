import 'dart:math';

import '../domain/entropy.dart';

/// The operating system's own cryptographic randomness.
///
/// `Random.secure()` and not `Random()`: the second is a pseudo-random generator seeded from
/// something an attacker can often guess, and it is the default a caller reaches for without
/// thinking. What this mints is a credential, so the distinction is the whole of the class.
///
/// The generator is created once and held. Asking for a fresh one per call would be slower and no
/// stronger — `Random.secure()` reads the platform's entropy source on every draw either way.
final class RealEntropy implements Entropy {
  /// Creates the source a real run is given.
  RealEntropy();

  final Random _random = Random.secure();

  @override
  String hex(int bytes) {
    if (bytes < 1) {
      throw ArgumentError.value(bytes, 'bytes', 'a secret is at least one byte long');
    }
    final StringBuffer written = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      // Padded, because a byte below sixteen writes one digit and would silently shorten the value.
      written.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return written.toString();
  }
}
