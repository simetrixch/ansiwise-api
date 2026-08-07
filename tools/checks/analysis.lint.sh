#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# ===========================================================================
# analysis — the analyzer and the formatter are clean for every Dart package.
#
# `dart analyze --fatal-infos --fatal-warnings` with this repository's analysis_options is not a
# style pass. strict-casts, strict-inference and strict-raw-types are on, so an implicit cast, an
# inferred `dynamic` and a raw generic are each a type the author never chose and each stops the
# build; unused_import, unused_local_variable and dead_code are raised to errors, which is the
# no-leftovers rule of this project enforced by a tool rather than by a reviewer. `dart format
# --set-exit-if-changed` is what keeps a diff about the change instead of about the whitespace.
#
# THIS DELIBERATELY OVERLAPS tools/ci.sh, WHICH RUNS THE SAME TWO PER PACKAGE. Neither is redundant
# and neither should be "simplified" away. ci.sh is the faithful run — a pinned container, one Dart,
# a `pub get` and the tests — and it is what has to be green before a push. This check is what makes
# `tools/run-checks.sh` alone a complete gate: the checks are the done-criterion for a piece of work,
# they are run far more often than the container is, and a set of checks that could all pass while
# the code does not compile would be a gate with a hole in exactly the place people lean on it.
#
# A PACKAGE WHOSE DEPENDENCIES ARE NOT RESOLVED IS NOT ANALYSED, AND IS NAMED FOR IT. The analyzer
# answers a package it cannot resolve with one error per import and then hundreds more about every
# name those imports would have brought in — a missing toolchain reported as a tree full of defects,
# which is the one answer nobody can act on. digita-cloud-client is the live case: it needs the
# Flutter SDK, it resolves on its own rather than as a member of this workspace, and the container
# tools/ci.sh builds carries plain Dart. So the package config that applies is read first, and a
# package it does not cover is reported NOT ANALYSED with its name on the verdict line. That is a
# gap and it is meant to read as one; it is not a pass, and ci.sh fails that package's `pub get`
# independently.
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/verdict.sh
. "$HERE/../lib/verdict.sh"
# shellcheck source=../lib/dart-packages.sh
. "$HERE/../lib/dart-packages.sh"
# shellcheck source=../lib/dart-workspace.sh
. "$HERE/../lib/dart-workspace.sh"

# The package config the analyzer would use for <dir>: the nearest one at or above it.
#
# This is the analyzer's own rule, and following it is what lets the answer below be about the same
# file the analyzer will read. A workspace member has none of its own — one resolution at the
# workspace root covers every member — and a package that resolves on its own has one beside it.
package_config_for() {
  local dir="$1"
  while [ -n "$dir" ] && [ "$dir" != / ] && [ "$dir" != . ]; do
    if [ -f "$dir/.dart_tool/package_config.json" ]; then
      printf '%s\n' "$dir/.dart_tool/package_config.json"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# Whether the package in <dir> is covered by the package config that applies to it.
#
# The test is that the config names the package itself. A config that does not know the package
# cannot know its dependencies either, so every import in it is unresolved and every issue the
# analyzer would report is about that and nothing else.
package_is_resolved() {
  local dir="$1" name config
  name="$(dart_package_name "$dir")"
  [ -n "$name" ] || return 1
  config="$(package_config_for "$dir")" || return 1
  grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$name\"" "$config"
}

# Every issue the analyzer reports for <dir>, one per line.
#
# Run from inside the directory rather than given as an argument, so the analysis_options that
# applies is the one that package ships. The exit status is not read: the analyzer answers 1, 2 and
# 3 for different severities and 0 for a run that found nothing, and what this check reports is the
# issues themselves.
analyzer_issues() {
  local dir="$1"
  (cd "$dir" && dart analyze --fatal-infos --fatal-warnings 2>&1) \
    | grep -E '^[[:space:]]*(error|warning|info) - ' || true
}

# Every file under <dir> the formatter would change, one per line.
#
# `--output=none` writes nothing, so a red run leaves the tree exactly as it found it: a check that
# repaired what it measures would be green the second time for having changed the thing it judged.
formatter_changes() {
  local dir="$1"
  (cd "$dir" && dart format --output=none --set-exit-if-changed . 2>&1) \
    | grep -E '^Changed ' || true
}

PACKAGES=()
while IFS= read -r dir; do
  PACKAGES+=("$dir")
done < <(dart_package_dirs "$REPO")

[ ${#PACKAGES[@]} -gt 0 ] || verdict_skip "this tree holds no Dart package"
dart_workspace_ready "$REPO" || exit 1

ANALYSED=0
NOT_ANALYSED=()
for pkg in "${PACKAGES[@]}"; do
  name="${pkg#"$REPO/"}"

  if package_is_resolved "$pkg"; then
    ANALYSED=$((ANALYSED + 1))
    while IFS= read -r issue; do
      [ -n "$issue" ] || continue
      finding "$name: ${issue#"${issue%%[![:space:]]*}"}"
    done < <(analyzer_issues "$pkg")
  else
    NOT_ANALYSED+=("$name")
    note "NOT ANALYSED: $name — nothing here resolved its dependencies, so the analyzer would answer with one error per import and nothing about the code. Resolving it with the SDK its own pubspec asks for is what opens it to this check."
  fi

  # The formatter parses and never resolves, so it holds for a package whose dependencies are
  # missing exactly as it does for one that has them. An unresolved package is unanalysed, not
  # unchecked.
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    finding "$name: dart format would change ${changed#Changed }"
  done < <(formatter_changes "$pkg")
done

# Both tools, over a package this check writes, so a green run is known to be a measurement rather
# than a scan that stopped working. The planted file carries one defect for each: an assignment the
# analyzer refuses, and spacing the formatter would rewrite.
PROBE="$(mktemp -d)"
trap 'rm -rf "$PROBE"' EXIT
mkdir -p "$PROBE/broken/lib" "$PROBE/clean/lib"
printf '%s\n' \
  'void main() {' \
  '  final int planted = "this is text, and the analyzer refuses the assignment";' \
  '  print(planted);' \
  '}' \
  > "$PROBE/broken/lib/planted.dart"
printf 'void main() {\n  print(1);\n}\n' > "$PROBE/clean/lib/planted.dart"

if [ -z "$(analyzer_issues "$PROBE/broken")" ]; then
  finding "counter-probe: a planted assignment of text to an int was not reported, so this check cannot go red on the analyzer"
fi
if [ -n "$(analyzer_issues "$PROBE/clean")" ]; then
  finding "counter-probe: a file with nothing wrong in it was reported, so this check would turn every package red"
fi

printf 'void main(){int   planted=1;print(planted);}\n' > "$PROBE/broken/lib/planted.dart"
if [ -z "$(formatter_changes "$PROBE/broken")" ]; then
  finding "counter-probe: a deliberately unformatted file was not reported, so this check cannot go red on the formatter"
fi
if [ -n "$(formatter_changes "$PROBE/clean")" ]; then
  finding "counter-probe: an already formatted file was reported as needing a change"
fi

# The resolution test, from both sides, over two packages this check writes. Only the second half
# has teeth in a tree where everything is resolved: a rule that called every package unresolved
# would report a green analysis over a tree it never looked at, which is the shape this whole
# escape hatch could rot into.
printf 'name: planted_unresolved\n' > "$PROBE/broken/pubspec.yaml"
printf 'name: planted_resolved\n'   > "$PROBE/clean/pubspec.yaml"
mkdir -p "$PROBE/clean/.dart_tool"
printf '%s\n' '{ "configVersion": 2, "packages": [ { "name": "planted_resolved", "rootUri": "../" } ] }' \
  > "$PROBE/clean/.dart_tool/package_config.json"
if package_is_resolved "$PROBE/broken"; then
  finding "counter-probe: a package no reachable package config names was called resolved, so an unanalysable package would be reported as a tree full of defects"
fi
if ! package_is_resolved "$PROBE/clean"; then
  finding "counter-probe: a package its own package config names was called unresolved, so this check would stop analysing everything"
fi

GAP=""
if [ ${#NOT_ANALYSED[@]} -gt 0 ]; then
  GAP=", and ${#NOT_ANALYSED[@]} was NOT ANALYSED — ${NOT_ANALYSED[*]} — because nothing here resolved its dependencies, though the formatter still read it"
fi

note "${#PACKAGES[@]} Dart package(s): $ANALYSED analysed, ${#NOT_ANALYSED[@]} not analysed"
verdict "dart analyze --fatal-infos --fatal-warnings and dart format --output=none --set-exit-if-changed are clean for all $ANALYSED Dart package(s) whose dependencies are resolved here$GAP"
