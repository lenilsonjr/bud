#!/usr/bin/env bash
# Render the screen catalog of the working tree as the iOS app draws it, on a named simulator.
#
#   scripts/ios-catalog.sh <simulator-name> [<out-dir>]
#
# e.g. scripts/ios-catalog.sh "iPad Pro 13-inch (M4)"
#
# The catalog is the unit-test target Bud-iOS-Catalog, hosted in the app: it draws the screens
# of the Mac's catalog, at the same sizes, in the app's window on the simulator, and writes each
# picture to <out-dir>/catalog with manifest.txt beside them, which is the folder layout the
# Mac's catalog writes. Nothing is compared: these are pictures to look at, for a review, a
# release or the design file.
#
# A shot is only as big as the simulator's screen. No simulator holds the Mac window
# (1400x900), so the mac shots are always skipped; the iOS catalog is the phone, iPad and Stage
# Manager shots. On the largest iPad the test takes what fits upright, turns the simulator to
# landscape and takes the landscape iPad too; if the simulator will not turn, the landscape
# iPad is skipped as well. Each skipped shot is in the manifest with its reason.
#
# What comes out, under <out-dir> (build/screens-ios by default):
#   catalog/          one PNG per screen taken, named surface.state-window-scheme.png, and the
#                     manifest
#   catalog.xcresult  the test result, which carries every picture as an attachment too
#   test.log          xcodebuild's output
# One line on stdout per screen that failed, that the Mac's references have and this run never
# planned, or that the Mac's references lack; then one per skipped screen with its
# reason. Exit 0 when nothing failed or went missing, skipped screens or not; 1 when something
# did; 2 when the catalog did not render or the arguments are off.
#
# Needs a Mac with Xcode, XcodeGen and the core built once (scripts/build-core.sh).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
references="$root/Tests/BudKitSnapshots/__Snapshots__/CatalogTests"

[ $# -ge 1 ] && [ $# -le 2 ] && [ -n "$1" ] || {
  echo "usage: $0 <simulator-name> [<out-dir>]" >&2
  exit 2
}
simulator="$1"
out="${2:-$root/build/screens-ios}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

[ -d "$root/build/BudCoreFFI.xcframework" ] || { echo "No core in build/; run scripts/build-core.sh first." >&2; exit 2; }
command -v xcodegen >/dev/null || { echo "XcodeGen is not installed (brew install xcodegen)." >&2; exit 2; }

# The screen names (surface.state-window-scheme) of the PNGs in a folder, one per line, sorted.
screens() {
  find "$1" -maxdepth 1 -name '*.png' ! -name '*.reference.png' ! -name '*.diff.png' \
    -exec basename {} .png \; | sort
}

rm -rf "$out/catalog" "$out/catalog.xcresult"
(cd "$root" && xcodegen generate --quiet)

# xcodebuild hands TEST_RUNNER_ variables to the app the tests run in, without the prefix. A
# screen that fails fails the run; the manifest says which, so the status alone is not the answer.
echo "Rendering the iOS catalog of the working tree on $simulator..." >&2
status=0
TEST_RUNNER_BUD_SNAPSHOT_DIR="$out" xcodebuild test \
  -project "$root/Bud.xcodeproj" -scheme "Bud iOS Catalog" \
  -destination "platform=iOS Simulator,name=$simulator" \
  -resultBundlePath "$out/catalog.xcresult" \
  CODE_SIGNING_ALLOWED=NO >"$out/test.log" 2>&1 || status=$?
if [ ! -f "$out/catalog/manifest.txt" ]; then
  tail -n 40 "$out/test.log" >&2
  echo "The catalog did not render (status $status); the full log is in $out/test.log" >&2
  exit 2
fi

# The manifest's answer per screen is its last line, so one left at `planned` never got taken.
# A skipped screen's line carries its reason after the outcome.
answers="$(awk 'NF >= 2 { line[$1] = $0 } END { for (name in line) print line[name] }' "$out/catalog/manifest.txt" | sort)"
failed="$(awk '$2 != "taken" && $2 != "skipped" { print $1 }' <<<"$answers")"
skipped="$(awk '$2 == "skipped" { print $1 }' <<<"$answers")"
# Missing is a Mac reference this run never planned; a planned one that went wrong is failed.
missing="$(comm -23 <(screens "$references") <(cut -d ' ' -f 1 <<<"$answers"))"
extra="$(comm -13 <(screens "$references") <(screens "$out/catalog"))"

problems=0
for name in $failed; do echo "failed $name"; problems=$((problems + 1)); done
for name in $missing; do echo "missing $name"; problems=$((problems + 1)); done
for name in $extra; do echo "extra $name"; problems=$((problems + 1)); done
sed -n 's/^\([^ ]*\) skipped /skipped \1 /p' <<<"$answers"
taken="$(screens "$out/catalog" | wc -l | tr -d ' ')"
count="$(sed '/^$/d' <<<"$skipped" | wc -l | tr -d ' ')"
if [ "$problems" -eq 0 ]; then
  echo "$taken screens in $out/catalog and $count skipped, name for name with the Mac's catalog."
  exit 0
fi
echo "$taken screens in $out/catalog, $count skipped; $problems failed or not in the Mac's set. See $out/test.log" >&2
exit 1
