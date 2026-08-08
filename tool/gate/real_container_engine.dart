/// The docker on this machine.
///
/// Every call starts the executable directly rather than through a shell, which is what makes this
/// work unchanged on Windows. The shell script this replaces had to defend against Git Bash
/// rewriting anything that looked like a unix path before docker saw it — `-w /work` arrived as
/// `C:/Program Files/Git/work`, and a mount source arrived half-translated, which took a `cygpath`
/// call for every host path and an `MSYS_NO_PATHCONV` on every invocation. With no shell in the way
/// there is nothing to rewrite: a Windows path is passed as this operating system spells it, and a
/// container-side path is passed untouched.
library;

import 'dart:io';

import 'container_engine.dart';

/// Starts the real `docker`.
final class RealContainerEngine implements ContainerEngine {
  /// Creates the real engine.
  const RealContainerEngine();

  @override
  Future<bool> isReachable() async {
    try {
      final ProcessResult info = await Process.run(_docker, <String>['info'], runInShell: false);
      return info.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<bool> hasImage(String tag) async {
    try {
      final ProcessResult inspect = await Process.run(_docker, <String>[
        'image',
        'inspect',
        tag,
      ], runInShell: false);
      return inspect.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<int> build({
    required String tag,
    required String dockerfile,
    required String context,
    required Map<String, String> buildArguments,
  }) => _stream(<String>[
    'build',
    '-t',
    tag,
    for (final MapEntry<String, String> argument in buildArguments.entries) ...<String>[
      '--build-arg',
      '${argument.key}=${argument.value}',
    ],
    '-f',
    dockerfile,
    context,
  ]);

  @override
  Future<int> run({
    required String tag,
    required List<Mount> mounts,
    required String workingDirectory,
    required List<String> command,
    bool interactive = false,
  }) => _stream(<String>[
    'run',
    '--rm',
    if (interactive) '-it' else '-i',
    for (final Mount mount in mounts) ...<String>['-v', _volumeArgument(mount)],
    '-w',
    workingDirectory,
    tag,
    ...command,
  ]);

  Future<int> _stream(List<String> arguments) async {
    final Process process = await Process.start(
      _docker,
      arguments,
      mode: ProcessStartMode.inheritStdio,
      runInShell: false,
    );
    return process.exitCode;
  }

  static String _volumeArgument(Mount mount) => switch (mount) {
    HostDirectory(:final String hostPath, :final String containerPath, :final bool readOnly) =>
      '$hostPath:$containerPath${readOnly ? ':ro' : ''}',
    NamedVolume(:final String name, :final String containerPath) => '$name:$containerPath',
  };

  static const String _docker = 'docker';
}
