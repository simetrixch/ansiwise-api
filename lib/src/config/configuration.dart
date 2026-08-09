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
/// plugins:
///   - example-plugin
/// ```
@immutable
final class Configuration {
  /// Creates the configuration from what the file says.
  const Configuration({required this.plugins, this.logLevel = LogLevel.info});

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

    return Configuration(plugins: names, logLevel: _logLevel(document, path));
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
}
