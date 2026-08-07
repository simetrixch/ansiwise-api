#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# ===========================================================================
# api-purity — this framework names no platform, anywhere, with no exemption.
#
# ansiwise-api is a step engine, three modes, a run record and four ports. It knows how to run a
# declared program against a machine and nothing whatever about what is being deployed. Everything
# of that kind lives in a plugin, in a repository of its own, and the dependency points one way.
#
# Such knowledge does not arrive as a dependency, where a reviewer would meet it in the pubspec. It
# arrives one word at a time, in a doc comment that explains a port by the tool the author had in
# mind and in a test fixture that runs a real command because a real command was handy. Both read as
# illustration on the day they are written and as specification a year later. So the scan is over
# every byte of the package — code, comment and fixture alike — and not over its imports.
#
# THERE IS NO EXEMPT DIRECTORY. While the two halves shared a package, four paths had to be carved
# out of this scan, and every one of them was a place the rule did not hold. The split removed the
# platform half, so the carve-outs went with it: lib/, test/, bin/ and programs/ are scanned to the
# byte, and a hit is a hit wherever it is.
#
# tools/ is not scanned, and that is the harness rather than a loophole: this check has to name the
# words it forbids in order to search for them, and the container has to name the tools it installs
# in order to install them. Nothing under tools/ is compiled into the framework or shipped with it.
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/verdict.sh
. "$HERE/../lib/verdict.sh"

# What the framework may not name. The first six are the platform's own components; the rest are the
# words a particular deployment uses for the things it deploys. A framework that knows any of them
# has stopped being one, and the owner's requirement — it must know nothing of digita — is this list.
#
# Matched case-insensitively, because they appear as prose ("no Vault") as often as identifiers, and
# word-anchored so that a snapshot — a captured state, which this framework may legitimately speak
# of — is not read as `snap`.
PLATFORM_WORDS='microk8s|vault|argocd|cloudflare|helm|snap|digita|tenant|consumer|zot|tekton|kubectl|netplan|hetzner|authentik'

# What is scanned: the package. Named one directory at a time rather than "the repository minus
# tools", so adding a directory is a decision somebody makes here rather than a silent widening.
SCANNED_PATHS=(lib test bin programs)

# Every occurrence under <root> in the scanned paths, as <file>:<line>:<text>. Takes a root rather
# than reading $REPO, so the counter-probe below can drive the same scan over a tree it planted.
scan_for_platform_words() {
  local root="$1" path out rc=0
  for path in "${SCANNED_PATHS[@]}"; do
    [ -d "$root/$path" ] || continue
    rc=0
    out="$(grep -rIiwnE \
          --exclude-dir=.dart_tool --exclude-dir=build --exclude-dir=.git \
          -e "$PLATFORM_WORDS" -- "$root/$path")" || rc=$?
    # grep answers 1 for "no match", which is the good answer here, and 2 for a real error. Under
    # `set -e` both would abort the check, so the status is read rather than inherited.
    if [ "$rc" -gt 1 ]; then
      echo "api-purity: grep failed with status $rc over $root/$path" >&2
      return "$rc"
    fi
    [ -n "$out" ] && printf '%s\n' "$out"
  done
  return 0
}

SCANNED=0
for path in "${SCANNED_PATHS[@]}"; do
  [ -d "$REPO/$path" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    SCANNED=$((SCANNED + 1))
  done < <(grep -rIl '' --exclude-dir=.dart_tool --exclude-dir=build --exclude-dir=.git -- "$REPO/$path")
done

[ "$SCANNED" -gt 0 ] || finding "nothing was scanned — none of ${SCANNED_PATHS[*]} is in this tree, so a pass here would mean nothing"

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  finding "${hit#"$REPO/"}"
done <<< "$(scan_for_platform_words "$REPO")"

# A check that cannot go red proves nothing about the tree it passes on. The same scan runs a second
# time over a scratch tree carrying planted occurrences; if it comes back empty there, the scan is
# broken and the verdict above it means nothing.
PROBE="$(mktemp -d)"
trap 'rm -rf "$PROBE"' EXIT
mkdir -p "$PROBE/lib/src/engine" "$PROBE/test/config" "$PROBE/tools/checks"
printf '%s\n' '/// Runs helm upgrade and waits for ArgoCD to sync it.' > "$PROBE/lib/planted.dart"
printf '%s\n' 'const String snapshotOfState = "a captured state";' > "$PROBE/lib/innocent.dart"
# The two places that used to be carved out. Both must now report, or the exemptions have grown back.
printf '%s\n' '/// Reads the tenant out of Vault.' > "$PROBE/lib/src/engine/deep.dart"
printf '%s\n' "const String argv = 'microk8s status';" > "$PROBE/test/config/planted_in_test.dart"
# And the one place that must NOT: the harness, which has to name what it forbids.
printf '%s\n' "WORDS='vault|helm'" > "$PROBE/tools/checks/planted_in_tools.sh"

PROBE_HITS="$(scan_for_platform_words "$PROBE")"
if ! grep -q 'lib/planted\.dart:' <<< "$PROBE_HITS"; then
  finding "counter-probe: a planted file naming helm and ArgoCD was not reported, so this scan cannot go red"
fi
if grep -q 'innocent\.dart:' <<< "$PROBE_HITS"; then
  finding "counter-probe: the word-anchoring is gone — 'snapshotOfState' was reported as an occurrence of 'snap'"
fi
if ! grep -q 'deep\.dart:' <<< "$PROBE_HITS"; then
  finding "counter-probe: a planted file deep under lib/src/ was not reported, so an exempt path has grown back"
fi
if ! grep -q 'planted_in_test\.dart:' <<< "$PROBE_HITS"; then
  finding "counter-probe: a planted file under test/ was not reported, so test/ has fallen out of scope"
fi
if grep -q 'planted_in_tools\.sh:' <<< "$PROBE_HITS"; then
  finding "counter-probe: tools/ was scanned, so this check reports itself and can never pass"
fi

note "scanned $SCANNED file(s) under ${SCANNED_PATHS[*]} for: ${PLATFORM_WORDS//|/, }"
note "nothing is exempt — the platform half is a separate repository, so no path needs carving out"
verdict "this framework names no platform in ${SCANNED_PATHS[*]}, in code, comment or fixture — none of: ${PLATFORM_WORDS//|/, }"
