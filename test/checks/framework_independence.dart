/// Which packages a framework reaches that are not on pub.dev, and what reached them.
///
/// The direction is the whole design and only one way is forbidden. A plugin depending on the
/// framework is what a plugin IS. A plugin depending on another plugin is what makes units units.
/// The framework depending on anything below it is the one arrow that must not exist — the moment
/// it did, that unit would stop being optional and everybody using the framework would drag it
/// along whether they wanted it or not.
///
/// **WHY WALKING THE UNHOSTED EDGES IS THE WHOLE GRAPH**, and this is what makes a check of a few
/// hundred lines complete rather than approximate: every package of this organisation declares
/// `publish_to: none`. An unpublished package cannot be reached from a published one, because pub
/// refuses to publish a package that depends on one — so at every hop, the only way to reach one of
/// ours is `path:` or `git:`. A dependency resolved from pub.dev therefore cannot lead anywhere
/// this check needs to look, and stopping there loses nothing.
///
/// So the rule is stated as its contrapositive, which is the form that can be measured: **every
/// package the framework reaches from OUTSIDE this repository is hosted on pub.dev.** Anything else
/// is something of ours, and the only things of ours below the framework are its plugins.
///
/// **A package inside this repository is not below the framework — it IS the framework's
/// repository.** The gate's own audits are such a package: they walk files, so they need `dart:io`,
/// which the shipped library may not have outside `infrastructure/`, so they cannot live in it. A
/// rule that forbade that edge would not be protecting anything — a sibling in the same checkout
/// cannot make a unit non-optional for anybody, and it reaches nothing that depends on the
/// framework. What it must still
/// do is be WALKED: a repository-local package that reaches a plugin is the same failure one hop
/// further out, and it is reported with the chain that got there.
library;

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A package's two manifests, as far as this check reads them.
///
/// The overrides file is here because it is the quiet door. `dependency_overrides:` and a sibling
/// `pubspec_overrides.yaml` both redirect a name that reads as an ordinary hosted dependency to
/// something on disk, and a check that read only `dependencies:` would call such a tree clean.
typedef Manifests = ({String? pubspec, String? overrides});

/// One dependency edge that leaves pub.dev.
final class UnhostedEdge {
  /// Records that [package] was declared as a [kind] dependency, reached along [chain].
  const UnhostedEdge({required this.package, required this.kind, required this.chain});

  /// The name of the package depended on.
  final String package;

  /// How it was declared: `path`, `git`, or the section of a manifest that redirected it.
  final String kind;

  /// Every package from the framework to this one, in order.
  final List<String> chain;

  /// The finding, as the gate prints it.
  ///
  /// It names the dependency AND the chain that reached it, because on a transitive one those are
  /// different answers: knowing that `planted_plugin` is in the tree does not say which of the
  /// framework's own dependencies to take back out.
  @override
  String toString() => '$package — a $kind dependency, reached by ${chain.join(' -> ')}';
}

/// Every package [root] reaches from outside this repository that is not hosted on pub.dev, with
/// the chain that reached each.
///
/// [manifestsOf] answers with the two manifests of the package at a directory given relative to the
/// repository root, or null where they cannot be read. A path whose manifests cannot be read still
/// produces its own finding where it points outside — the edge is what is being reported, and an
/// unreadable target does not make the edge allowed.
///
/// A declared path is resolved against the directory of the package that DECLARED it, which is what
/// pub does: `path: ..` written in `checks/pubspec.yaml` means the repository root and not the
/// parent of wherever the walk started.
///
/// Walking stops at a hosted dependency and at a directory already visited, so a cycle between two
/// path packages terminates.
List<UnhostedEdge> unhostedReachOf({
  required String root,
  required Manifests manifests,
  required Manifests? Function(String directory) manifestsOf,
}) {
  final List<UnhostedEdge> found = <UnhostedEdge>[];
  final Set<String> visited = <String>{''};

  void walk(Manifests here, String directory, List<String> chain) {
    for (final _Declared declared in _dependenciesIn(here)) {
      final List<String> reached = <String>[...chain, declared.name];
      if (declared.kind == _hosted || declared.kind == _sdk) {
        // Hosted goes no further for the reason in this library's own doc, and the SDK is not ours
        // — neither can lead to an unpublished package of this organisation.
        continue;
      }
      final String? declaredPath = declared.path;
      final String? at = declaredPath == null
          ? null
          : p.url.normalize(p.url.join(directory, declaredPath));
      // Inside this repository is not a finding, and is still walked. Outside is reported whether
      // or not it can be followed.
      if (at == null || at.startsWith('..')) {
        found.add(UnhostedEdge(package: declared.name, kind: declared.kind, chain: reached));
      }
      if (at == null || !visited.add(at)) {
        continue;
      }
      final Manifests? beyond = manifestsOf(at);
      if (beyond != null) {
        walk(beyond, at, reached);
      }
    }
  }

  walk(manifests, '', <String>[root]);
  return found;
}

const String _hosted = 'hosted';
const String _sdk = 'sdk';

/// One dependency as a manifest declares it.
final class _Declared {
  const _Declared({required this.name, required this.kind, this.path});

  final String name;
  final String kind;

  /// Where its own manifests are, relative to the package that declared it, or null when this edge
  /// leads somewhere that cannot be read from here.
  final String? path;
}

/// Every dependency the two manifests declare, overrides last so they win.
///
/// All three sections of the pubspec are read. A dev dependency on a plugin is the same coupling
/// wearing a different hat: the framework's own tests would then be running against a tree with the
/// platform in it, and the example a plugin author copies would be one that never proved the
/// framework stands alone.
List<_Declared> _dependenciesIn(Manifests manifests) {
  final Map<String, _Declared> byName = <String, _Declared>{};
  for (final (String? text, List<String> sections) in <(String?, List<String>)>[
    (manifests.pubspec, <String>['dependencies', 'dev_dependencies', 'dependency_overrides']),
    (manifests.overrides, <String>['dependency_overrides']),
  ]) {
    if (text == null) {
      continue;
    }
    final Object? document = loadYaml(text);
    if (document is! YamlMap) {
      throw const FormatException(
        'a manifest that is not a mapping cannot be read for dependencies',
      );
    }
    for (final String section in sections) {
      final Object? entries = document[section];
      if (entries == null) {
        continue;
      }
      if (entries is! YamlMap) {
        // Refused rather than read past. A section this check cannot read holds no dependencies as
        // far as it can tell, and answering "clean" there is the check claiming to have looked at
        // something it did not — which is the one thing a gate must never do.
        throw FormatException('"$section" is not a mapping, so its dependencies cannot be read');
      }
      for (final MapEntry<Object?, Object?> entry in entries.entries) {
        final Object? name = entry.key;
        if (name is! String) {
          continue;
        }
        byName[name] = _declaredAs(name, entry.value);
      }
    }
  }
  return byName.values.toList(growable: false);
}

/// What one entry of a dependency section declares.
///
/// A bare version constraint, and a name with nothing under it at all, are both pub.dev. Anything
/// else says where it really comes from, and `path` is the only one this check can follow.
_Declared _declaredAs(String name, Object? value) {
  if (value is! YamlMap) {
    return _Declared(name: name, kind: _hosted);
  }
  final Object? path = value['path'];
  if (path is String) {
    return _Declared(name: name, kind: 'path', path: path);
  }
  if (value.containsKey('git')) {
    return _Declared(name: name, kind: 'git');
  }
  if (value.containsKey('sdk')) {
    return _Declared(name: name, kind: _sdk);
  }
  return _Declared(name: name, kind: _hosted);
}
