/// The container engine, as the gate asks it things.
///
/// The gate runs in a pinned Linux container on this machine and nowhere else. What it needs of an
/// engine is small and stated here, so the outside half can be exercised — which image tag, which
/// mounts, which command — without docker being installed or a container being started. The order
/// is the part that has been wrong before: a step that runs after a failed build reports a tree
/// full of defects that nothing ever looked at.
library;

/// Something made available inside a container.
sealed class Mount {
  const Mount(this.containerPath);

  /// Where it appears inside the container.
  final String containerPath;
}

/// A directory of this machine, visible inside the container.
final class HostDirectory extends Mount {
  /// Mounts [hostPath] at [containerPath].
  const HostDirectory(this.hostPath, super.containerPath, {this.readOnly = true});

  /// The directory on this machine, as this operating system names it.
  final String hostPath;

  /// Whether the container may write through it.
  ///
  /// Read-only by default: the gate copies the tree in rather than working in the mount, so a run
  /// that changed the working copy would be changing the thing it is judging.
  final bool readOnly;
}

/// A volume the engine keeps between runs.
final class NamedVolume extends Mount {
  /// Mounts the volume called [name] at [containerPath].
  const NamedVolume(this.name, super.containerPath);

  /// What the engine files it under.
  final String name;
}

/// What the gate does with the container engine.
abstract interface class ContainerEngine {
  /// Whether the engine is installed and answering.
  Future<bool> isReachable();

  /// Whether an image tagged [tag] is already built.
  Future<bool> hasImage(String tag);

  /// Builds [tag] from [dockerfile], with [context] as the build context and [buildArguments] as
  /// its build arguments, and answers what the build exited with.
  Future<int> build({
    required String tag,
    required String dockerfile,
    required String context,
    required Map<String, String> buildArguments,
  });

  /// Runs [command] in a container of [tag], with [mounts] in place, and answers what it exited
  /// with.
  ///
  /// [interactive] attaches this process's terminal, which is what a developer asking for a shell
  /// inside the gate needs and what a check run must not have.
  Future<int> run({
    required String tag,
    required List<Mount> mounts,
    required String workingDirectory,
    required List<String> command,
    bool interactive = false,
  });
}
