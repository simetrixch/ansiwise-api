#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# ===========================================================================
# naming — the abolished words appear in no name.
#
# WHAT WAS ABOLISHED IS A PROGRAM NAME, NOT A VERB — and this distinction is the whole check, so it
# is written down here before the code rather than left to be re-derived by whoever reads it next.
#
# The shell implementation had `install.sh` and `setup.sh`: two programs split along a line nobody
# could name, which is how one of them came to do five unrelated things. The verbs for OUR programs
# are `deploy` and `onboard`, and what is deployed or onboarded is a `host`, a `branch`, a
# `cluster`, `gitops` or the `controller`. So `install` and `setup` are forbidden where a program or
# a sub-command is named, and there only.
#
# `install` as the name of what a command does is NOT abolished and must not be reported. A step
# that runs `apt-get install` is called install_packages.dart because that is the word the software
# itself uses, and the naming law of this project is to take that word rather than invent one. A
# check that forbade the substring would rename the step to something that no longer says what it
# runs — which is the failure this check exists to prevent, arriving from the other side.
#
# THE ONE UNCONDITIONAL WORD IS `desktop`, in a file name, a directory name or a sub-command alike.
# It is not a bad name, it is a false one: one Flutter app runs on web, on a phone, on a tablet and
# on a laptop, so `desktop` states a platform the code inside it does not have. There is no position
# in which that becomes true, so there is no position in which it is allowed.
#
# A word can hide in three places a compiler never reads: a file name, a directory name, and the
# string a sub-command answers to on the command line. Those are what this scans.
#
# SCOPE IS THE NEW CODE. apps/, charts/, argocd/, cluster/, platform/ and templates/ are carried
# over: they are Helm charts and ArgoCD manifests where `helm install`, `argocd` setup jobs and
# upstream file names occur legitimately and are not ours to rename. The scan is the Dart packages
# and tools/.
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/verdict.sh
. "$HERE/../lib/verdict.sh"
# shellcheck source=../lib/dart-packages.sh
. "$HERE/../lib/dart-packages.sh"

# Every file and directory name under <root> carrying an abolished word, as <path> — <why>.
#
# Four rules. `desktop` is the only substring test, for the reason above; the other three ask where
# the name sits before they ask what it says, which is what keeps install_packages.dart out of the
# findings. Every test is case-insensitive, because `Setup` is the same word wearing a disguise, and
# the tests are done with bash pattern matching rather than a pipe into `grep -q`, because grep
# closes the pipe on its first match and, under pipefail, the pipeline then reports failure for a
# name that WAS found.
scan_for_abolished_names() {
  local root="$1" path base lower
  [ -d "$root" ] || return 0
  while IFS= read -r path; do
    base="$(basename "$path")"
    lower="${base,,}"

    # `desktop`, unconditionally, wherever it appears in a name.
    case "$lower" in
      *desktop*) printf '%s — desktop names a platform the code does not have\n' "$path"; continue ;;
    esac

    if [ -d "$path" ]; then
      # A directory CALLED install or setup is the old split by another route: it collects whatever
      # someone decided belongs to installing, which is the grouping that had no name.
      case "$lower" in
        install|setup) printf '%s — a directory named for the abolished program, not for what is in it\n' "$path" ;;
      esac
      continue
    fi

    # The two shell programs themselves, and a Dart file that would inherit their names.
    case "$lower" in
      install.sh|setup.sh|install.dart|setup.dart)
        printf '%s — the abolished program name; the verbs are deploy and onboard\n' "$path"
        continue
        ;;
    esac

    # A program file is one that lives in a programs/ directory: its name is what an operator picks
    # from a list, so it is named like a sub-command and judged like one.
    case "$path" in
      */programs/*)
        case "$lower" in
          install*|setup*)
            printf '%s — a program named install/setup; the verbs are deploy and onboard\n' "$path"
            continue
            ;;
        esac
        ;;
    esac
  done < <(find "$root" \
      \( -name .git -o -name .dart_tool -o -name build -o -name node_modules -o -name Pods \) -prune \
      -o \( -type f -o -type d \) -print | sort)
  return 0
}

# Every Dart sub-command under <root> whose name carries an abolished word, as <file>:<line>:<name>.
#
# A sub-command is declared in one of two shapes, and both are read out of the source rather than
# guessed at: `parser.addCommand('deploy-host')` for a bare ArgParser, and `String get name =>
# 'deploy-host'` for a Command subclass of package:args. A word that reaches the command line is
# what an operator types and reads in help output, so it outlives every rename of the file behind
# it.
#
# A sub-command is a program name, so `install`, `setup` and anything beginning with them is out —
# `install`, `install-cluster`, `setup`. `desktop` is out wherever it sits in the string.
scan_for_abolished_subcommands() {
  local root="$1" file out rc hit line_number literal
  [ -d "$root" ] || return 0
  while IFS= read -r file; do
    rc=0
    out="$(grep -nE "addCommand\([[:space:]]*['\"]|get name[[:space:]]*=>[[:space:]]*['\"]" -- "$file")" || rc=$?
    if [ "$rc" -gt 1 ]; then
      echo "naming: grep failed with status $rc over $file" >&2
      return "$rc"
    fi
    [ -n "$out" ] || continue
    while IFS= read -r hit; do
      line_number="${hit%%:*}"
      literal="$(sed -nE "s/.*['\"]([^'\"]*)['\"].*/\1/p" <<< "${hit#*:}")"
      case "${literal,,}" in
        install*|setup*|*desktop*) printf '%s:%s:%s\n' "$file" "$line_number" "$literal" ;;
      esac
    done <<< "$out"
  done < <(dart_source_files "$root")
  return 0
}

ROOTS=("$REPO/tools")
while IFS= read -r dir; do
  ROOTS+=("$dir")
done < <(dart_package_dirs "$REPO")

for root in "${ROOTS[@]}"; do
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    finding "${hit#"$REPO/"}"
  done <<< "$(scan_for_abolished_names "$root")"
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    finding "sub-command carries an abolished word: ${hit#"$REPO/"}"
  done <<< "$(scan_for_abolished_subcommands "$root")"
done

# Both scans get a planted violation and a correct neighbour, so a scan that reported everything is
# caught as surely as one that reports nothing. The correct neighbours are the point of this probe
# now: install_packages.dart and deploy-host.yaml are exactly what a substring match would eat, so
# they are what reports the check having been "simplified" back into one.
PROBE="$(mktemp -d)"
trap 'rm -rf "$PROBE"' EXIT
mkdir -p "$PROBE/setup" "$PROBE/lib/desktop" "$PROBE/programs"
printf 'const String x = 1;\n' > "$PROBE/setup/whatever.dart"
printf 'const String x = 2;\n' > "$PROBE/lib/desktop/shell.dart"
printf '#!/bin/sh\n'           > "$PROBE/install.sh"
printf 'name: p\n'             > "$PROBE/programs/setup-cluster.yaml"
printf 'const String x = 3;\n' > "$PROBE/lib/deploy_host.dart"
printf 'const String x = 4;\n' > "$PROBE/lib/install_packages.dart"
printf 'name: p\n'             > "$PROBE/programs/deploy-host.yaml"
printf '%s\n' \
  "  String get name => 'install';" \
  "  String get name => 'install-cluster';" \
  "  String get name => 'deploy-cluster';" \
  "    parser.addCommand('setup');" \
  "    parser.addCommand('desktop-shell');" \
  "    parser.addCommand('onboard');" \
  > "$PROBE/lib/commands.dart"

# The findings read `<path> — <why>`, so a planted path is asserted at the head of a line and an
# allowed one is looked for anywhere: an allowed name must not appear at all.
PROBE_NAMES="$(scan_for_abolished_names "$PROBE")"
for planted in setup lib/desktop install.sh programs/setup-cluster.yaml; do
  if ! grep -qE "^${PROBE//./\\.}/${planted//./\\.} " <<< "$PROBE_NAMES"; then
    finding "counter-probe: the planted name $planted was not reported, so the name scan cannot go red"
  fi
done
for allowed in deploy_host.dart install_packages.dart deploy-host.yaml; do
  if grep -q "$allowed" <<< "$PROBE_NAMES"; then
    finding "counter-probe: $allowed names the command it runs and was reported anyway — the name scan has collapsed back into a substring match"
  fi
done

PROBE_COMMANDS="$(scan_for_abolished_subcommands "$PROBE")"
for planted in install install-cluster setup desktop-shell; do
  if ! grep -qE ":${planted}$" <<< "$PROBE_COMMANDS"; then
    finding "counter-probe: the planted sub-command '$planted' was not reported, so the sub-command scan cannot go red"
  fi
done
for allowed in deploy-cluster onboard; do
  if grep -qE ":${allowed}$" <<< "$PROBE_COMMANDS"; then
    finding "counter-probe: the sub-command '$allowed' carries no abolished word and was reported anyway"
  fi
done

note "scanned ${#ROOTS[@]} root(s): ${ROOTS[*]#"$REPO/"}"
verdict "no program file, directory or Dart sub-command is named install or setup, nothing is named desktop, and a step named for the command it runs is left alone"
