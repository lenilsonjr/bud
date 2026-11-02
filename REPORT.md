```
BUILD round 1
Ticket:
- Crate `core/bud-ffi`: met. It is a workspace member with `crate-type = ["staticlib", "cdylib", "lib"]`. The extra `lib` is there so the integration tests and the bindgen binary can link it. It exports `open_vault(vault_dir, index_path) -> Arc<Vault>`, which also rescans so the index is filled on open. `Vault` has `snapshot`, `children`, `bud`, `create`, `set_body`, `set_state`, `set_pinned`, `rename`, `move_to`, `trash`, `restore`, `search`, `today`, `counts`, `next_step`, `lens` and `watch(listener)`. `BudRecord` is flat, with path, parent, title, kind, state, when, due, pinned, created, source, body and place. Errors are one `VaultError` enum. The enums are named `BudKind`, `BudState`, `BudPlace` and `VaultLens`, so they don't collide with app types. Query results come back as `RowRecord`, `HitRecord` and `CountsRecord`. `watch` returns a `VaultWatch` object that stops the watcher when it is released or when `stop()` is called.
- Bindgen: met. `cargo run -p bud-ffi --bin uniffi-bindgen generate --library target/debug/libbud_ffi.so --language swift --out-dir <dir>` produced `BudCore.swift`, `BudCoreFFI.h` and `BudCoreFFI.modulemap`.
- `scripts/build-core.sh`: partial. I wrote it to do all of the following. I could not run it on Linux, so the macOS path is untested until CI.
  - Add the four rustup targets when they are missing.
  - Build for all four targets and lipo the macOS pair.
  - Run bindgen.
  - Assemble `build/BudCoreFFI.xcframework` and `build/BudCore/BudCore.swift`.
  - Clear its own outputs first, so a second run gives the same result.
  - `bash -n` passes.
- `.gitignore` and generated files: met. `build/` was already ignored and nothing generated is in the tree. `git status` shows only the new sources, `Cargo.toml` and `Cargo.lock`.
- `VaultListener`: met. It is a UniFFI callback interface with `changed(paths)`, and the generated `BudCore.swift` names it.

Changed: Cargo.toml, Cargo.lock, core/bud-ffi/Cargo.toml, core/bud-ffi/src/lib.rs, core/bud-ffi/uniffi-bindgen.rs, core/bud-ffi/tests/vault.rs, scripts/build-core.sh

Tests: `core/bud-ffi/tests/vault.rs` has 8 tests, written before the code. They call the FFI surface the way Swift does.
- Open and snapshot.
- A flat record's fields.
- Children.
- Create, set_body, set_state, set_pinned, rename and move_to.
- Trash and restore.
- Search, today, counts, next_step and both lenses.
- `VaultError` variants.
- The listener hears a change made outside the app.
Gate:
- `swift build`: pass.
- `swift test`: pass, 15 tests.
- `cargo fmt --all --check`: pass.
- `cargo clippy --all-targets -- -D warnings`: pass.
- `cargo test --workspace`: pass. Core tests are unchanged and the 8 new ones pass.
No expectation was weakened.

Verify:
- Run `cargo test --workspace`.
- Run `cargo build -p bud-ffi`.
- Run `cargo run -p bud-ffi --bin uniffi-bindgen generate --library target/debug/libbud_ffi.so --language swift --out-dir build/check`. Then look for `BudCore.swift`, `BudCoreFFI.h` and `BudCoreFFI.modulemap` in `build/check`, and for `VaultListener` in `BudCore.swift`. On macOS the library is `libbud_ffi.dylib`.
- Run `bash -n scripts/build-core.sh`.
- The script's real run is on the macOS runner. After it, `build/BudCoreFFI.xcframework` and `build/BudCore/BudCore.swift` should exist and `git status` should stay clean.
```
