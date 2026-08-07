#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# ===========================================================================
# exec-confinement — nothing outside infrastructure/ reaches the machine directly.
#
# The dry-run guarantee is that `--mode dry` cannot change anything, and it rests on two
# independent things: the engine calls a step's plan and never its apply, and the ports handed to
# the step — Shell, Files, Http — throw on any call the step did not declare as only looking. The
# second is what holds when the first is wrong.
#
# It holds only for what goes THROUGH those ports. A step that writes `Process.run(...)` or
# `File(path).writeAsString(...)` has left the framework: the port never sees the call, the run
# record never mentions it, and the dry run reports that nothing would change while the machine
# was already changed. Nothing about that line looks wrong in review — it is shorter than the port
# call and does the same thing on a real run.
#
# So the reach itself is confined by name. A directory called infrastructure/ is where a port is
# implemented against the real machine; everywhere else in the shipped library — domain,
# application, presentation, the engine, the steps — asks a port. This scan is the wall.
#
# THE RULE IS ABOUT THE SHIPPED LIBRARY, so two directories of the package layout stand outside it:
#
#   test/  A test that could not open programs/deploy-host.yaml would be verifying a copy of the
#          program pasted into the test rather than the program that ships. Nothing under test/ is
#          shipped, and no dry run of a real deployment goes through it.
#   bin/   The entry point reads the process's own arguments and sets its exit code, which is
#          dart:io and can be nothing else. It does the machine's work through the ports like
#          everything above it.
#
# Both are matched at the package root — <package>/test/, <package>/bin/ — and not as a path
# segment anywhere. lib/src/testing/ ships: it is the fake machine the framework hands to a step's
# test, and a fake that reached the real one would defeat the thing it exists for.
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/verdict.sh
. "$HERE/../lib/verdict.sh"
# shellcheck source=../lib/dart-packages.sh
. "$HERE/../lib/dart-packages.sh"

# The five ways out of the process. Matched case-SENSITIVELY and word-anchored, because these are
# Dart identifiers: the prose "a step never starts a process itself" is not a reference to
# `Process`, and the port class `Files` is not `File`.
DIRECT_REACH='dart:io|Process|File|HttpClient|SSHClient'

# Whether <file> is one of the three places the reach is allowed in the package rooted at <root>.
reach_is_allowed_in() {
  local root="$1" file="$2"
  case "$file" in
    # An infrastructure/ directory is where the reach belongs. The test is on a path segment, so a
    # file merely NAMED infrastructure.dart is not inside one.
    */infrastructure/*) return 0 ;;
    # test/ and bin/ of the package are not the shipped library. Anchored at the package root, so
    # lib/src/testing/ — which does ship — stays inside the wall.
    "$root"/test/*|"$root"/bin/*) return 0 ;;
  esac
  return 1
}

# Every reference outside the three allowed places under <root>, as <file>:<line>:<text>. Takes a
# root — a Dart package directory — so the counter-probe can drive the same scan over a tree it
# planted.
scan_for_direct_reach() {
  local root="$1" file out rc line text trimmed
  [ -d "$root" ] || return 0
  while IFS= read -r file; do
    reach_is_allowed_in "$root" "$file" && continue
    rc=0
    out="$(grep -nwE -e "$DIRECT_REACH" -- "$file")" || rc=$?
    if [ "$rc" -gt 1 ]; then
      echo "exec-confinement: grep failed with status $rc over $file" >&2
      return "$rc"
    fi
    [ -n "$out" ] || continue
    while IFS= read -r line; do
      text="${line#*:}"
      trimmed="${text#"${text%%[![:space:]]*}"}"
      # A line that is nothing but a comment names the thing, it does not reach it. The framework's
      # own doc comments say what a port exists instead of — "neither of these knows about a socket
      # or dart:io" — and a scan that could not tell that from a call would forbid the sentence that
      # states the rule. Nothing executable can hide there: a comment-only line runs no code, and a
      # trailing comment sits on a line that is scanned anyway.
      case "$trimmed" in
        '///'*|'//'*|'*'*|'/*'*) continue ;;
      esac
      printf '%s:%s\n' "$file" "$line"
    done <<< "$out"
  done < <(dart_source_files "$root")
  return 0
}

PACKAGES=()
while IFS= read -r dir; do
  PACKAGES+=("$dir")
done < <(dart_package_dirs "$REPO")

[ ${#PACKAGES[@]} -gt 0 ] || verdict_skip "this tree holds no Dart package"

SCANNED=0
ALLOWED=0
for pkg in "${PACKAGES[@]}"; do
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if reach_is_allowed_in "$pkg" "$file"; then
      ALLOWED=$((ALLOWED + 1))
    else
      SCANNED=$((SCANNED + 1))
    fi
  done < <(dart_source_files "$pkg")
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    finding "${hit#"$REPO/"}"
  done <<< "$(scan_for_direct_reach "$pkg")"
done

# Both directions, or the probe proves nothing: a planted reach outside infrastructure/ must be
# reported, and the same line inside one must not. A scan that reported everything would pass the
# first half alone.
PROBE="$(mktemp -d)"
trap 'rm -rf "$PROBE"' EXIT
mkdir -p "$PROBE/lib/src/domain" "$PROBE/lib/src/infrastructure" "$PROBE/lib/src/testing" \
         "$PROBE/test/executions" "$PROBE/bin"
REACHES=("import 'dart:io';" 'Future<void> reach() async => Process.run("true", const <String>[]);')
printf '%s\n' \
  "import 'dart:io';" \
  'Future<void> plantedApply() async => Process.run("rm", <String>["-rf", "/"]);' \
  > "$PROBE/lib/src/domain/planted.dart"
printf '%s\n' "${REACHES[@]}" > "$PROBE/lib/src/infrastructure/real_shell.dart"
printf '%s\n' "${REACHES[@]}" > "$PROBE/test/executions/reads_a_program.dart"
printf '%s\n' "${REACHES[@]}" > "$PROBE/bin/main.dart"
# lib/src/testing/ ships and only LOOKS like test/. If the two allowances are ever collapsed into a
# substring match on "test", this file is what reports it.
printf '%s\n' "${REACHES[@]}" > "$PROBE/lib/src/testing/fake_machine.dart"

# The findings read <file>:<line>:<text>, and the text of one finding can name another file. The
# assertions therefore match a path in the FILE position — `<path>:` — never anywhere in the line.
PROBE_HITS="$(scan_for_direct_reach "$PROBE")"
for planted in lib/src/domain/planted.dart lib/src/testing/fake_machine.dart; do
  if ! grep -qF "$planted:" <<< "$PROBE_HITS"; then
    finding "counter-probe: a planted 'import dart:io' plus Process.run in $planted was not reported, so this scan cannot go red there"
  fi
done
for allowed in lib/src/infrastructure/real_shell.dart test/executions/reads_a_program.dart bin/main.dart; do
  if grep -qF "$allowed:" <<< "$PROBE_HITS"; then
    finding "counter-probe: the same lines in $allowed were reported, so this scan refuses one of the three places the reach belongs"
  fi
done

note "scanned $SCANNED Dart file(s) in ${#PACKAGES[@]} package(s) for: ${DIRECT_REACH//|/, }"
note "$ALLOWED file(s) allowed the reach — every infrastructure/ directory, plus each package's test/ and bin/"
verdict "nothing in a package's shipped library outside an infrastructure/ directory references dart:io, Process, File, HttpClient or SSHClient — test/ and bin/ are not the shipped library"
