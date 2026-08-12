import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import '../domain/files.dart';
import '../model/failures.dart';
import '../model/run_event.dart';

/// What the installation's own configuration says, read from one file beside the programs.
///
/// **Handing the binary this file is enough.** Everything a run needs that is not a program, an
/// answer or a command-line decision stands here, so an operator points at one path and is done.
/// The same file is what the REST surface reads, because a service that had to be told separately
/// is a second place to keep in step.
///
/// The file is data and nothing else — names and values, no conditions, no expressions, no
/// templating. The moment a configuration file can compute, the thing being debugged stops being the
/// program and starts being the configuration language.
///
/// ```yaml
/// # ansiwise.yaml
/// log_level: info
/// gate:
///   dry: false
/// plugins:
///   - example-plugin
/// ```
@immutable
final class Configuration {
  /// Creates the configuration from what the file says.
  const Configuration({
    required this.plugins,
    this.logLevel = LogLevel.info,
    this.requireDryRun = true,
    this.allowUnwind = true,
  });

  /// The name the file is looked for under, beside the programs.
  static const String defaultFileName = 'ansiwise.yaml';

  /// The plugins this installation turns on, in the order the file lists them.
  final List<String> plugins;

  /// The quietest level this installation writes.
  ///
  /// `info` unless the file says otherwise, which is the level an operator reads. A run somebody is
  /// debugging asks for `debug` and gets what it needs by having asked; nothing is dropped from the
  /// record because a step decided months ago that it was not worth saying.
  final LogLevel logLevel;

  /// Whether a real run still needs a clean dry run of the same input behind it.
  ///
  /// True unless `gate: dry: false` says otherwise, so an installation that never thought about it
  /// has the gate. Turning it off does not make a run claim more: it is recorded as having waived
  /// the proof, and the closing line still counts its rows apart from the measured ones.
  ///
  /// **The installation this platform was built for runs with the gate on.** Somebody else running
  /// it may decide differently; the run that is supposed to demonstrate the chain works waives
  /// nothing.
  final bool requireDryRun;

  /// Whether the engine should roll back steps when a failure happens.
  ///
  /// True unless `no_unwind: true` is given, in which case the framework stops on failure
  /// leaving the machine exactly as it was, preserving evidence for debugging.
  final bool allowUnwind;

  /// Reads [path] through [files].
  ///
  /// Throws [PluginRejected] when the file is not a mapping, when `plugins:` is absent or is not a
  /// list, when an entry is not a plain string, or when `log_level:` is not one of the four. Every
  /// one of those is named rather than coerced: a configuration that is quietly interpreted is a
  /// configuration nobody can predict.
  static Future<Configuration> load({required Files files, required String path}) async {
    final String text = await files.read(path);

    final Object? document;
    try {
      document = loadYaml(text);
    } on YamlException catch (broken) {
      throw PluginRejected('$path is not YAML: ${broken.message}');
    }

    if (document is! YamlMap) {
      throw PluginRejected('$path has to be a mapping with a "plugins:" list');
    }

    final Object? named = document['plugins'];
    if (named == null) {
      throw PluginRejected(
        '$path names no plugins\n'
        'add a "plugins:" list, or no step exists and every program is refused',
      );
    }
    if (named is! YamlList) {
      throw PluginRejected('$path: "plugins" has to be a list of names');
    }

    final List<String> names = <String>[];
    for (final Object? entry in named) {
      if (entry is! String) {
        throw PluginRejected('$path: "$entry" is not a plugin name');
      }
      names.add(entry);
    }

    return Configuration(
      plugins: names,
      logLevel: _logLevel(document, path),
      requireDryRun: _requireDryRun(document, path),
      allowUnwind: _allowUnwind(document, path),
    );
  }

  /// The level [document] names, or `info` when it names none.
  ///
  /// A value that is not one of the four is refused with all four in the refusal, so somebody who
  /// wrote `warning` learns the word rather than that something was wrong.
  static LogLevel _logLevel(YamlMap document, String path) {
    final Object? written = document['log_level'];
    if (written == null) {
      return LogLevel.info;
    }
    for (final LogLevel level in LogLevel.values) {
      if (level.name == written) {
        return level;
      }
    }
    throw PluginRejected(
      '$path: "log_level" is "$written", and it is one of '
      '${LogLevel.values.map((LogLevel each) => each.name).join(', ')}',
    );
  }

  /// Whether `gate: dry:` leaves the gate standing, which is what a file saying nothing means.
  ///
  /// Only `false` turns it off, and it has to be written. A key that is absent, and a `gate:` block
  /// that names something else, both leave the gate where it is — so the one way to end up without
  /// it is to have typed the word.
  static bool _requireDryRun(YamlMap document, String path) {
    final Object? gate = document['gate'];
    if (gate == null) {
      return true;
    }
    if (gate is! YamlMap) {
      throw PluginRejected('$path: "gate" has to be a mapping, with "dry:" under it');
    }
    final Object? dry = gate['dry'];
    if (dry == null) {
      return true;
    }
    if (dry is! bool) {
      throw PluginRejected(
        '$path: "gate.dry" is "$dry", and it is true or false\n'
        'false means a real run no longer needs a clean dry run of the same input behind it',
      );
    }
    return dry;
  }

  /// Whether `no_unwind:` disables the rollback of steps after a failure.
  static bool _allowUnwind(YamlMap document, String path) {
    final Object? val = document['no_unwind'];
    if (val == null) {
      return true;
    }
    if (val is! bool) {
      throw PluginRejected(
        '$path: "no_unwind" is "$val", and it must be true or false\n'
        'true means the engine will leave the machine exactly as it was when a failure happened',
      );
    }
    return !val;
  }
}
