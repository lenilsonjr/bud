#!/bin/sh
# Camarim image setup for Bud (CAM-5): what the package's Rust crates need and the base image lacks.
# Runs once, as root, while the house builds the project's box image; nothing here runs at turn time.
#
# - gcc, because rusqlite's `bundled` feature compiles C.
# - Rust from the standalone installer, pinned by version and checksum, installed root-owned under
#   /usr/local with no rustup, so nothing in /usr/local/bin is writable by the box and the image
#   build's ownership check passes. CARGO_HOME defaults to the box user's home, which it can write.
set -eu

RUST_VERSION=1.99.1
RUST_SHA256=231fcae47ee950621374725b5fc3b5441d2fbda2955ac45dd7dc816d8876cfe7
RUST_TARGET=x86_64-unknown-linux-gnu

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends gcc ca-certificates curl xz-utils
rm -rf /var/lib/apt/lists/*

tarball="rust-$RUST_VERSION-$RUST_TARGET.tar.xz"
tmp=$(mktemp -d)
cd "$tmp"
curl -fsSLO "https://static.rust-lang.org/dist/$tarball"
echo "$RUST_SHA256  $tarball" | sha256sum -c -
tar -xJf "$tarball"
"rust-$RUST_VERSION-$RUST_TARGET/install.sh" --prefix=/usr/local \
  --components=rustc,cargo,rust-std-$RUST_TARGET,clippy-preview,rustfmt-preview
cd /
rm -rf "$tmp"

cargo --version
rustc --version
