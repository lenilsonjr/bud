# Working on Bud

Rules for anyone, person or agent, who changes this repository. Where this file is stricter than
a tool's defaults, this file wins. The plan and the decision records live outside the repository;
this file carries only what a change must respect.

## Branches, commits, merges

- `develop` is where work lands and the beta channel: every push to it ships a TestFlight build.
  `main` is the release line. Both move only by pull request with green build checks.
- Cut from and compare against `develop`. Never push to or commit on `main` or `develop`.
- Never run `gh pr merge`, `fastlane`, `xcodebuild`, `xcodegen`, or anything under `scripts/`
  unless a ticket says so. Merging is the owner's.
- A commit subject is one gitmoji, a space, and a short sentence in the imperative. No body, no
  trailers. Add commits; never rewrite what a shared branch already carries.

## What never goes in

- Personal information: no real names, emails, addresses, phone numbers or device names in code,
  seeds, fixtures, tests or comments. Seed data is the fictional newsletter world in
  `Tree.seed()`; fixtures use the same world.
- Secrets and signing: never read or write `Config/BundleIdSecrets.xcconfig` or a `.p8` file.
  Never print a token.
- Do not touch `.github/workflows/`, `fastlane/`, `Config/`, `Design/`,
  `Resources/Assets.xcassets/`, `project.yml`, `LICENSE` or `Gemfile`. A ticket that needs one of
  them is a question for the owner, not a change.
- No Markdown documents beyond this file and the README. Plans, notes and records live outside
  the repository.
- Nothing about the infrastructure behind the project: no host names, no internal tool names, no
  account or workspace names, in code, comments, commit messages or pull requests.

## Code

- Logic lives in files that compile and test on Linux: the model, the layout, the vault
  protocol, the Rust crate. Every file that imports SwiftUI, UIKit or AppKit sits inside
  `#if canImport(SwiftUI)` or the matching `#if os(...)`, so `swift build` keeps passing on
  Linux and the gate below can run anywhere.
- Colours and fonts come from `Theme` only. No literal colours or system fonts in views.
- User-facing text: sentence case, Apple spelling (to-do, to-dos), no em dashes, no emoji.
- Tests first. Rust: `cargo test`. Swift: XCTest in `Tests/`.

## The gate

From the repository root, each by itself:

```sh
swift build
swift test
cargo fmt --all --check
cargo clippy --all-targets -- -D warnings
cargo test --workspace
```

The iOS and macOS apps compile only on GitHub's macOS runners, on the pull request. Both
`build (iOS, …)` and `build (macOS, …)` must be green before a merge.
