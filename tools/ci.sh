#!/usr/bin/env bash
# ===========================================================================
# ci.sh — the gate of this repository, in a pinned Linux container, on this machine.
#
# Nothing runs in a hosted CI. This script IS the CI, and it is a standing rule of this project
# rather than a workaround: the gate is the done-criterion for every step, so it has to run where a
# person can read it, break into it and fix it in the same minute.
#
# WHAT IT RUNS, per Dart package, is `dart pub get`, tools/checks/analysis.lint.sh and `dart test`.
# Four of this repository's five checks are tests under test/checks/ and arrive with the suite; the
# fifth is the analyzer and the formatter, which cannot be a test of the package they judge.
#
# WHY A CONTAINER AND NOT THE BARE HOST. What is pinned here is the Dart version, and that is now
# the whole of the reason. On a Windows host the suite meets whatever Dart happens to be on PATH,
# which is a different environment — the same check has answered differently on the two — and a
# host run also cannot see how a file behaves under a case-sensitive filesystem.
#
#   tools/ci.sh              build if needed, then run everything
#   tools/ci.sh --rebuild    force a fresh image
#   tools/ci.sh --shell      drop into the container, tree already in place
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

# THE PINS. Each was read from the source named beside it, on the date given. A version recalled
# from memory is as old as whoever recalled it, which is why the source is part of the record.
DEBIAN_TAG="trixie-slim"   # hub.docker.com/v2/repositories/library/debian/tags — current stable, read 2026-08-07
DART_VERSION="3.12.2"      # storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION — read 2026-08-07

_pin_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }
IMAGE="ansiwise-api-ci:$(_pin_slug "dart${DART_VERSION}-debian${DEBIAN_TAG}")"
PUB_CACHE_VOLUME="ansiwise-api-ci-pub-cache-$(_pin_slug "$DART_VERSION")"

REBUILD=0
SHELL_ONLY=0
for a in "$@"; do
  case "$a" in
    --rebuild) REBUILD=1 ;;
    --shell)   SHELL_ONLY=1 ;;
    *) echo "ci: FAIL — unknown option $a (expected --rebuild or --shell)" >&2; exit 2 ;;
  esac
done

command -v docker >/dev/null || { echo "ci: FAIL — docker is not on PATH" >&2; exit 1; }
docker info >/dev/null 2>&1  || { echo "ci: FAIL — the docker daemon is not reachable" >&2; exit 1; }

# Git Bash rewrites anything that looks like a unix path in an argument before the program sees it,
# so `-w /work` reaches docker as `C:/Program Files/Git/work` and a mount source arrives
# half-translated. Two different fixes are needed, because the two kinds of path are mangled in
# opposite directions: a HOST path has to become a native Windows one for docker to find it, and a
# CONTAINER-side path has to be left alone.
HOST_REPO="$REPO"
HOST_BUILD_CONTEXT="$HERE"
if command -v cygpath >/dev/null 2>&1; then
  HOST_REPO="$(cygpath -w "$REPO")"
  HOST_BUILD_CONTEXT="$(cygpath -w "$HERE")"
fi

if [ "$REBUILD" = 1 ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "ci: building $IMAGE"
  docker build -t "$IMAGE" \
    --build-arg "DEBIAN_TAG=$DEBIAN_TAG" \
    --build-arg "DART_VERSION=$DART_VERSION" \
    -f "$HOST_BUILD_CONTEXT/Dockerfile" "$HOST_BUILD_CONTEXT" \
    || { echo "ci: FAIL — image build failed" >&2; exit 1; }
fi

# Called as: run_in_container <docker flags> -- <command in the container>. The `--` is what keeps
# the command behind the image argument; without the split the command lands in front of the flags
# and docker reads its first word as the image name.
#
# MSYS_NO_PATHCONV is set on the call rather than exported, because the same rewriting is what
# makes `docker build` above find its context: turned off globally, the host paths would reach
# docker as unix paths it cannot open.
run_in_container() {
  local flags=()
  while [ "$1" != "--" ]; do flags+=("$1"); shift; done
  shift
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
  docker run --rm "${flags[@]}" \
    -v "$HOST_REPO:/host/ansiwise-api:ro" \
    -v "$PUB_CACHE_VOLUME:/root/.pub-cache" \
    -w /work "$IMAGE" "$@"
}

if [ "$SHELL_ONLY" = 1 ]; then
  exec run_in_container -it -- bash -c 'copy-in && cd /work/ansiwise-api && exec bash'
fi

# `bash -s`, not `bash -lc`: a login shell rebuilds PATH from /etc/profile and loses the dart image's
# own /usr/lib/dart/bin, so `dart` is then not a command.
run_in_container -i -- bash -s <<'INNER'
# -e is deliberately off here and only here. Every package and both steps have to run even after an
# earlier one went red, or one failure hides the rest and the next run finds a second problem that
# was there all along.
set -uo pipefail

copy-in || { echo "ci: FAIL — could not copy the tree into the container" >&2; exit 1; }
cd /work/ansiwise-api

# Which packages exist is discovered rather than listed, so a package that lands on disk without
# anybody adding it here is still analysed and still tested.
. tools/lib/dart-packages.sh

FAILED=""

while IFS= read -r package; do
  name="${package#/work/ansiwise-api/}"
  cd "$package" || { FAILED="$FAILED $name/cd"; continue; }

  echo; echo "########## $name — dart pub get ##########"
  if ! dart pub get; then
    # Nothing below can say anything true without a resolved package config: the analyzer reports
    # every import as unresolved and the failure reads as a tree full of defects.
    FAILED="$FAILED $name/pub-get"
    cd /work/ansiwise-api || exit 1
    continue
  fi

  echo; echo "########## $name — tools/checks/analysis.lint.sh ##########"
  bash /work/ansiwise-api/tools/checks/analysis.lint.sh || FAILED="$FAILED $name/analysis"

  echo; echo "########## $name — dart test ##########"
  if [ -d test ]; then
    dart test || FAILED="$FAILED $name/test"
  else
    echo "no test/ directory in $name"
  fi

  cd /work/ansiwise-api || exit 1
done < <(dart_package_dirs /work/ansiwise-api)

echo; echo "########## verdict ##########"
if [ -n "$FAILED" ]; then
  echo "ci: FAIL —$FAILED" >&2
  exit 1
fi
echo "ci: OK — every check green"
INNER
