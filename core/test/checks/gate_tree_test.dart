import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/paths.dart';

/// What the gate does to a tree before it judges it — find the packages in it — plus the path
/// arithmetic it does for itself.
///
/// Nothing under tool/ may import package:path, because the gate is what resolves the tree: its
/// own program has to start before anything has been resolved. So the little that a path library
/// would have answered is written there and proven here, and a wrong answer points the toolchain
/// at the wrong directory.
void main() {
  group('the path arithmetic tool/ does without package:path', () {
    test('a program under tool/ finds the package it is part of', () {
      expect(
        packageOfToolScript(Uri.file('/repos/ansiwise-api/tool/ci.dart')).path,
        endsWith('ansiwise-api'),
        reason:
            'taken from where the program sits and not from the working directory, so a run from a '
            'subdirectory answers the same instead of quietly gating less',
      );
    });

    test('a program one directory deeper under tool/ is not the package', () {
      expect(
        packageOfToolScript(Uri.file('/repos/ansiwise-api/tool/gate/ci.dart')).path,
        endsWith('tool'),
        reason:
            'the arithmetic is two levels up and nothing cleverer; a gate program that moved into '
            'a subdirectory would hand the toolchain the wrong directory to start in',
      );
    });

    test('the last segment is found whichever separator wrote the path', () {
      expect(baseName(r'D:\repos\ansiwise-api\tool'), 'tool');
      expect(baseName('/work/ansiwise-api/tool'), 'tool');
    });
  });

  group('finding the packages', () {
    test('a package at the root of a tree that carries code is one', () {
      final Directory scratch = _scratch();
      Directory('${scratch.path}/lib').createSync(recursive: true);
      File('${scratch.path}/pubspec.yaml').writeAsStringSync('name: planted_root\n');
      expect(dartPackagesIn(scratch).map((DartPackage package) => package.name), <String>[
        'planted_root',
      ], reason: 'a one-package repository would otherwise be invisible to every check');
    });

    test('a manifest at the root of a tree with no code is a workspace and is not one', () {
      final Directory scratch = _scratch();
      File('${scratch.path}/pubspec.yaml').writeAsStringSync('name: planted_workspace\n');
      Directory('${scratch.path}/member/lib').createSync(recursive: true);
      File('${scratch.path}/member/pubspec.yaml').writeAsStringSync('name: planted_member\n');
      expect(dartPackagesIn(scratch).map((DartPackage package) => package.name), <String>[
        'planted_member',
      ], reason: 'walking a workspace manifest as a package counts every member twice');
    });

    test('a package nobody listed anywhere is still found', () {
      final Directory scratch = _scratch();
      Directory('${scratch.path}/lib').createSync(recursive: true);
      File('${scratch.path}/pubspec.yaml').writeAsStringSync('name: planted_root\n');
      Directory('${scratch.path}/later/lib').createSync(recursive: true);
      File('${scratch.path}/later/pubspec.yaml').writeAsStringSync('name: planted_later\n');
      expect(
        dartPackagesIn(scratch).map((DartPackage package) => package.name),
        <String>['planted_root', 'planted_later'],
        reason:
            'discovery is a search of the tree and not a read of a list, or a package that lands '
            'on disk compiles, imports and breaks a rule unwatched',
      );
    });

    test('a manifest under a pruned directory is not a package of this tree', () {
      final Directory scratch = _scratch();
      Directory('${scratch.path}/lib').createSync(recursive: true);
      File('${scratch.path}/pubspec.yaml').writeAsStringSync('name: planted_root\n');
      Directory('${scratch.path}/.dart_tool/planted').createSync(recursive: true);
      File('${scratch.path}/.dart_tool/planted/pubspec.yaml').writeAsStringSync('name: resolved\n');
      expect(dartPackagesIn(scratch), hasLength(1));
    });

    test('the name comes from the manifest and not from the directory', () {
      expect(
        declaredPackageName('# a comment\nname: ansiwise_api\nversion: 0.1.0\n'),
        'ansiwise_api',
        reason: 'the directory is ansiwise-api, and a Dart package name may not carry a hyphen',
      );
    });

    test('a manifest that declares no name is not a package', () {
      expect(declaredPackageName('description: no name here\n'), isNull);
    });
  });
}

Directory _scratch() {
  final Directory directory = Directory.systemTemp.createTempSync('ansiwise-gate-tree-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
