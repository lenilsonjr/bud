REVIEW round 1
Reviewed: crew/BUD-19 against develop
What this does: Adds the `core/bud-ffi` workspace crate, which wraps `bud_core::Vault` behind a mutex and exposes it over UniFFI proc-macros. It provides flat records (`BudRecord`, `RowRecord`, `HitRecord`, `CountsRecord`), one `VaultError` enum, a `VaultListener` callback interface and a `watch` that returns a stoppable `VaultWatch`. It also adds a `uniffi-bindgen` binary and `scripts/build-core.sh`, which builds the four Apple targets, lipos the macOS pair, runs bindgen and assembles the XCFramework plus `BudCore.swift` under `build/`.
Ticket check:
- `core/bud-ffi` crate and API surface: met. Every listed method is present and the crate is thin, with conversions only.
- `crate-type`: met, with an added `lib` that the integration tests and bindgen binary need. This is a reasonable deviation.
- `BudRecord` flat with the listed fields, and one `VaultError`: met.
- Bindgen produces `BudCore.swift`, `BudCoreFFI.h` and the modulemap: met. I ran it and all three files were written.
- `VaultListener` callback interface named in the bindgen output: met. It appears 20 times in `BudCore.swift`.
- `scripts/build-core.sh`: met by reading, not run. `bash -n` passes. The macOS path (rustup targets, lipo, xcodebuild, idempotent `rm -rf` of its outputs) can only be exercised on the macOS runner in the CI ticket.
- `.gitignore` and nothing generated committed: met. The branch has no generated files and `git status` is clean.
- Hard rules: no files outside the ticket's scope were touched, and no Swift or SwiftUI files changed.
Tests:
- `core/bud-ffi/tests/vault.rs` has 8 tests that call the FFI surface the way Swift does.
  - They cover open and snapshot, record shape, children, all edits, trash and restore, the queries and both lenses, the error enum, and the listener hearing an outside change.
  - Gap (minor): `VaultWatch::stop()` and the stop-on-release behaviour are not directly tested in bud-ffi. The core has a test for dropping the watch.
- I ran:
  - `cargo test --workspace`: passes, including the 8 new tests.
  - `cargo clippy --workspace --all-targets -- -D warnings`: clean.
  - `cargo fmt --all --check`: clean.
  - `swift test`: 15 tests pass.
  - `bash -n scripts/build-core.sh`: passes.
  - Bindgen: ran as in the ticket and produced the three files.
- The host's checks on head `76c192371c7f3dd6694133b0c194f0a4a51bc6cd` passed (5 checks). I did not re-run them.
Findings:
1. scripts/build-core.sh:27 nit: `cargo build --release` for the iOS targets also builds the `cdylib`, which nothing uses there. It is harmless, but the build takes longer. It could be avoided later with `--lib` plus a per-target crate-type if build time matters.
2. core/bud-ffi/src/lib.rs:196 nit: `Counts` is converted with `as u64`. This is safe on all supported targets, so it is only a style note.
3. scripts/build-core.sh:36 question: the bindgen step reads the `.dylib` of the `aarch64-apple-darwin` build. This works on both Apple Silicon and Intel runners because it only reads metadata. Confirm on the macOS CI run, since nobody could run it here.
verdict: approved
