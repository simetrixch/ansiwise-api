#!/usr/bin/env bash
# Compiles the binary that gets copied to a machine.
#
# The client reaches a fresh Ubuntu with a username and a password and nothing else on it — no Dart,
# no checkout. So what travels is one self-contained executable, and this is where it comes from.
#
# The output is bin/ at the repository root rather than inside the package, because it is a build
# artifact and not source: it is what gets deployed, and it is gitignored for the same reason.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

target="${1:-bin/ansiwise-api}"
mkdir -p "$(dirname "$target")"

# Compiled from inside the package, because that is where its pubspec and its .dart_tool are. A
# compile from the repository root resolves no package: imports at all.
(cd ansiwise-api && dart compile exe bin/ansiwise_api.dart -o "../$target")

printf 'built %s (%s)\n' "$target" "$(dart --version 2>&1 | sed 's/^Dart SDK version: //;s/ (.*//')"
