/// Where the programs an audit reads its answer declarations out of stand.
///
/// **A program file is not a package's own.** It says what ONE installation deploys and in what
/// order, so it lives in that installation's repository beside the things it names; a plugin ships
/// the steps a program may name and no program at all. But the KINDS and the DEFAULTS of the answers
/// a step reads are declared nowhere else — a step reads an answer by name, and only the program
/// says whether that name holds text, a list, or a value that defaults to empty.
///
/// **So a probe that wants to plant what an installation plants has to read them.** The tree is
/// found once, here, so every package asks the same question of the same directory instead of each
/// carrying a path of its own that can drift.
///
/// **The tree named below is TEST INPUT and says what it is.** It is the checkout an audit reads
/// declarations out of when the environment names none — data describing one installation, never a
/// dependency of anything that ships. Nothing in a plugin's library, and nothing this package
/// decides, is derived from it.
///
/// **Absent FAILS, and the refusal says what it looked for.** A suite that quietly skipped the
/// declarations would report green over the one thing this exists to measure, and the shape of that
/// failure is a probe planting a value no installation ever gives.
library;

import 'dart:io';

/// The environment variable that names the installation tree, overriding the fallback.
const String installationVariable = 'ANSIWISE_INSTALLATION';

/// Where the programs stand inside an installation tree.
const String installationPrograms = 'ansiwise/programs';

/// The installation tree, as the environment names it or as a checkout of it sits beside this one.
///
/// The fallback is one relative path, taken from the directory `dart test` runs in — which is the
/// package root, and every package of every repository here sits at the same depth below the
/// directory the checkouts share.
String get installationTree =>
    Platform.environment[installationVariable] ?? '../../../digitaplatform/digita-cloud';

/// [installationTree], proven to be there.
String get installationRoot {
  if (!Directory('$installationTree/$installationPrograms').existsSync()) {
    throw StateError(
      'no programs at $installationTree/$installationPrograms — the programs of an installation '
      'live in its own repository, and these audits read that tree for the kinds and defaults its '
      'answers are declared with. Clone it beside this one, or set $installationVariable to where '
      'it is.',
    );
  }
  return installationTree;
}

/// The directory the programs of the installation stand in, proven to be there.
String get installationProgramsRoot => '$installationRoot/$installationPrograms';

/// The program file named [name], as a path a test can open.
String programAt(String name) => '$installationProgramsRoot/$name';
