import '../domain/catalogue.dart';
import '../domain/files.dart';
import '../domain/registry.dart';
import '../domain/resolved_program.dart';
import '../engine/program_resolver.dart';
import '../model/failures.dart';
import '../model/names.dart';
import 'program_loader.dart';

/// The programs a directory of files declares, loaded once and resolved against a registry.
///
/// The directory is taken whole or not at all. A deployment whose programs half loaded is a
/// deployment where the one program an operator reaches for is the one that is missing, and nothing
/// says so until they reach for it — so a single bad file refuses the lot, and the refusal names
/// every bad file with everything wrong in it.
final class LoadedCatalogue implements Catalogue {
  /// Holds [programs], in the order they were read.
  LoadedCatalogue(this.programs)
    : _byName = <ProgramName, ResolvedProgram>{
        for (final ResolvedProgram program in programs) program.declared.name: program,
      };

  /// Reads every `*.yaml` in [directory] through [files], and resolves each against [registry].
  ///
  /// Throws [ProgramInvalid] naming every file that does not add up, with that file's problems
  /// indented beneath it.
  static Future<LoadedCatalogue> load({
    required Files files,
    required String directory,
    required Registry registry,
  }) async {
    final List<String> names = <String>[
      for (final String name in await files.list(directory))
        if (name.endsWith('.yaml')) name,
    ]..sort();

    final ProgramResolver resolver = ProgramResolver(registry);
    final List<ResolvedProgram> loaded = <ResolvedProgram>[];
    final List<String> problems = <String>[];
    final Map<ProgramName, String> claimed = <ProgramName, String>{};

    for (final String name in names) {
      // The port lists names rather than paths, and splits them on a forward slash. Joining with
      // `package:path` would produce a backslash on Windows and stop matching what it handed back.
      final String path = '$directory/$name';
      try {
        final ResolvedProgram program = resolver.resolve(
          loadProgram(await files.read(path), where: name),
        );
        final ProgramName declared = program.declared.name;
        final String? taken = claimed[declared];
        if (taken != null) {
          // A name is what a sub-command and [byName] resolve, so two files claiming one name
          // leaves whichever of them is reached a matter of the order the directory was read in.
          problems.add('$name: declares "$declared", and so does $taken');
          continue;
        }
        claimed[declared] = name;
        loaded.add(program);
      } on ProgramInvalid catch (refused) {
        problems.add('$name:\n${_indented(refused.message)}');
      }
    }

    if (problems.isNotEmpty) {
      throw ProgramInvalid(problems.join('\n'), where: directory);
    }
    return LoadedCatalogue(loaded);
  }

  @override
  final List<ResolvedProgram> programs;

  final Map<ProgramName, ResolvedProgram> _byName;

  @override
  ResolvedProgram? byName(ProgramName name) => _byName[name];
}

/// [message] with every line pushed in, so a file's problems read as belonging to that file.
String _indented(String message) => message.split('\n').map((String line) => '  $line').join('\n');
