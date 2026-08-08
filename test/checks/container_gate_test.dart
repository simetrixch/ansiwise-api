import 'package:test/test.dart';

import '../../tool/gate/container_engine.dart';
import '../../tool/gate/container_gate.dart';
import '../../tool/gate/container_layout.dart';
import '../../tool/gate/fake_container_engine.dart';
import '../../tool/gate/gate_log.dart';
import '../../tool/gate/pins.dart';

/// The outside half of the gate, driven without docker.
///
/// What it decides is small and every part of it has been wrong at least once in the shell script
/// this replaces: which image tag, whether to build, what the container is told to run, and what is
/// mounted where. A fake engine records all four, so each is a fact rather than something a person
/// checks by watching a container start.
void main() {
  test('the image tag carries both pins, so an image built from something else cannot answer', () {
    expect(imageTag, contains(dartVersion));
    expect(imageTag, contains(debianTag));
  });

  test('the pub cache volume carries the SDK that filled it', () {
    expect(
      pubCacheVolume,
      contains(dartVersion),
      reason: 'a cache that outlives its toolchain is a false green one layer down',
    );
  });

  test('an engine that does not answer stops the gate before anything is built', () async {
    final FakeContainerEngine engine = FakeContainerEngine(reachable: false);
    expect(await _gate(engine).start(rebuild: false, shell: false), isA<CouldNotStart>());
    expect(engine.builds, isEmpty);
    expect(engine.starts, isEmpty);
  });

  test('a missing image is built, with the pins as its build arguments', () async {
    final FakeContainerEngine engine = FakeContainerEngine();
    await _gate(engine).start(rebuild: false, shell: false);
    expect(engine.builds, hasLength(1));
    expect(engine.builds.single.tag, imageTag);
    expect(engine.builds.single.buildArguments, <String, String>{
      'DEBIAN_TAG': debianTag,
      'DART_VERSION': dartVersion,
    });
  });

  test('the recipe the image is built from is the one in this repository', () async {
    final FakeContainerEngine engine = FakeContainerEngine();
    await _gate(engine).start(rebuild: false, shell: false);
    expect(engine.builds.single.dockerfile, endsWith('tool/Dockerfile'));
  });

  test('an image that is already there is not built again', () async {
    final FakeContainerEngine engine = FakeContainerEngine(images: <String>{imageTag});
    await _gate(engine).start(rebuild: false, shell: false);
    expect(engine.builds, isEmpty);
    expect(engine.starts, hasLength(1));
  });

  test('--rebuild builds it anyway', () async {
    final FakeContainerEngine engine = FakeContainerEngine(images: <String>{imageTag});
    await _gate(engine).start(rebuild: true, shell: false);
    expect(engine.builds, hasLength(1));
  });

  test('a build that fails stops the gate rather than starting a container', () async {
    final FakeContainerEngine engine = FakeContainerEngine(buildExitCode: 1);
    expect(await _gate(engine).start(rebuild: false, shell: false), isA<CouldNotStart>());
    expect(
      engine.starts,
      isEmpty,
      reason: 'a container started from an image that was not built runs the previous one',
    );
  });

  test('the container is told to run the inside half of this same program', () async {
    final FakeContainerEngine engine = FakeContainerEngine(images: <String>{imageTag});
    await _gate(engine).start(rebuild: false, shell: false);
    expect(engine.starts.single.command, <String>['dart', gateEntryPoint, '--inside']);
    expect(
      engine.starts.single.interactive,
      isFalse,
      reason: 'a check run with a terminal attached waits for somebody who is not there',
    );
  });

  test('the inside half is started off the read-only mount, not off the copy', () {
    expect(
      gateEntryPoint,
      startsWith(hostRoot),
      reason: 'it is what does the copying, so at the moment it starts the work root is empty',
    );
  });

  test('--shell asks for the same program with a terminal attached', () async {
    final FakeContainerEngine engine = FakeContainerEngine(images: <String>{imageTag});
    await _gate(engine).start(rebuild: false, shell: true);
    expect(engine.starts.single.command, <String>['dart', gateEntryPoint, '--inside', '--shell']);
    expect(engine.starts.single.interactive, isTrue);
  });

  test('the exit code of the container is the exit code of the gate', () async {
    final FakeContainerEngine engine = FakeContainerEngine(images: <String>{imageTag}, exitCode: 7);
    expect(
      await _gate(engine).start(rebuild: false, shell: false),
      isA<Finished>().having((Finished run) => run.exitCode, 'exitCode', 7),
    );
  });

  group('what the container is given', () {
    test('this repository is mounted read-only, because the gate copies it in', () {
      final HostDirectory tree = _gate(
        FakeContainerEngine(),
      ).mounts.whereType<HostDirectory>().single;
      expect(tree.hostPath, '/repos/ansiwise-api');
      expect(tree.containerPath, '$hostRoot/$repositoryDirectory');
      expect(
        tree.readOnly,
        isTrue,
        reason: 'a run that wrote through the mount would be changing the thing it is judging',
      );
    });

    test('the pub cache survives between runs', () {
      expect(
        _gate(FakeContainerEngine()).mounts.whereType<NamedVolume>().single.name,
        pubCacheVolume,
      );
    });

    test('the container starts in the work root, where the copy lands', () async {
      final FakeContainerEngine engine = FakeContainerEngine(images: <String>{imageTag});
      await _gate(engine).start(rebuild: false, shell: false);
      expect(engine.starts.single.workingDirectory, workRoot);
    });

    test('the container is started with exactly the mounts the gate names', () async {
      final FakeContainerEngine engine = FakeContainerEngine(images: <String>{imageTag});
      final ContainerGate gate = _gate(engine);
      await gate.start(rebuild: false, shell: false);
      expect(
        engine.starts.single.mounts.map((Mount mount) => mount.containerPath),
        gate.mounts.map((Mount mount) => mount.containerPath),
        reason:
            'a gate that worked out its mounts and then started the container with something else '
            'would be judging a tree nobody named',
      );
    });
  });
}

ContainerGate _gate(FakeContainerEngine engine) => ContainerGate(
  engine: engine,
  log: CollectedGateLog(),
  repository: '/repos/ansiwise-api',
  dockerfile: '/repos/ansiwise-api/tool/Dockerfile',
  buildContext: '/repos/ansiwise-api/tool',
);
