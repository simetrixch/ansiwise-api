/// What a caller supplies for one run, and the one place that shape is written down.
///
/// **WHY THIS IS IN THE FRAMEWORK AND NOT IN A DOOR.** A run can be told in two ways — a command
/// line reading standard input, and `POST /runs` over the API — and both take the same thing: the
/// answers, and the password that raises a command to root where the installation says the caller
/// hands it over. Each door used to describe that shape itself, and three defects in one day came
/// out of exactly that:
///
///   * the launcher wrote the bare answers while the run had begun demanding the envelope, so every
///     run started over the API died before writing its header,
///   * the API had no route for the password at all, so no program with an elevated row could be
///     run through it,
///   * the API refused every list answer, because only the other door fixed the element type a JSON
///     decoder leaves as `List<dynamic>`.
///
/// None of the three was a hard problem. Each was one door learning something the other already
/// knew. So the shape lives here, once, and a door parses nothing of its own.
library;

/// What one run was told.
final class CallerInputs {
  /// Holds [answers], and [elevationPassword] where the caller supplied one.
  const CallerInputs({required this.answers, this.elevationPassword});

  /// A run that was told nothing.
  const CallerInputs.none() : answers = const <String, Object?>{}, elevationPassword = null;

  /// Reads the envelope out of [parsed], refusing anything that is not one.
  ///
  /// [where] is what a refusal calls the place this came from — a file's name, or `standard input`,
  /// or the request — because a caller told "that is not an envelope" and not told which envelope
  /// has to go looking.
  ///
  /// **The element type of a list is fixed here.** A JSON decoder answers an array as
  /// `List<dynamic>`, and an answer that holds a list holds a list of TEXT; leaving that to the kind
  /// check produces a refusal about a type nobody wrote.
  ///
  /// Throws [InputsRejected] naming what is wrong, which a door turns into its own kind of refusal.
  factory CallerInputs.of(Object? parsed, {required String where}) {
    if (parsed is! Map<String, Object?>) {
      throw InputsRejected(
        '$where holds ${parsed.runtimeType}, and a run is told by a JSON object',
      );
    }
    // AN EMPTY ENVELOPE IS AN ENVELOPE: a program that declares nothing is told nothing, and a
    // caller saying so did not get the shape wrong.
    //
    // WHAT IS NOT JUDGED HERE is whatever else the object carries. This reads the envelope out of
    // something that may be larger than it — `POST /runs` puts the program and the mode beside it —
    // so a door whose payload is WHOLLY the envelope is the one that can say a stray key is the
    // older bare shape, and it says so itself.
    final Object supplied = parsed[answersField] ?? const <String, Object?>{};
    if (supplied is! Map<String, Object?>) {
      throw InputsRejected(
        '$where: "$answersField" holds ${supplied.runtimeType}, and answers are an object',
      );
    }
    final Object? password = parsed[elevationPasswordField];
    if (password != null && (password is! String || password.isEmpty)) {
      throw InputsRejected('$where: "$elevationPasswordField" holds nothing usable');
    }
    return CallerInputs(
      answers: <String, Object?>{
        for (final MapEntry<String, Object?> answer in supplied.entries)
          answer.key: switch (answer.value) {
            final List<Object?> texts => <String>[for (final Object? each in texts) '$each'],
            final Object? value => value,
          },
      },
      elevationPassword: password as String?,
    );
  }

  /// The key the answers stand under.
  static const String answersField = 'answers';

  /// The key the password stands under, on the wire and as the answer a program may declare.
  static const String elevationPasswordField = 'elevation_password';

  /// What the program declares it must be told.
  final Map<String, Object?> answers;

  /// The password that raises a command to root, or null where the caller supplied none.
  final String? elevationPassword;

  /// The envelope, as a caller writes it.
  ///
  /// Written by whoever starts a run in a process of its own, and read back by [CallerInputs.of] at
  /// the other end. One method and one factory rather than two hand-built maps, because the two used
  /// to be built in different packages and drifted apart the first time one of them changed.
  Map<String, Object?> toJson() => <String, Object?>{
    answersField: answers,
    if (elevationPassword case final String password) elevationPasswordField: password,
  };
}

/// What a caller sent that is not an envelope.
final class InputsRejected implements Exception {
  /// Refuses [message].
  const InputsRejected(this.message);

  /// What is wrong, in the words whoever sent it reads.
  final String message;

  @override
  String toString() => message;
}
