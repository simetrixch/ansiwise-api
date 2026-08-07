#!/usr/bin/env bash
# ===========================================================================
# ci.sh — every check of this repository, in a pinned Linux container, on this machine.
#
# Nothing runs in a hosted CI. This script IS the CI, and it is a standing rule of this project
# rather than a workaround: the checks are the done-criterion for every step, so they have to run
# where a person can read them, break into them and fix them in the same minute.
#
# WHY A CONTAINER AND NOT THE BARE HOST. The code is written for Linux and runs on Linux
# everywhere else. On a Windows host it meets Git Bash and whatever Dart happens to be
# on PATH, which is a different environment: the same check has answered differently on the two,
# and a host run also cannot see how a file behaves under a case-sensitive filesystem.
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
#
# DIGITA_CI=1 is how anything inside knows where it is. tools/run-checks.sh is the only reader
# today: without it a host run looks the same as this one, and the two do not always answer the
# same.
run_in_container() {
  local flags=()
  while [ "$1" != "--" ]; do flags+=("$1"); shift; done
  shift
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
  docker run --rm "${flags[@]}" \
    -e DIGITA_CI=1 \
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
# -e is deliberately off here and only here. Every package and every check has to run even after an
# earlier one went red, or one failure hides the rest and the next run finds a second problem that
# was there all along.
set -uo pipefail

copy-in || { echo "ci: FAIL — could not copy the tree into the container" >&2; exit 1; }
cd /work/ansiwise-api

# The same discovery the checks use, so ci.sh and a layering check can never disagree about which
# packages exist.
. tools/lib/dart-packages.sh

FAILED=""

while IFS= read -r package; do
  name="${package#/work/ansiwise-api/}"
  cd "$package" || { FAILED="$FAILED $name/cd"; continue; }

  # A package that depends on the Flutter SDK cannot be resolved, analyzed or tested by the bare
  # `dart` tool: `sdk: flutter` is a source only `flutter pub get` knows how to reach. Which tool a
  # package needs is read from its own pubspec rather than from its name, so a second Flutter
  # package needs no change here.
  if grep -qE '^\s+sdk:\s+flutter\s*$' pubspec.yaml; then
    TOOL=flutter
  else
    TOOL=dart
  fi

  echo; echo "########## $name — $TOOL pub get ##########"
  if ! "$TOOL" pub get; then
    # Nothing below can say anything true without a resolved package config: the analyzer reports
    # every import as unresolved and the failure reads as a tree full of defects.
    FAILED="$FAILED $name/pub-get"
    cd /work/ansiwise-api || exit 1
    continue
  fi

  echo; echo "########## $name — $TOOL analyze --fatal-infos ##########"
  "$TOOL" analyze --fatal-infos || FAILED="$FAILED $name/analyze"

  echo; echo "########## $name — dart format ##########"
  dart format --output=none --set-exit-if-changed . || FAILED="$FAILED $name/format"

  echo; echo "########## $name — $TOOL test ##########"
  if [ -d test ]; then
    "$TOOL" test || FAILED="$FAILED $name/test"
  else
    echo "no test/ directory in $name"
  fi

  cd /work/ansiwise-api || exit 1
done < <(dart_package_dirs /work/ansiwise-api)

echo; echo "########## ansiwise-api — tools/run-checks.sh ##########"
bash tools/run-checks.sh || FAILED="$FAILED run-checks"

echo; echo "########## verdict ##########"
if [ -n "$FAILED" ]; then
  echo "ci: FAIL —$FAILED" >&2
  exit 1
fi
echo "ci: OK — every check green"
INNER
