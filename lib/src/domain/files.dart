/// Reading and writing files is one of the three ways this framework reaches outside.
///
/// A step never touches the file system itself. It asks this, for the same reason it asks the
/// shell: a dry run can then refuse every write while still allowing every read, which is what a
/// step needs in order to compute the difference it would make.
abstract interface class Files {
  /// Whether [path] exists, as a file or as a directory.
  Future<bool> exists(String path);

  /// Reads [path] as text.
  ///
  /// Throws when it does not exist. A step that does not know whether it exists asks [exists]
  /// first — the answer is part of what it is checking.
  Future<String> read(String path);

  /// Writes [content] to [path], replacing whatever was there.
  ///
  /// [mode] is the POSIX permission bits the file ends up with. It is required rather than
  /// defaulted, because a file this framework writes is either something anyone may read or
  /// something only its owner may, and there is no sensible guess between the two.
  ///
  /// The write is verified by reading the file back. A write that reported success and changed
  /// nothing is the failure this exists to catch: it looks like success everywhere else.
  Future<void> write(String path, String content, {required int mode});

  /// Removes [path]. Does nothing when it is not there.
  Future<void> delete(String path);

  /// Creates [path] as a directory, including any parent that is missing.
  Future<void> createDirectory(String path, {required int mode});

  /// The names in directory [path], not recursively.
  Future<List<String>> list(String path);
}
