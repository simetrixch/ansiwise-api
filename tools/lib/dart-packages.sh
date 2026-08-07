# Finding the Dart packages of this repository.
#
# A Dart package is a directory holding a pubspec.yaml, and the repository root may be one of them.
# It is not always: a pubspec at the root that declares `workspace:` and carries no lib/ of its own
# is a workspace, and walking it would count every member package twice.
#
# Discovery is a search of the tree, not a read of a workspace list. A package that is on disk but
# not listed is exactly the case the gate must still see: it compiles, imports and violates a
# layering rule like any other, and reading the list would let it do so unwatched.
#
# The same discovery for the checks themselves lives in Dart, in test/checks/source_tree.dart. This
# copy is what tools/ci.sh loops over, and it is the whole of what is left in shell.
#
# This file is sourced, never executed. It sets no shell options.

# The directories of every Dart package under <root>, one per line, sorted. The root itself counts
# when it carries code — anything else would make a one-package repository invisible to the gate.
dart_package_dirs() {
  local root="$1"
  find "$root" \
      \( -name .git -o -name .dart_tool -o -name build -o -name node_modules -o -name Pods \) -prune \
      -o -name pubspec.yaml -print \
    | while IFS= read -r manifest; do
        local dir
        dir="$(dirname "$manifest")"
        if [ "$dir" = "$root" ] && ! [ -d "$dir/lib" ] && ! [ -d "$dir/bin" ]; then
          # A workspace manifest, not a package: it declares members and holds no code itself.
          continue
        fi
        printf '%s\n' "$dir"
      done \
    | sort
}
