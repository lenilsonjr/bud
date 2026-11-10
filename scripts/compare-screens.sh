#!/usr/bin/env bash
# Compare the screen catalog between two refs: which screens changed, which are new, which left.
#
#   scripts/compare-screens.sh [<base-ref> [<head-ref>]]
#   scripts/compare-screens.sh --collect <base-references> <rendered-catalog>
#
# The base ref's reference pictures (Tests/BudKitSnapshots/__Snapshots__/CatalogTests at that
# ref) are read with `git show`, so nothing is checked out. The head is the working tree, or
# a ref rendered in a temporary worktree, which builds from scratch. Rendering is the catalog
# test on macOS, pointed at the base pictures through BUD_CATALOG_REFERENCES. With no arguments
# the base is the newest v* tag: what people already have, the gate before a release. Day to
# day, pass `develop`.
#
# What comes out, under build/screens:
#   diff/        for a changed screen its new picture, the base reference and the difference;
#                for an added screen its picture; for a removed screen the base reference
#   summary.txt  the changed, added and removed screens, one name per line under each count
#   base/        the base references;  head/catalog/  every picture the head rendered
# One line on stdout per screen that changed, was added or was removed. Exit 1 when that list
# is not empty, 0 when every screen matches, 2 when nothing rendered or the arguments are off.
#
# --collect skips the rendering: given a folder of base references and the `catalog` folder
# the test wrote inside BUD_SNAPSHOT_DIR, it produces diff/ and the summary. That is the part
# that runs anywhere, and what the rendering path calls at the end.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
references="Tests/BudKitSnapshots/__Snapshots__/CatalogTests"
out="$root/build/screens"

usage() {
  echo "usage: $0 [<base-ref> [<head-ref>]]" >&2
  echo "       $0 --collect <base-references> <rendered-catalog>" >&2
  exit 2
}

# The screen names (surface.state-window-scheme) of the PNGs in a folder, one per line, sorted.
# What the test writes beside a changed screen (.reference.png, .diff.png) is not a screen.
screens() {
  find "$1" -maxdepth 1 -name '*.png' ! -name '*.reference.png' ! -name '*.diff.png' \
    -exec basename {} .png \; | sort
}

# One group of the summary: its name, its count, then one name per line.
group() {
  local title="$1"
  shift
  echo "$title: $#"
  local name
  for name in "$@"; do echo "  $name"; done
}

# Diff folder, summary and exit code from a base folder and a rendered folder.
collect() {
  local base="$1" rendered="$2" label_base="$3" label_head="$4"
  local changed=() added=() removed=() name
  rm -rf "$out/diff"
  mkdir -p "$out/diff"

  while IFS= read -r name; do
    if [ -f "$rendered/$name.diff.png" ]; then
      changed+=("$name")
      cp "$rendered/$name.png" "$rendered/$name.reference.png" "$rendered/$name.diff.png" "$out/diff/"
    elif [ ! -f "$base/$name.png" ]; then
      added+=("$name")
      cp "$rendered/$name.png" "$out/diff/$name.png"
    fi
  done < <(screens "$rendered")

  while IFS= read -r name; do
    if [ ! -f "$rendered/$name.png" ]; then
      removed+=("$name")
      cp "$base/$name.png" "$out/diff/$name.reference.png"
    fi
  done < <(screens "$base")

  {
    echo "base: $label_base"
    echo "head: $label_head"
    group changed "${changed[@]+"${changed[@]}"}"
    group added "${added[@]+"${added[@]}"}"
    group removed "${removed[@]+"${removed[@]}"}"
  } >"$out/summary.txt"

  for name in "${changed[@]+"${changed[@]}"}"; do echo "changed $name"; done
  for name in "${added[@]+"${added[@]}"}"; do echo "added $name"; done
  for name in "${removed[@]+"${removed[@]}"}"; do echo "removed $name"; done
  local total=$((${#changed[@]} + ${#added[@]} + ${#removed[@]}))
  if [ "$total" -eq 0 ]; then
    echo "Every screen matches $label_base."
    return 0
  fi
  echo "$total screen(s) differ from $label_base; see $out/diff and $out/summary.txt"
  return 1
}

if [ "${1:-}" = "--collect" ]; then
  [ $# -eq 3 ] && [ -d "$2" ] && [ -d "$3" ] || usage
  collect "$2" "$3" "$2" "$3"
  exit 0
fi

[ $# -le 2 ] || usage
case "${1:-}" in -*) usage ;; esac

if [ $# -ge 1 ]; then
  base_ref="$1"
else
  base_ref="$(git -C "$root" tag -l 'v*' --sort=-version:refname | head -n 1)"
  [ -n "$base_ref" ] || { echo "No v* tag to compare against; name a base ref." >&2; exit 2; }
fi
git -C "$root" rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null \
  || { echo "Unknown ref: $base_ref" >&2; exit 2; }
head_ref="${2:-}"
if [ -n "$head_ref" ]; then
  git -C "$root" rev-parse --verify --quiet "$head_ref^{commit}" >/dev/null \
    || { echo "Unknown ref: $head_ref" >&2; exit 2; }
fi

# The base references, read straight from the object store. The test gets a copy to work
# against, since it records a reference it cannot find; base/ stays as the ref has it.
rm -rf "$out/base" "$out/head"
mkdir -p "$out/base" "$out/head/references"
git -C "$root" ls-tree -r --name-only "$base_ref" -- "$references" | while IFS= read -r file; do
  git -C "$root" show "$base_ref:$file" >"$out/base/$(basename "$file")"
done
cp "$out/base/"*.png "$out/head/references/" 2>/dev/null || true

# The head: the working tree, or a ref in a worktree that goes away with the run.
tree="$root"
worktree=""
cleanup() {
  if [ -n "$worktree" ]; then
    git -C "$root" worktree remove --force "$worktree" >/dev/null 2>&1 || true
    rm -rf "$worktree"
  fi
}
trap cleanup EXIT
if [ -n "$head_ref" ]; then
  worktree="$(mktemp -d)"
  git -C "$root" worktree add --detach "$worktree" "$head_ref" >/dev/null
  tree="$worktree"
fi

# The test fails whenever a screen differs; that is the answer, not an error. A run that left
# no picture at all did not render, and its log says why.
echo "Rendering ${head_ref:-the working tree} against $base_ref..." >&2
(
  cd "$tree"
  BUD_SNAPSHOT_DIR="$out/head" BUD_CATALOG_REFERENCES="$out/head/references" \
    swift test --filter BudKitSnapshots.CatalogTests >"$out/test.log" 2>&1
) || true
if [ ! -d "$out/head/catalog" ] || [ -z "$(screens "$out/head/catalog")" ]; then
  tail -n 40 "$out/test.log" >&2
  echo "The catalog did not render; the full log is in $out/test.log" >&2
  exit 2
fi

collect "$out/base" "$out/head/catalog" "$base_ref" "${head_ref:-working tree}"
