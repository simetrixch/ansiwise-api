/// Reading and writing files is one of the three ways this framework reaches outside.
///
/// A step never touches the file system itself. It asks this, for the same reason it asks the
/// shell: a dry run can then refuse every write while still allowing every read, which is what a
/// step needs in order to compute the difference it would make.
///
/// **`elevated` is on every method, for the same reason it is on a command.** Half of what a
/// deployment writes lives where only root may write, and half of what it reads lives where only
/// root may read — the argument file of a service, a drop-in beside a network or a daemon
/// configuration. Without it a step reaching for one of those has two ways out, and both are worse:
/// run the whole program as root, which makes every other boundary meaningless, or reach for the
/// shell with `cat` and `tee`, which takes file work out of the port that exists to record it and
/// to refuse it under a dry run.
///
/// **Elevated does not mean mutating.** Reading something only root may read is still a read, and a
/// dry run performs it. What a dry run refuses is a WRITE, elevated or not.
abstract interface class Files {
  /// Whether [path] exists, as a file or as a directory.
  Future<bool> exists(String path, {bool elevated = false});

  /// Reads [path] as text.
  ///
  /// Throws when it does not exist. A step that does not know whether it exists asks [exists]
  /// first — the answer is part of what it is checking.
  Future<String> read(String path, {bool elevated = false});

  /// Writes [content] to [path], replacing whatever was there.
  ///
  /// [mode] is the POSIX permission bits the file ends up with. It is required rather than
  /// defaulted, because a file this framework writes is either something anyone may read or
  /// something only its owner may, and there is no sensible guess between the two.
  ///
  /// The write is verified by reading the file back. A write that reported success and changed
  /// nothing is the failure this exists to catch: it looks like success everywhere else.
  Future<void> write(String path, String content, {required int mode, bool elevated = false});

  /// Removes [path]. Does nothing when it is not there.
  Future<void> delete(String path, {bool elevated = false});

  /// Creates [path] as a directory, including any parent that is missing.
  Future<void> createDirectory(String path, {required int mode, bool elevated = false});

  /// The names in directory [path], not recursively.
  Future<List<String>> list(String path, {bool elevated = false});
}
