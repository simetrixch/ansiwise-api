import '../model/names.dart';
import 'resolved_program.dart';

/// The programs this deployment declares, already resolved against the registry.
///
/// One truth, read by both sides. The client renders its form from what is in here rather than from
/// a list of its own, so a new input appears in the form without a line of the client changing —
/// and a client in front of a different deployment shows that one's programs.
///
/// Everything in here has already passed the resolver, so nothing downstream has to ask whether a
/// step name exists. A catalogue that could hold an unresolved program would put that question back
/// into every reader.
abstract interface class Catalogue {
  /// Every program, in the order they were declared.
  List<ResolvedProgram> get programs;

  /// One by name, or null when there is none.
  ResolvedProgram? byName(ProgramName name);
}
