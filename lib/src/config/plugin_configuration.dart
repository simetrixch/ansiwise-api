import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import '../domain/files.dart';
import '../model/failures.dart';

/// What the installation's own configuration says, read from one file beside the programs.
///
/// The file is data and nothing else — a list of names, no conditions, no expressions, no
/// templating. The moment a configuration file can compute, the thing being debugged stops being the
/// program and starts being the configuration language.
///
/// ```yaml
/// # ansiwise.yaml
/// plugins:
///   - example-plugin
/// ```
@immutable
final class PluginConfiguration {
  /// Creates the configuration from the names it activates.
  const PluginConfiguration({required this.plugins});

  /// The name the file is looked for under, beside the programs.
  static const String defaultFileName = 'ansiwise.yaml';

  /// The plugins this installation turns on, in the order the file lists them.
  final List<String> plugins;

  /// Reads [path] through [files].
  ///
  /// Throws [PluginRejected] when the file is not a mapping, when `plugins:` is absent or is not a
  /// list, or when an entry is not a plain string. Every one of those is named rather than coerced:
  /// a configuration that is quietly interpreted is a configuration nobody can predict.
  static Future<PluginConfiguration> load({required Files files, required String path}) async {
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

    return PluginConfiguration(plugins: names);
  }
}
