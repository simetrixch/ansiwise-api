/// An engine with no docker behind it, so the outside half of the gate can be exercised.
library;

import 'container_engine.dart';

/// One image the gate asked for.
final class ImageBuild {
  /// Records a build of [tag] from [dockerfile] with [buildArguments].
  const ImageBuild({required this.tag, required this.dockerfile, required this.buildArguments});

  /// What it was tagged.
  final String tag;

  /// The recipe it was built from.
  final String dockerfile;

  /// The values handed to that recipe.
  final Map<String, String> buildArguments;
}

/// One container the gate asked for.
final class ContainerStart {
  /// Records a run of [command] in a container of [tag].
  const ContainerStart({
    required this.tag,
    required this.mounts,
    required this.workingDirectory,
    required this.command,
    required this.interactive,
  });

  /// The image it was started from.
  final String tag;

  /// What was made available inside it.
  final List<Mount> mounts;

  /// Where the command ran.
  final String workingDirectory;

  /// What was run.
  final List<String> command;

  /// Whether this process's terminal was attached.
  final bool interactive;
}

/// A container engine that records what it was asked and answers what a test told it to.
final class FakeContainerEngine implements ContainerEngine {
  /// Creates an engine that is [reachable], already holds [images], and answers [exitCode] for a
  /// container run and [buildExitCode] for a build.
  FakeContainerEngine({
    this.reachable = true,
    Set<String> images = const <String>{},
    this.exitCode = 0,
    this.buildExitCode = 0,
  }) : _images = <String>{...images};

  final Set<String> _images;

  /// Whether the daemon answers.
  final bool reachable;

  /// What a container run exits with.
  final int exitCode;

  /// What an image build exits with.
  final int buildExitCode;

  /// Every image this engine was asked to build, in order.
  final List<ImageBuild> builds = <ImageBuild>[];

  /// Every container this engine was asked to start, in order.
  final List<ContainerStart> starts = <ContainerStart>[];

  @override
  Future<bool> isReachable() async => reachable;

  @override
  Future<bool> hasImage(String tag) async => _images.contains(tag);

  @override
  Future<int> build({
    required String tag,
    required String dockerfile,
    required String context,
    required Map<String, String> buildArguments,
  }) async {
    builds.add(ImageBuild(tag: tag, dockerfile: dockerfile, buildArguments: buildArguments));
    if (buildExitCode == 0) {
      _images.add(tag);
    }
    return buildExitCode;
  }

  @override
  Future<int> run({
    required String tag,
    required List<Mount> mounts,
    required String workingDirectory,
    required List<String> command,
    bool interactive = false,
  }) async {
    starts.add(
      ContainerStart(
        tag: tag,
        mounts: mounts,
        workingDirectory: workingDirectory,
        command: command,
        interactive: interactive,
      ),
    );
    return exitCode;
  }
}
