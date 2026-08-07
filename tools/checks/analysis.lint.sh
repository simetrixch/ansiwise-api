#!/usr/bin/env bash
# ===========================================================================
# analysis — the analyzer and the formatter, over one Dart package.
#
# `dart analyze --fatal-infos --fatal-warnings` with this repository's analysis_options is not a
# style pass. strict-casts, strict-inference and strict-raw-types are on, so an implicit cast, an
# inferred `dynamic` and a raw generic are each a type the author never chose and each stops the
# build; unused_import, unused_local_variable and dead_code are raised to errors, which is the
# no-leftovers rule of this project enforced by a tool rather than by a reviewer. `dart format
# --set-exit-if-changed` is what keeps a diff about the change instead of about the whitespace.
#
# THIS IS THE ONE CHECK OF THIS REPOSITORY THAT CANNOT BE A `dart test`. A test runs inside the
# package it would judge, so it is compiled by the very analysis it is meant to fail on: either the
# package analyses, and the test has nothing to report, or it does not, and the test never starts.
# Every other check lives under test/checks/ and comes in with the suite.
#
# IT NEEDS NO COUNTER-PROBE, and that is a property of what is left rather than an exemption. The
# shell this replaces had one because it PARSED the analyzer's output with grep, so a scan that
# stopped matching would have reported a clean package. Here each tool's exit status IS the verdict
# and there is nothing in between to break.
#
# `--output=none` writes nothing, so a red run leaves the tree exactly as it found it: a check that
# repaired what it measures would be green the second time for having changed the thing it judged.
#
#   bash tools/checks/analysis.lint.sh            the package in the current directory
#   bash tools/checks/analysis.lint.sh <package>  the package in <package>
# ===========================================================================
set -euo pipefail

cd "${1:-.}"

dart analyze --fatal-infos --fatal-warnings
dart format --output=none --set-exit-if-changed .
