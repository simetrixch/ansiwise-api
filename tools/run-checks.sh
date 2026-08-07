#!/usr/bin/env bash
# ===========================================================================
# run-checks.sh — every check under tools/checks/, one verdict.
#
# A check is named <subject>.<kind>.sh and decides one thing about this tree. Red means the tree
# is not in a finishable state.
#
# THE MEMBER SET IS DISCOVERED BY GLOB, never enumerated here. A new check is picked up the moment
# its file lands, so the set cannot silently shrink to the subset someone remembered to list. The
# same reason makes a *.sh under checks/ that is neither *.lint.sh nor *.test.sh a hard failure
# rather than a file the glob quietly walks past: an ignored member is the shrink arriving by
# another door.
#
# A MEMBER THAT EXITS NON-ZERO FOR ANY REASON COUNTS AS FAIL. A check that cannot run has not
# passed, and there is no exit status a check can return that this runner reads kindly.
#
# A SKIP IS DECLARED BY THE MEMBER'S OWN VERDICT LINE — `<name>: SKIP — why`, anchored at the start
# of a line — and by nothing else. Searching the whole output for the word would count a check
# whose assertion texts merely mention skipping, which is how a passing run was once reported as
# skipped. For the same reason a member that exits 0 without writing a verdict line at all is
# FAIL: it did not say what it decided.
#
# Members inherit this shell's environment, so a per-member override set on the command line
# reaches the member unchanged. They run sequentially, in sorted order.
#
# WHERE THIS RUNS DECIDES WHAT IT MEASURES. tools/ci.sh is the local CI: a pinned Linux container
# holding this repository under /work, with one Dart, one helm, one kubectl and one yq. This
# runner is what ci.sh calls inside that container, and it also runs on the developer's host,
# where the checks meet whatever happens to be on PATH. A host run says so, before the wait and
# again in the verdict. It is not refused — typing this while working on one check is what it is
# for.
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKS="$HERE/checks"

# Set by tools/ci.sh on the container it starts, and by nothing else.
if [ "${DIGITA_CI:-}" = 1 ]; then
  WHERE="in the pinned container"
else
  WHERE="on this host, NOT in the pinned container — tools/ci.sh is the faithful run"
  echo "run-checks: running ${WHERE}"
fi

[ -d "$CHECKS" ] || { echo "run-checks: FAIL — $CHECKS does not exist" >&2; exit 1; }

shopt -s nullglob
MEMBERS=("$CHECKS"/*.lint.sh "$CHECKS"/*.test.sh)
ALL_SCRIPTS=("$CHECKS"/*.sh)
shopt -u nullglob

STRAYS=()
for f in "${ALL_SCRIPTS[@]}"; do
  case "$f" in
    *.lint.sh|*.test.sh) ;;
    *) STRAYS+=("${f##*/}") ;;
  esac
done
if [ ${#STRAYS[@]} -gt 0 ]; then
  echo "run-checks: FAIL — ${STRAYS[*]} under $CHECKS is neither *.lint.sh nor *.test.sh, so the glob would never run it" >&2
  exit 1
fi

if [ ${#MEMBERS[@]} -eq 0 ]; then
  echo "run-checks: FAIL — no checks found in $CHECKS (expected *.lint.sh / *.test.sh)" >&2
  exit 1
fi

mapfile -t MEMBERS < <(printf '%s\n' "${MEMBERS[@]}" | sort)

PASSED=(); SKIPPED=(); FAILED=()
DETAIL=""

printf '\n=== %d check(s) discovered under %s ===\n' "${#MEMBERS[@]}" "${CHECKS}"

for m in "${MEMBERS[@]}"; do
  name="${m##*/}"

  rc=0
  out="$(bash "$m" 2>&1)" || rc=$?

  # The member's own verdict line, taken from the collected output rather than from a pipe the
  # member is still writing into: a `grep -q` at the end of a live pipeline kills the writer and,
  # under pipefail, reports the pipeline as failed for a line that WAS found.
  verdict_line=""
  if verdict_line="$(grep -E "^${name//./\\.}: (OK|SKIP|FAIL)( |$)" <<< "$out" | tail -n 1)"; then :; fi

  if [ "$rc" -ne 0 ]; then
    FAILED+=("$name")
    printf '  [FAIL] %s\n' "${verdict_line:-$name: exited $rc without a verdict line}"
    DETAIL="${DETAIL}
--- ${name} ---
${out}
"
  elif [ -z "$verdict_line" ]; then
    FAILED+=("$name")
    printf '  [FAIL] %s: exited 0 but wrote no verdict line\n' "$name"
    DETAIL="${DETAIL}
--- ${name} ---
${out}
"
  elif [[ "$verdict_line" == "$name: SKIP"* ]]; then
    SKIPPED+=("$name")
    printf '  [skip] %s\n' "$verdict_line"
  else
    PASSED+=("$name")
    printf '  [pass] %s\n' "$verdict_line"
  fi
done

if [ -n "$DETAIL" ]; then
  printf '\n=== output of the red check(s) ===\n%s' "$DETAIL"
fi

printf '\n=== summary ===\n'
printf '  discovered  %d\n' "${#MEMBERS[@]}"
printf '  pass        %d  %s\n' "${#PASSED[@]}"  "${PASSED[*]}"
printf '  skip        %d  %s\n' "${#SKIPPED[@]}" "${SKIPPED[*]}"
printf '  fail        %d  %s\n' "${#FAILED[@]}"  "${FAILED[*]}"
printf '\n'

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "run-checks: FAIL — ${#FAILED[@]} of ${#MEMBERS[@]} check(s) red, ${WHERE}" >&2
  exit 1
fi

echo "run-checks: OK — ${#MEMBERS[@]} check(s), ${#PASSED[@]} passed, ${#SKIPPED[@]} skipped, ${WHERE}"
