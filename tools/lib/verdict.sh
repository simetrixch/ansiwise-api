# The verdict protocol every check under tools/checks/ speaks.
#
# tools/run-checks.sh interprets exactly ONE line of a check's output: the verdict line,
# `<check file name>: OK|SKIP|FAIL — <why>`, anchored at the start of a line. Everything else a
# check prints is for a person reading a red run and is never parsed.
#
# The anchoring is the mechanism. A runner that decided by searching the whole output for the
# word SKIP reported a passing check as skipped, because one of that check's own assertion texts
# mentioned skipping. Only a line that begins with the check's own file name and one of the three
# words is a verdict; a check may write those words anywhere else without changing what it said.
#
# This file is sourced, never executed. It sets no shell options: a library that turns on `set -e`
# changes the behaviour of code it cannot see, and every check sets its own.

# The name a check answers to. Taken from the file the shell was started with, so the verdict line
# always carries the file name the runner globbed and a person can grep for.
CHECK_NAME="$(basename "$0")"

# How many things this check found wrong. `verdict` reads it and nothing else writes it.
FINDINGS=0

# Records one thing that is wrong, and prints it where a person will see it above the verdict.
finding() {
  FINDINGS=$((FINDINGS + 1))
  printf '  finding: %s\n' "$*"
}

# Prints something a person needs in order to read the verdict — what was scanned, what could not
# be measured, which half of a check found nothing to bind to. Never affects the verdict.
note() {
  printf '  %s\n' "$*"
}

# Ends the check as inapplicable. The reason is mandatory: a run that is green only because
# everything skipped has to be readable as such from the output alone.
verdict_skip() {
  printf '%s: SKIP — %s\n' "$CHECK_NAME" "$*"
  exit 0
}

# Ends the check. The argument states what was proven, not what was looked for — it is what the
# runner reprints on the summary line, so it has to stand on its own.
verdict() {
  if [ "$FINDINGS" -gt 0 ]; then
    printf '%s: FAIL — %d finding(s) above; %s\n' "$CHECK_NAME" "$FINDINGS" "$*" >&2
    exit 1
  fi
  printf '%s: OK — %s\n' "$CHECK_NAME" "$*"
  exit 0
}
