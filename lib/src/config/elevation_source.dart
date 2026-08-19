/// Where the password that raises a command to root comes from.
///
/// **Why this is a configuration question and not an answer.** A step may raise a command to root
/// without any answer of the program knowing that it does, and the configuration is read before a
/// program is resolved at all. So the run cannot be told "here is a password" by a program row; the
/// installation has to say, once and in one place, that root is reachable and by which route.
///
/// **Why there are two routes and not one.** A password standing in a file on the installed machine
/// is a credential that outlives every run that used it, and it is the last one of this platform
/// that still works that way — every other credential is handed to a run and gone when it ends. So
/// beside the file there is the route the caller supplies, where the password arrives with the
/// answers and lives no longer than the process. Which route an installation takes is its own
/// decision and is stated in its configuration; the engine only refuses to guess.
///
/// **Both together is a refusal, and so is neither.** Two routes named is two answers to one
/// question, and whichever the code picked would be the one somebody did not mean. A block that is
/// there and names nothing is somebody who meant to configure elevation and did not, which is worse
/// than the block being absent — absent is a complete configuration for an installation whose steps
/// never need root.
sealed class ElevationSource {
  const ElevationSource();
}

/// The password stands in a file on this machine, at [path].
///
/// Read at start-up rather than at the first elevated command, so an installation whose file is
/// missing learns it before a run has changed anything.
final class ElevationFromFile extends ElevationSource {
  /// Names the file at [path].
  const ElevationFromFile(this.path);

  /// Where the file stands, exactly as the configuration wrote it.
  final String path;

  @override
  bool operator ==(Object other) => other is ElevationFromFile && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'ElevationFromFile($path)';
}

/// The password is handed to the run by whoever started it, and nothing on this machine holds it.
///
/// It arrives on the same channel as the answers, which is the channel every other credential of a
/// run already travels on. What reads it is the composition root, because standard input is not a
/// file and there is no port to ask about it.
final class ElevationFromCaller extends ElevationSource {
  /// The route where nothing is stored.
  const ElevationFromCaller();

  @override
  bool operator ==(Object other) => other is ElevationFromCaller;

  @override
  int get hashCode => 0x1e7a;

  @override
  String toString() => 'ElevationFromCaller()';
}
