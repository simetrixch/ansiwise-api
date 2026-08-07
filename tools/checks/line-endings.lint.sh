#!/usr/bin/env bash
# ===========================================================================
# Every file this repository declares as LF is LF in the working copy too.
#
# .gitattributes already forces LF in the repository and on checkout, and it says why: a shell
# script that reaches a Linux host with CRLF fails as `bad interpreter: /usr/bin/env bash^M`.
#
# What it does NOT protect is the WORKING COPY on a Windows machine. tools/ci.sh copies the working
# copy into the container, not a fresh checkout — so an editor or a script that writes CRLF puts a
# broken shebang in front of the container without git ever seeing it.
#
# That is not a theoretical failure. It happened: two checks were patched by a Python script, which
# writes \r\n by default on Windows, and in the container the kernel looked for `bash\r`, found
# nothing, and fell back to `sh` — where `set -o pipefail` does not exist. Both checks reported a
# shell error instead of a finding, which reads as a broken tree rather than a broken file.
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/verdict.sh
. "$HERE/../lib/verdict.sh"

ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

scanned=0

# The suffixes .gitattributes declares eol=lf, plus every file with a shebang whatever it is called
# — tools/ops/sync-versions on legacy-master had no suffix, and the next one will not either.
while IFS= read -r file; do
  [ -f "$file" ] || continue
  case "$file" in
    ./.git/*|*/.dart_tool/*|./bin/*) continue ;;
  esac

  keep=no
  case "$file" in
    *.sh|*.bash|*.yaml|*.yml|*.tpl|*.json|*.conf|*.config|*.example|*.dart) keep=yes ;;
    *) head -c 2 "$file" 2>/dev/null | grep -q '#!' && keep=yes ;;
  esac
  [ "$keep" = yes ] || continue

  scanned=$((scanned + 1))
  if grep -qU $'\r' "$file" 2>/dev/null; then
    finding "$file carries CRLF, and this repository declares it LF"
  fi
done < <(find . -type f)

note "scanned $scanned file(s) for carriage returns"

# The counter-probe. A scan that stopped finding files would report a clean tree, which is the one
# outcome a check must never produce by accident.
if [ "$scanned" -lt 20 ]; then
  finding "only $scanned file(s) were scanned, so this check measured almost nothing"
fi

verdict "every file this repository declares as LF is LF in the working copy, so the container gets a readable shebang"
