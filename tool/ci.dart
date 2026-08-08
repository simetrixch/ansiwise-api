/// The gate of this repository, in a pinned Linux container, on this machine.
///
/// ```
/// dart run tool/ci.dart              build the image if needed, then run every check
/// dart run tool/ci.dart --rebuild    force a fresh image
/// dart run tool/ci.dart --shell      drop into the container, tree already in place
/// ```
///
/// It has to end with `ci: OK — every check green`.
///
/// ONE FILE, TWO ROLES. Without `--inside` this runs on the host: it builds the image if it is not
/// there and starts the container. With `--inside` it is what the container runs: it copies the
/// tree off the read-only mount and drives the checks over it. The alternative is a second entry
/// point that has to be kept in step with this one, and the two would answer differently the first
/// time somebody edited one of them. Nobody types `--inside`.
///
/// THIS FILE IMPORTS NOTHING BUT `dart:`, AND EVERYTHING UNDER tool/gate/ THAT IT REACHES DOES THE
/// SAME. Inside the container it is started as a bare script off the read-only mount before
/// anything has been resolved — it is what copies the tree in — and the package config it would
/// find beside it there is the host's, holding absolute paths into a Windows filesystem. A single
/// `package:` import would make the gate unable to start until the gate had run.
library;

import 'dart:io';

import 'gate/container_gate.dart';
import 'gate/container_layout.dart';
import 'gate/dart_packages.dart';
import 'gate/gate_log.dart';
import 'gate/package_gate.dart';
import 'gate/paths.dart';
import 'gate/real_container_engine.dart';
import 'gate/real_dart_toolchain.dart';
import 'gate/tree_copy.dart';

/// Runs the gate and answers non-zero when anything is wrong.
Future<void> main(List<String> arguments) async {
  bool rebuild = false;
  bool shell = false;
  bool inside = false;
  for (final String argument in arguments) {
    switch (argument) {
      case '--rebuild':
        rebuild = true;
      case '--shell':
        shell = true;
      case '--inside':
        inside = true;
      default:
        stderr.writeln(
          'ci: FAIL — unknown option $argument (expected --rebuild, --shell or --inside)',
        );
        exit(2);
    }
  }

  exitCode = inside
      ? await _insideTheContainer(shell: shell)
      : await _startTheContainer(rebuild: rebuild, shell: shell);
}

/// The half that runs on this machine: build the image if it is missing, then start the other half.
Future<int> _startTheContainer({required bool rebuild, required bool shell}) async {
  final Directory repository = packageOfToolScript(Platform.script);

  final ContainerGate gate = ContainerGate(
    engine: const RealContainerEngine(),
    log: const StdoutGateLog(),
    repository: repository.path,
    dockerfile: '${repository.path}/tool/Dockerfile',
    buildContext: '${repository.path}/tool',
  );

  switch (await gate.start(rebuild: rebuild, shell: shell)) {
    case CouldNotStart(:final String why):
      stderr.writeln('ci: FAIL — $why');
      return 1;
    case Finished(:final int exitCode):
      return exitCode;
  }
}

/// The half that runs inside the container: copy the tree in, then check every package in it.
Future<int> _insideTheContainer({required bool shell}) async {
  const GateLog log = StdoutGateLog();
  final Directory mounted = Directory('$hostRoot/$repositoryDirectory');
  if (!mounted.existsSync()) {
    stderr.writeln('ci: FAIL — ${mounted.path} is not mounted, so there is no tree to check');
    return 1;
  }

  final Directory repository = Directory('$workRoot/$repositoryDirectory');
  copyTree(mounted, repository);

  if (shell) {
    // The developer's own interactive shell, in the container the checks run in. Nothing about the
    // gate goes through it — it is here so that a check that answers differently inside can be
    // taken apart where it answers that way.
    final Process session = await Process.start(
      'bash',
      const <String>[],
      workingDirectory: repository.path,
      mode: ProcessStartMode.inheritStdio,
    );
    return session.exitCode;
  }

  final GateVerdict verdict = await PackageGate(
    toolchain: const RealDartToolchain(),
    packages: dartPackagesIn(repository),
    log: log,
    analysisRoot: repository.path,
  ).run();

  log.heading('verdict');
  if (verdict.green) {
    stdout.writeln(verdict.line);
    return 0;
  }
  stderr.writeln(verdict.line);
  return 1;
}
