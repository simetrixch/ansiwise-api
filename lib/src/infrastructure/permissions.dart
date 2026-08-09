import 'dart:io';

/// Sets the POSIX permission bits of [path] to [mode].
///
/// `dart:io` has no permission setter of any kind, so this runs `chmod`, which is the program that
/// owns those bits on the platforms that have them. [mode] is written the way `chmod` expects it:
/// the value is an octal number, so 0644 is the decimal 420.
///
/// On Windows nothing is run and nothing changes. There are no POSIX bits there — a file is
/// protected by the access control list it inherits from its directory — so a run on Windows gets
/// whatever that inheritance gives it, and a caller that needs a file to be unreadable by others
/// cannot get that from this call.
Future<void> setPermissions(String path, int mode) async {
  if (Platform.isWindows) {
    return;
  }
  final ProcessResult result = await Process.run('chmod', <String>[
    mode.toRadixString(8).padLeft(3, '0'),
    path,
  ]);
  if (result.exitCode != 0) {
    throw FileSystemException('chmod returned ${result.exitCode}', path);
  }
}
