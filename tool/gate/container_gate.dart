/// Starting the pinned container the gate runs in.
///
/// Nothing runs in a hosted CI. This IS the CI, and it is a standing rule of this project rather
/// than a workaround: the checks are the done-criterion for every piece of work, so they have to
/// run where a person can read them, break into them and fix them in the same minute.
///
/// WHY A CONTAINER AND NOT THE BARE HOST. What is pinned is the Dart version, and that is the whole
/// of the reason. On a Windows host the suite meets whatever Dart happens to be on PATH, which is a
/// different environment — the same check has answered differently on the two — and a host run also
/// cannot see how a file behaves under a case-sensitive filesystem.
///
/// This half decides and never prints a verdict: what it answers is a [ContainerRun], so the whole
/// sequence can be driven by a test on a machine with no engine installed.
library;

import 'container_engine.dart';
import 'container_layout.dart';
import 'gate_log.dart';
import 'pins.dart';

/// What starting the gate came to.
sealed class ContainerRun {
  const ContainerRun();
}

/// The engine or the image was not there, and the gate never started.
///
/// A run that could not start is not a run that found nothing, which is why it is a case of its own
/// rather than a non-zero exit code.
final class CouldNotStart extends ContainerRun {
  /// Records why nothing ran.
  const CouldNotStart(this.why);

  /// What was missing, in the words the person reading it can act on.
  final String why;
}

/// The container ran and exited with [exitCode], having already said what it decided.
final class Finished extends ContainerRun {
  /// Records the exit code of the container.
  const Finished(this.exitCode);

  /// What the container exited with.
  final int exitCode;
}

/// The outside half of the gate: build the image if it is missing, then run the inside half in it.
final class ContainerGate {
  /// Runs the gate of [repository] on [engine], announcing what it does on [log].
  const ContainerGate({
    required this.engine,
    required this.log,
    required this.repository,
    required this.dockerfile,
    required this.buildContext,
  });

  /// How containers are built and started.
  final ContainerEngine engine;

  /// Where the gate says what it is doing.
  final GateLog log;

  /// This repository on the host, as this operating system names it.
  final String repository;

  /// The recipe the image is built from.
  final String dockerfile;

  /// The directory that recipe is given as its context.
  final String buildContext;

  /// Builds what is missing and starts the container.
  Future<ContainerRun> start({required bool rebuild, required bool shell}) async {
    if (!await engine.isReachable()) {
      return const CouldNotStart(
        'the container engine is not installed or its daemon is not reachable',
      );
    }

    if (rebuild || !await engine.hasImage(imageTag)) {
      log.note('ci: building $imageTag');
      final int built = await engine.build(
        tag: imageTag,
        dockerfile: dockerfile,
        context: buildContext,
        buildArguments: <String, String>{'DEBIAN_TAG': debianTag, 'DART_VERSION': dartVersion},
      );
      if (built != 0) {
        return const CouldNotStart('the image build failed');
      }
    }

    return Finished(
      await engine.run(
        tag: imageTag,
        mounts: mounts,
        workingDirectory: workRoot,
        command: <String>['dart', gateEntryPoint, '--inside', if (shell) '--shell'],
        interactive: shell,
      ),
    );
  }

  /// What the container is given: this tree, and the pub cache.
  List<Mount> get mounts => <Mount>[
    HostDirectory(repository, '$hostRoot/$repositoryDirectory'),
    NamedVolume(pubCacheVolume, '/root/.pub-cache'),
  ];
}
