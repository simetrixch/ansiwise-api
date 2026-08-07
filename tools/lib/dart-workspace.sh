# Whether a check can run this repository's Dart, and making it so.
#
# Several checks decide something that is only true of the code once it is RUNNING — which class a
# registry entry builds, whether a step's plan refuses a mutation, whether a second run does
# nothing. Those checks start Dart, so they need two things that a scan of the text does not: the
# `dart` command, and a resolved workspace.
#
# THE RESOLVED WORKSPACE IS `.dart_tool/package_config.json` AT THE REPOSITORY ROOT, and it is
# missing more often than one would guess. tools/Dockerfile deliberately leaves .dart_tool behind
# when it copies the tree into the container, because the file holds absolute paths into the host
# filesystem; a fresh clone has never had one. A check that went red on that would be reporting the
# absence of a build directory as a defect in the tree, so the file is produced here instead —
# `dart pub get` at the workspace root writes one covering every member at once.
#
# This file is sourced, never executed. It sets no shell options: a library that turns on `set -e`
# changes the behaviour of code it cannot see, and every check sets its own.

# Makes <repository root> ready to run Dart, or writes why it is not and answers non-zero.
#
# The caller decides what an unusable workspace costs its verdict. A check that cannot start Dart
# has not measured anything, so silence here would be the worst answer of the three.
dart_workspace_ready() {
  local repo="$1"

  if ! command -v dart >/dev/null 2>&1; then
    echo "dart is not on PATH, so nothing that runs this repository's code can be measured" >&2
    return 1
  fi

  if [ -f "$repo/.dart_tool/package_config.json" ]; then
    return 0
  fi

  # Output is kept rather than discarded: when this fails it is the only thing that says why, and a
  # resolution failure reads nothing like a check failure.
  local out rc=0
  out="$(cd "$repo" && dart pub get 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] || [ ! -f "$repo/.dart_tool/package_config.json" ]; then
    echo "dart pub get did not resolve the workspace in $repo, so package: imports cannot be found:" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi
  return 0
}
