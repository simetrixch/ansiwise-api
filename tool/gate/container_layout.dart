/// Where the gate puts things inside the container.
///
/// One definition, read by the half that starts the container and by the half that runs inside it,
/// so a check run and an interactive shell can never be looking at different things.
library;

/// Where the read-only mount of this machine appears.
const String hostRoot = '/host';

/// Where the copied tree is worked on.
const String workRoot = '/work';

/// The directory name this repository is copied under, on both sides.
const String repositoryDirectory = 'ansiwise-api';

/// The gate's own program, as the container is told to start it.
///
/// Named under [hostRoot] and not under [workRoot], because it is what does the copying: at the
/// moment it starts there is nothing in the work root yet.
const String gateEntryPoint = '$hostRoot/$repositoryDirectory/tool/ci.dart';
