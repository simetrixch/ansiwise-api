/// Unpredictability, asked for rather than reached for.
///
/// A step that mints a credential calls this. Injecting it is what makes a mint testable at all: a
/// step reaching for a random generator itself produces a different value on every run, so a test
/// can assert nothing about what was written — and a test that settles for "something was written"
/// passes when the step writes an empty string.
///
/// The same argument as the clock port, one step further. Time is injected so a five-minute
/// deadline can be waited out in no time; randomness is injected so a generated password can be
/// asserted at all.
abstract interface class Entropy {
  /// [bytes] unpredictable bytes, written as lower-case hexadecimal.
  ///
  /// Twice as many characters as bytes, out of `0-9a-f` and nothing else. That alphabet is the point
  /// rather than a detail: a minted value ends up inside a connection string, an environment
  /// variable and an SQL statement, and hexadecimal needs escaping in none of them. A password
  /// carrying a quote or a backslash breaks at the third place it is pasted and not at the first.
  ///
  /// Throws [ArgumentError] when [bytes] is not positive.
  String hex(int bytes);
}
