#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# ===========================================================================
# layering — no import points outward.
#
# Two directions have to hold, and neither is visible in a diff that adds one import line.
#
# INSIDE a package, by directory name:
#
#   presentation -> application -> domain          infrastructure -> domain
#
# domain is what the system is; it may reach nothing. application orchestrates domain.
# presentation renders application. infrastructure implements the domain's ports against a real
# machine and knows nothing of the two above it. The moment domain imports infrastructure the
# arrow reverses: the thing that was meant to be testable without a machine now needs one, and
# every test above it drags a real process along.
#
# ACROSS packages:
#
#   deployment -> ansiwise-api      digita-cloud-client -> ansiwise-api
#
# ansiwise-api imports neither. It is the framework, it is meant to be lifted into its own
# repository, and one import of a sibling ends that. The rule is enforced as "the api package
# imports no other package of this workspace", derived from each package's own pubspec name, so a
# package that lands later is covered on the day it lands rather than on the day someone
# remembers to add it here.
#
# A directory that names none of the four layers — the engine, the model, the step catalogue — is
# not judged: the rule is about the four names, and inventing a fifth arrow here would be a rule
# nobody wrote down.
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/verdict.sh
. "$HERE/../lib/verdict.sh"
# shellcheck source=../lib/dart-packages.sh
. "$HERE/../lib/dart-packages.sh"

API_DIRECTORY_NAME="ansiwise-api"
LAYER_NAMES='domain application presentation infrastructure'

# The import and export URIs of a Dart file, one per line. `part` is not read: a part is the same
# library as its parent and cannot cross a boundary the parent has not already crossed.
dart_import_uris() {
  sed -nE "s/^[[:space:]]*(import|export)[[:space:]]+'([^']+)'.*/\2/p;
           s/^[[:space:]]*(import|export)[[:space:]]+\"([^\"]+)\".*/\2/p" "$1"
}

# Collapses . and .. textually. The target of an import may not exist — a broken import is the
# analyzer's finding, not this one — so the path is never resolved against the filesystem.
normalize_path() {
  local raw="$1" seg joined=""
  local -a segs out=()
  IFS='/' read -r -a segs <<< "$raw"
  for seg in "${segs[@]}"; do
    case "$seg" in
      ''|.) ;;
      ..) if [ ${#out[@]} -gt 0 ]; then unset 'out[${#out[@]}-1]'; fi ;;
      *) out+=("$seg") ;;
    esac
  done
  for seg in "${out[@]}"; do
    joined="$joined/$seg"
  done
  printf '%s' "$joined"
}

# The layer a path sits in, or empty. The LAST layer-named segment wins, so a file under
# lib/src/domain/ is domain even when the package directory happens to carry a layer word.
layer_of_path() {
  local seg layer=""
  local -a segs
  IFS='/' read -r -a segs <<< "$1"
  for seg in "${segs[@]}"; do
    case " $LAYER_NAMES " in
      *" $seg "*) layer="$seg" ;;
    esac
  done
  printf '%s' "$layer"
}

# Whether a file in layer $1 may import a file in layer $2.
layer_allows() {
  case "$1:$2" in
    domain:domain) return 0 ;;
    application:application|application:domain) return 0 ;;
    presentation:presentation|presentation:application|presentation:domain) return 0 ;;
    infrastructure:infrastructure|infrastructure:domain) return 0 ;;
    *) return 1 ;;
  esac
}

# Every import that points outward under <root>, one finding per line. Takes a root and builds its
# own package map from it, so the counter-probe below can drive the whole machinery over a tree it
# planted rather than over this repository.
scan_layering() {
  local root="$1"
  local -A dir_of_package=()
  local dir name file uri target target_package source_package source_layer target_layer rest api_package=""

  while IFS= read -r dir; do
    name="$(dart_package_name "$dir")"
    [ -n "$name" ] || continue
    dir_of_package["$name"]="$dir"
    if [ "$(basename "$dir")" = "$API_DIRECTORY_NAME" ]; then
      api_package="$name"
    fi
  done < <(dart_package_dirs "$root")

  # The package a file belongs to: the package directory that is the longest prefix of its path.
  # Longest, because a package may sit inside another package's tree (a Flutter example app does).
  _package_of_file() {
    local file="$1" candidate best="" best_length=0
    for candidate in "${!dir_of_package[@]}"; do
      case "$file" in
        "${dir_of_package[$candidate]}"/*)
          if [ ${#dir_of_package[$candidate]} -gt "$best_length" ]; then
            best="$candidate"
            best_length=${#dir_of_package[$candidate]}
          fi
          ;;
      esac
    done
    printf '%s' "$best"
  }

  for name in "${!dir_of_package[@]}"; do
    while IFS= read -r file; do
      source_package="$(_package_of_file "$file")"
      source_layer="$(layer_of_path "$file")"
      while IFS= read -r uri; do
        [ -n "$uri" ] || continue
        target=""
        target_package=""
        case "$uri" in
          dart:*)
            # The SDK carries no layer and is not a package of this workspace.
            continue
            ;;
          package:*)
            rest="${uri#package:}"
            target_package="${rest%%/*}"
            rest="${rest#*/}"
            # A package name this workspace does not know is a third-party dependency: it has no
            # layers here and no arrow to point the wrong way.
            [ -n "${dir_of_package[$target_package]:-}" ] || continue
            target="${dir_of_package[$target_package]}/lib/$rest"
            ;;
          *)
            target_package="$source_package"
            target="$(normalize_path "$(dirname "$file")/$uri")"
            ;;
        esac

        if [ -n "$api_package" ] && [ "$source_package" = "$api_package" ] && [ "$target_package" != "$api_package" ]; then
          printf '%s: imports %s — the framework package %s may import no other package of this workspace\n' \
            "$file" "$uri" "$api_package"
          continue
        fi

        target_layer="$(layer_of_path "$target")"
        if [ -n "$source_layer" ] && [ -n "$target_layer" ] && ! layer_allows "$source_layer" "$target_layer"; then
          printf '%s: imports %s — %s may not import %s\n' "$file" "$uri" "$source_layer" "$target_layer"
        fi
      done < <(dart_import_uris "$file")
    done < <(dart_source_files "${dir_of_package[$name]}")
  done
  return 0
}

# What is measurable in THIS tree, counted before the scan so an empty result can be told apart
# from an empty measurement. An empty derivation must never read as agreement.
PACKAGE_COUNT=0
LAYERED_FILE_COUNT=0
while IFS= read -r dir; do
  PACKAGE_COUNT=$((PACKAGE_COUNT + 1))
  while IFS= read -r file; do
    [ -n "$(layer_of_path "$file")" ] && LAYERED_FILE_COUNT=$((LAYERED_FILE_COUNT + 1))
  done < <(dart_source_files "$dir")
done < <(dart_package_dirs "$REPO")

if [ "$LAYERED_FILE_COUNT" -eq 0 ] && [ "$PACKAGE_COUNT" -lt 2 ]; then
  verdict_skip "nothing to measure yet — $PACKAGE_COUNT Dart package(s) and no file under a domain/, application/, presentation/ or infrastructure/ directory"
fi

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  finding "${hit#"$REPO/"}"
done <<< "$(scan_layering "$REPO")"

# Both halves get their own probe, and each proves both directions — a scan that reported every
# import would satisfy the red half alone.
PROBE="$(mktemp -d)"
trap 'rm -rf "$PROBE"' EXIT
mkdir -p "$PROBE/$API_DIRECTORY_NAME/lib/src/domain" \
         "$PROBE/$API_DIRECTORY_NAME/lib/src/infrastructure" \
         "$PROBE/deployment/lib"
printf 'name: ansiwise_api\n' > "$PROBE/$API_DIRECTORY_NAME/pubspec.yaml"
printf 'name: deployment\n'       > "$PROBE/deployment/pubspec.yaml"

printf "import '../infrastructure/real_shell.dart';\n" \
  > "$PROBE/$API_DIRECTORY_NAME/lib/src/domain/reaches_out.dart"
printf "import 'reaches_out.dart';\n" \
  > "$PROBE/$API_DIRECTORY_NAME/lib/src/domain/stays_in.dart"
printf "import '../domain/stays_in.dart';\n" \
  > "$PROBE/$API_DIRECTORY_NAME/lib/src/infrastructure/real_shell.dart"
printf "import 'package:deployment/steps.dart';\n" \
  > "$PROBE/$API_DIRECTORY_NAME/lib/src/domain/pulls_deployment.dart"
printf "import 'package:ansiwise_api/ansiwise_api.dart';\n" \
  > "$PROBE/deployment/lib/steps.dart"

# A finding reads `<importing file>: imports <uri> — <why>`, and the uri names the file at the
# other end of the arrow. The assertions therefore match a path in the IMPORTING position, before
# `: imports` — a bare substring match would find the allowed file inside the finding that reports
# the file importing it.
PROBE_HITS="$(scan_layering "$PROBE")"
for planted in domain/reaches_out.dart domain/pulls_deployment.dart; do
  if ! grep -q "$planted: imports" <<< "$PROBE_HITS"; then
    finding "counter-probe: the planted violation in $planted was not reported, so this scan cannot go red"
  fi
done
for allowed in domain/stays_in.dart infrastructure/real_shell.dart deployment/lib/steps.dart; do
  if grep -q "$allowed: imports" <<< "$PROBE_HITS"; then
    finding "counter-probe: $allowed follows the arrow and was reported anyway, so this scan refuses correct code"
  fi
done

note "$PACKAGE_COUNT Dart package(s), $LAYERED_FILE_COUNT file(s) under a layer directory"
if [ "$PACKAGE_COUNT" -lt 2 ]; then
  note "the cross-package half is not measured: only one Dart package is in this tree, so no import can cross a package boundary"
fi
if [ "$LAYERED_FILE_COUNT" -eq 0 ]; then
  note "the layer half is not measured: no domain/, application/, presentation/ or infrastructure/ directory exists yet"
fi
verdict "no import points outward — presentation to application to domain, infrastructure to domain, and ansiwise-api to nothing of this workspace"
