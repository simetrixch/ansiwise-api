/// The `dart` this program is itself running under.
library;

import 'dart:io';

import 'dart_toolchain.dart';

/// Starts the real `dart`, in the directory the package sits in.
///
/// [Platform.resolvedExecutable] rather than the word `dart` on the PATH, and that is the whole
/// point of naming it here: the tool that judges the code is then the same one that compiled the
/// judge, so a machine carrying two SDKs cannot analyse the tree with one and report under the name
/// of the other. Inside the pinned container there is only ever one, which is what makes the two
/// spellings agree there and is exactly why the difference has to be settled somewhere it is
/// visible.
///
/// Every call runs FROM inside the package rather than naming it as an argument, so the
/// analysis_options that applies is the one that package ships. Nothing goes through a shell: a
/// Windows path is handed to the process as this operating system spells it, and there is nothing
/// in between to rewrite it.
final class RealDartToolchain implements DartToolchain {
  /// Creates the real toolchain.
  const RealDartToolchain();

  @override
  Future<ToolRun> pubGet({required String directory}) =>
      _capture(<String>['pub', 'get'], directory: directory);

  @override
  Future<ToolRun> analyze({required String directory}) =>
      _capture(<String>['analyze', '--fatal-infos', '--fatal-warnings'], directory: directory);

  @override
  Future<ToolRun> format({required String directory}) => _capture(<String>[
    'format',
    '--output=none',
    '--set-exit-if-changed',
    '.',
  ], directory: directory);

  @override
  Future<int> runTests({required String directory}) =>
      _stream(<String>['test'], directory: directory);

  @override
  Future<int> runScript(String script, {required String directory}) =>
      _stream(<String>['run', script], directory: directory);

  Future<ToolRun> _capture(List<String> arguments, {required String directory}) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: directory,
      runInShell: false,
    );
    return ToolRun(exitCode: result.exitCode, output: '${result.stdout}${result.stderr}');
  }

  Future<int> _stream(List<String> arguments, {required String directory}) async {
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: directory,
      mode: ProcessStartMode.inheritStdio,
      runInShell: false,
    );
    return process.exitCode;
  }
}
