question: BUD-42 can't be built as written, and I haven't changed anything. Which of these do you want?

1. **Forbidden files.** The XCFramework needs tvOS and tvOS-simulator slices, which means editing `scripts/build-core.sh`. Linking it into the tvOS target needs `project.yml`. Both are off limits to me. Should I leave the tvOS slices and target wiring for you to do, or will you allow those two files for this ticket?
2. **Missing pieces.** `core/bud-ffi/src/lib.rs` exposes the vault but nothing for sync, peers or tickets. The core has `peer.rs` and `sync.rs`, but Swift has no binding to them. The Swift app doesn't use the vault at all: `BudTVView` runs on `BudStore` with a single file, not a vault folder. Three of the four criteria are therefore several tickets of work:
   - Caches location with a rebuild-on-empty fetch.
   - A foreground endpoint.
   - A ticket-entry pairing screen.

   Which scope do you want?
   - (a) Rust and Swift groundwork only: export sync, pairing and ticket calls through `bud-ffi` with `cargo test`, plus a Linux-testable Swift type that picks the vault and index paths and decides whether to fetch on an empty folder.
   - (b) Everything, including moving the TV app onto the vault, once you've settled option 1.
   - (c) Split the ticket first.

I recommend 1 (you do the build script and `project.yml` edits) together with 2(a).
