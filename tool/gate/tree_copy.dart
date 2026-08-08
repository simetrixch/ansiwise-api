/// Getting the tree into the container.
///
/// The tree is COPIED rather than worked on where it is mounted. A bind mount of a Windows
/// directory into Linux Docker is slow enough to change results and not just timing, and a gate
/// that invents red findings is worse than a slow one. The mount the copy reads from is read-only
/// and is never the working copy, so nothing a check does can reach the developer's files.
///
/// `.dart_tool` is left behind deliberately. It holds absolute paths into the HOST filesystem — the
/// package_config.json written by `dart pub get` on Windows points at `C:\…` — so a copy of it
/// makes the analyzer resolve packages that are not in the container. `pub get` rebuilds it there
/// against the pub cache volume.
library;

import 'dart:io';

import 'paths.dart';

/// Directory names that never travel into the container.
const Set<String> notCopied = <String>{'.dart_tool'};

/// Copies everything under [source] into [target], leaving [excluded] directory names behind.
///
/// [target] is created if it is not there. Files that are already there are overwritten, so a
/// second copy inside one container answers the same as the first.
void copyTree(Directory source, Directory target, {Set<String> excluded = notCopied}) {
  target.createSync(recursive: true);
  for (final FileSystemEntity entry in source.listSync(followLinks: false)) {
    final String name = baseName(entry.path);
    if (excluded.contains(name)) {
      continue;
    }
    final String destination = '${target.path}/$name';
    if (entry is Directory) {
      copyTree(entry, Directory(destination), excluded: excluded);
    } else if (entry is File) {
      entry.copySync(destination);
    }
  }
}
