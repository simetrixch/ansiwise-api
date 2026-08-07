import 'package:meta/meta.dart';

import 'clock.dart';
import 'files.dart';
import 'http.dart';
import 'shell.dart';

/// The whole of the outside world, as this framework can reach it.
///
/// Four ports and nothing else. Everything a program does to a machine goes through one of them,
/// which is what makes a run recordable without anyone logging, a dry run refusable without anyone
/// remembering, and a step testable without a machine.
///
/// A real run is given implementations that talk to the machine; a test is given fakes; a dry run
/// is given the real ones behind a wrapper that refuses what would change anything.
@immutable
final class Machine {
  /// Bundles the four ports.
  const Machine({
    required this.shell,
    required this.files,
    required this.http,
    required this.clock,
  });

  /// Running a command.
  final Shell shell;

  /// Reading and writing files.
  final Files files;

  /// Sending a request.
  final Http http;

  /// Asking the time and waiting.
  final Clock clock;
}
