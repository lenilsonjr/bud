BUILD round 1
Ticket: all criteria met except as noted.
- `protocol Peers` (`Sources/BudKit/Peers.swift`): met. It has `devices`, `ticket(withAddresses:)`, `accept`, `remove`, `allow`, `rotateKey` (an `AsyncStream<RotationStep>` ending in `.done(RotationResult)`), `syncNow`, `state`, `relay`/`setRelay` (`default`, `custom(URL)`, `off`) and `events`. `PeerEvent` has the four cases. The ticket lists `allow` but the Rust `PeerNode` has no matching call, so I read it as letting a device the last rotation turned away back in: it clears `missed`.
- `Device`, `Ticket`: met. `Device` has `Reach`, `lastSeen`, `missed`, and optional `name` and `DeviceKind`. `Ticket.expiresAt` defaults to ten minutes after `madeAt`. The ticket does not list the kinds, so I picked `mac`, `iphone`, `ipad` and `tv`.
- `AcceptError`: met. `AcceptError(message:)` maps "not a pairing ticket", "refused" and "could not reach".
- `MemoryPeers` actor (`Sources/BudKit/MemoryPeers.swift`): met.
  - It issues one-use tickets that expire after a lifetime you can set, with a clock the test supplies.
  - `accept` adds a fake device and fires `ticketRedeemed` and `deviceJoined`.
  - `rotateKey` streams one step per device, and a configurable set of devices miss it.
  - `emitFetchProgress` drives fetch progress from a test.
  - The fixture ids are the five from the frames (a91c…7t0e, k7f3…q2m9, m2pd…h81k, t6vb…2kxe, c55w…0pdl).
- `DeviceStore` (`Sources/BudKit/DeviceStore.swift`): met. It has `devices`, `syncState`, `lastSummary`, `currentTicket` (refreshes on expiry while a sheet is open), `join(text:)` with `JoinPhase`, `remove(_:rotate:)`, `rotation` progress and `shortID`. I added a few things the frames imply: `allow`, `syncNow`, `redeemedBy`, `resetJoin` and `dismissRotation`.
- Text helpers (`Sources/BudKit/PeerText.swift`): met. It has groups of five, "37 of 134", `looksLikeTicket(_:)`, "seen …" labels, the "9:58" countdown and `shortID`. I read 134 as the ticket length and set the tolerance to ±6; both are constants in `PeerText`.
- Not touching the App target, `project.yml`, the Rust crates or adding views: met.
- One addition outside the ticket: `Sources/BudKit/ObservableShim.swift`. Linux has no Combine, so `DeviceStore` could not compile or test there. On Linux only, the shim provides an empty `ObservableObject` and `@Published`. On Apple platforms the real Combine types are used.

Changed:
- `Sources/BudKit/Peers.swift`
- `Sources/BudKit/PeerText.swift`
- `Sources/BudKit/MemoryPeers.swift`
- `Sources/BudKit/DeviceStore.swift`
- `Sources/BudKit/ObservableShim.swift`
- `Tests/BudKitTests/PeerTextTests.swift`
- `Tests/BudKitTests/MemoryPeersTests.swift`
- `Tests/BudKitTests/DeviceStoreTests.swift`

Tests:
- `PeerTextTests` covers:
  - grouping and the typed count;
  - `looksLikeTicket`, including the tolerance edges;
  - the seen labels, never seen and a future date;
  - the countdown;
  - `shortID`;
  - the error mapping and the ticket lifetime.
- `MemoryPeersTests` covers:
  - fixtures, ticket issue, accepting once, expiry, not a ticket, unreachable and removal;
  - rotation with and without a missed device, `allow` and the sync event;
  - state, relay round trip and fetch progress.
- `DeviceStoreTests` covers:
  - the device list and sync state;
  - ticket refresh, by hand and by timer;
  - join success and each of the three errors;
  - fetch progress during a join and a redeemed ticket;
  - removal without rotation, with rotation, with a missed device, and `allow`.
- Gate:
  - `swift build` passed.
  - `swift test` ran 156 tests with 0 failures, including the new suites.
  - `cargo fmt --all --check` was clean.
  - `cargo clippy --all-targets -- -D warnings` was clean.
  - `cargo test --workspace` passed.
- I weakened no expectation.

Verify: from the repository root, run `swift test --filter PeerTextTests`, then `--filter MemoryPeersTests`, then `--filter DeviceStoreTests`. The app still builds on the pull request's macOS checks. Nothing in the app target reads the new files yet, so nothing there changes.
