/// The path arithmetic the gate does for itself.
///
/// `package:path` would answer all of this, and nothing under tool/ may import it. The gate's own
/// program is started inside the container before anything has been resolved — it is what copies
/// the tree in — and the package config it would find beside itself there is the host's, holding
/// absolute paths into a Windows filesystem. So tool/ imports nothing but `dart:`, and the two
/// things it needs from a path library are here.
library;

import 'dart:io';

/// The last segment of [path], whichever separator this operating system wrote it with.
String baseName(String path) {
  final int cut = path.lastIndexOf(_separator);
  return cut < 0 ? path : path.substring(cut + 1);
}

/// The package a program under `tool/` is part of.
///
/// Taken from where the program's own file sits rather than from the working directory, so `dart
/// run tool/ci.dart` answers the same from anywhere in the tree. [script] is `Platform.script`; it
/// is a parameter rather than read here so that what this resolves to can be asserted.
Directory packageOfToolScript(Uri script) => File.fromUri(script).parent.parent.absolute;

final RegExp _separator = RegExp(r'[/\\]');
