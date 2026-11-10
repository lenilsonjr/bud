#!/usr/bin/env bash
# Compare the screen catalog between two refs: which screens changed, which are new, which left,
# and which the head could not take.
#
#   scripts/compare-screens.sh [<base-ref> [<head-ref>]]
#   scripts/compare-screens.sh --collect <base-references> <rendered-catalog>
#
# The base ref's reference pictures (Tests/BudKitSnapshots/__Snapshots__/CatalogTests at that
# ref) come out of `git archive`, so nothing is checked out. The head is the working tree, or
# a ref rendered in a temporary worktree, which builds from scratch. Rendering is the catalog
# test on macOS, pointed at the base pictures through BUD_CATALOG_REFERENCES; the test keeps
# every picture it takes and writes manifest.txt, one line per screen with its outcome, which
# is where the groups below come from. With no arguments the base is the newest v* tag: what
# people already have, the gate before a release. Day to day, pass `develop`.
#
# What comes out, under build/screens:
#   diff/        for a changed screen its new picture, the base reference and the difference;
#                for an added or a failed screen its picture, when there is one; for a removed
#                screen the base reference
#   summary.txt  the changed, added, removed and failed screens, one per line under each count
#   base/        the base references;  head/catalog/  every picture the head took, and the
#                manifest
# The groups: changed is a screen that mismatched its base reference; added is one the base
# had no reference for; removed is a base reference the head never planned to take; failed is
# one the head planned but could not take, whether its setup threw or the run died before it.
# One line on stdout per screen in a group. Exit 1 when the groups are not all empty, 0 when
# every screen matches, 2 when the catalog did not render or the arguments are off.
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
screens() {
  find "$1" -maxdepth 1 -name '*.png' ! -name '*.reference.png' ! -name '*.diff.png' \
    -exec basename {} .png \; | sort
}

# The manifest's answer per screen: its last line wins, so a screen left at `planned` is one
# the run never got to.
outcomes() {
  awk 'NF == 2 { outcome[$1] = $2 } END { for (name in outcome) print name, outcome[name] }' "$1" | sort
}

# One group of the summary: its name, its count, then one name per line.
group() {
  local title="$1"
  shift
  echo "$title: $#"
  local name
  for name in "$@"; do echo "  $name"; done
}

# Copy a rendered picture into diff/ when the head took one.
keep() {
  if [ -f "$1" ]; then cp "$1" "$out/diff/"; fi
}

# Diff folder and summary from a base folder and a rendered folder; `total` is how many screens
# landed in a group.
total=0
collect() {
  local base="$1" rendered="$2" label_base="$3" label_head="$4"
  local changed=() added=() removed=() failed=() name outcome attempted
  local manifest="$rendered/manifest.txt"
  [ -f "$manifest" ] || { echo "No manifest in $rendered: the catalog did not render." >&2; exit 2; }
  rm -rf "$out/diff"
  mkdir -p "$out/diff"
  attempted="$(outcomes "$manifest" | cut -d ' ' -f 1)"

  while read -r name outcome; do
    case "$outcome" in
      matched) ;;
      mismatched)
        changed+=("$name")
        cp "$rendered/$name.png" "$rendered/$name.reference.png" "$rendered/$name.diff.png" "$out/diff/"
        ;;
      recorded)
        if [ -f "$base/$name.png" ]; then
          changed+=("$name")
          cp "$rendered/$name.png" "$out/diff/"
          cp "$base/$name.png" "$out/diff/$name.reference.png"
        else
          added+=("$name")
          cp "$rendered/$name.png" "$out/diff/"
        fi
        ;;
      *)
        failed+=("$name")
        keep "$rendered/$name.png"
        ;;
    esac
  done < <(outcomes "$manifest")

  while IFS= read -r name; do
    if ! grep -qxF -- "$name" <<<"$attempted"; then
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
    group failed "${failed[@]+"${failed[@]}"}"
  } >"$out/summary.txt"

  for name in "${changed[@]+"${changed[@]}"}"; do echo "changed $name"; done
  for name in "${added[@]+"${added[@]}"}"; do echo "added $name"; done
  for name in "${removed[@]+"${removed[@]}"}"; do echo "removed $name"; done
  for name in "${failed[@]+"${failed[@]}"}"; do echo "failed $name"; done
  total=$((${#changed[@]} + ${#added[@]} + ${#removed[@]} + ${#failed[@]}))
  if [ "$total" -eq 0 ]; then
    echo "Every screen matches $label_base."
  else
    echo "$total screen(s) differ from $label_base; see $out/diff and $out/summary.txt"
  fi
}

if [ "${1:-}" = "--collect" ]; then
  [ $# -eq 3 ] && [ -d "$2" ] && [ -d "$3" ] || usage
  collect "$2" "$3" "$2" "$3"
  if [ "$total" -eq 0 ]; then exit 0; fi
  exit 1
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

# The base references, read straight from the object store; a ref from before the catalog has
# none. The test gets a copy to work against, since it records a reference it cannot find;
# base/ stays as the ref has it.
rm -rf "$out/base" "$out/head"
mkdir -p "$out/base" "$out/head/references"
if [ -n "$(git -C "$root" ls-tree -d "$base_ref" -- "$references")" ]; then
  depth=$(( $(printf '%s' "$references" | tr -cd / | wc -c) + 1 ))
  git -C "$root" archive "$base_ref" -- "$references" | tar -x -C "$out/base" --strip-components="$depth"
fi
if [ -n "$(screens "$out/base")" ]; then
  cp "$out/base/"*.png "$out/head/references/"
fi

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
# no manifest did not render, and one that failed with nothing in the manifest to show for it
# failed for another reason; the log says why in both cases.
echo "Rendering ${head_ref:-the working tree} against $base_ref..." >&2
status=0
(
  cd "$tree"
  BUD_SNAPSHOT_DIR="$out/head" BUD_CATALOG_REFERENCES="$out/head/references" \
    swift test --filter BudKitSnapshots.CatalogTests >"$out/test.log" 2>&1
) || status=$?
if [ ! -f "$out/head/catalog/manifest.txt" ]; then
  tail -n 40 "$out/test.log" >&2
  echo "The catalog did not render; the full log is in $out/test.log" >&2
  exit 2
fi

collect "$out/base" "$out/head/catalog" "$base_ref" "${head_ref:-working tree}"
if [ "$total" -ne 0 ]; then exit 1; fi
if [ "$status" -ne 0 ]; then
  tail -n 40 "$out/test.log" >&2
  echo "The test failed (status $status) with nothing in the manifest to show for it; see $out/test.log" >&2
  exit 2
fi
exit 0
