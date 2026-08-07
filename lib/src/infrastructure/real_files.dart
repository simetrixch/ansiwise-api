import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/files.dart';
import 'permissions.dart';

/// The file system of the machine the run is on.
///
/// The one method with anything in it is [write], which reads the file back and compares. Everything
/// else is a call through.
final class RealFiles implements Files {
  /// Creates the file system a real run is given.
  const RealFiles();

  @override
  Future<bool> exists(String path) async =>
      await File(path).exists() || await Directory(path).exists();

  @override
  Future<String> read(String path) => File(path).readAsString();

  @override
  Future<void> write(String path, String content, {required int mode}) async {
    final File file = File(path);
    if (!await file.exists()) {
      // Created empty and given its bits before it holds anything. Writing first and setting the
      // bits afterwards leaves a file that is meant to be private readable by everyone for the
      // moment in between, and that moment is exactly when the secret is in it.
      await file.create();
    }
    await setPermissions(path, mode);
    await file.writeAsString(content, flush: true);

    // The write is verified by reading the file back. A write that reported success and changed
    // nothing looks like success at every other layer: the call returns, the step's postcondition is
    // asked about the machine and finds the old content, and the failure is reported as the step
    // being wrong rather than as the file not having been written.
    final String written = await file.readAsString();
    if (written != content) {
      throw FileSystemException('the file does not hold what was just written to it', path);
    }
  }

  @override
  Future<void> delete(String path) async {
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
      return;
    }
    final Directory directory = Directory(path);
    if (await directory.exists()) {
      // A directory goes with what is in it. The caller asked for the path to be gone, and a
      // non-recursive delete would refuse every directory that is not already empty.
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> createDirectory(String path, {required int mode}) async {
    await Directory(path).create(recursive: true);
    await setPermissions(path, mode);
  }

  @override
  Future<List<String>> list(String path) async {
    final List<String> names = <String>[
      await for (final FileSystemEntity entry in Directory(path).list(followLinks: false))
        p.basename(entry.path),
    ];
    // Sorted, because the order the file system hands entries back in is not stable. A step that
    // compares one listing against another would otherwise see a change that is not there.
    names.sort();
    return names;
  }
}
