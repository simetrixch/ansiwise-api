/// The file this package declares its version in, as something the release program is handed.
///
/// The same split tool/release_git.dart makes: what the release program DECIDES is one thing and
/// writing a file on this operating system is another. It is what lets the deciding half be driven
/// by a check — including the half that bumps — on a machine where no pubspec.yaml is edited, and
/// what was written is then readable as a value.
///
/// ONE PACKAGE IS ONE MANIFEST HERE. This repository holds a single Dart package, ansiwise_core, and
/// the pubspec.yaml at its root is the only one in the tree — so a walker that bumped every package
/// of a workspace in lockstep would be a mechanism with nothing to walk.
///
/// WHAT THE BUMPED NUMBER IS FOR, in a package that is compiled into nothing. Nobody resolves this
/// package by its version: every consumer names it as a git dependency and resolves the `ref`. What
/// the declared version does is answer what this tree says it is, which is where the first release
/// is proposed from — tool/release_versions.dart's declaredVersionIn — and a tag naming a version
/// the manifest does not declare would be two answers to one question.
library;

import 'dart:io';

/// A file declaring the version of this package.
abstract interface class Manifest {
  /// Where it is, as a refusal names it.
  String get path;

  /// What it holds, or null when there is no such file.
  String? get text;

  /// Replaces what it holds with [text].
  void write(String text);
}

/// pubspec.yaml, as a file of the machine the release program is running on.
final class PubspecFile implements Manifest {
  /// The pubspec.yaml at [path].
  const PubspecFile(this.path);

  @override
  final String path;

  @override
  String? get text {
    final File file = File(path);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  void write(String text) => File(path).writeAsStringSync(text);
}
