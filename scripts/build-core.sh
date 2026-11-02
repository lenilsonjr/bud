#!/usr/bin/env bash
# Build bud-ffi for Apple platforms and assemble what the Swift side links (ADR-003 §5):
#   build/BudCoreFFI.xcframework   the static library, headers and modulemap
#   build/BudCore/BudCore.swift    the generated Swift bindings
# Needs macOS with Xcode's command line tools and rustup. Safe to run again: it rebuilds
# build/ from scratch and adds a rustup target only when it is missing.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

profile="release"
lib="libbud_ffi"
targets=(
  aarch64-apple-darwin
  x86_64-apple-darwin
  aarch64-apple-ios
  aarch64-apple-ios-sim
)

installed="$(rustup target list --installed)"
for target in "${targets[@]}"; do
  if ! grep -qx "$target" <<<"$installed"; then
    rustup target add "$target"
  fi
done

for target in "${targets[@]}"; do
  cargo build -p bud-ffi --"$profile" --target "$target"
done

out="$root/build"
rm -rf "$out/BudCoreFFI.xcframework" "$out/BudCore" "$out/stage"
mkdir -p "$out/BudCore" "$out/stage/macos" "$out/stage/headers"

# One macOS library for both architectures.
lipo -create \
  "target/aarch64-apple-darwin/$profile/$lib.a" \
  "target/x86_64-apple-darwin/$profile/$lib.a" \
  -output "$out/stage/macos/$lib.a"

# Bindings come from the metadata inside a built library.
cargo run -p bud-ffi --bin uniffi-bindgen generate \
  --library "target/aarch64-apple-darwin/$profile/$lib.dylib" \
  --language swift \
  --out-dir "$out/stage/bindings"

cp "$out/stage/bindings/BudCore.swift" "$out/BudCore/BudCore.swift"
cp "$out/stage/bindings/BudCoreFFI.h" "$out/stage/headers/BudCoreFFI.h"
cp "$out/stage/bindings/BudCoreFFI.modulemap" "$out/stage/headers/module.modulemap"

xcodebuild -create-xcframework \
  -library "$out/stage/macos/$lib.a" -headers "$out/stage/headers" \
  -library "target/aarch64-apple-ios/$profile/$lib.a" -headers "$out/stage/headers" \
  -library "target/aarch64-apple-ios-sim/$profile/$lib.a" -headers "$out/stage/headers" \
  -output "$out/BudCoreFFI.xcframework"

rm -rf "$out/stage"
echo "Built $out/BudCoreFFI.xcframework and $out/BudCore/BudCore.swift"
