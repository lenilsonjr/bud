REVIEW round 2
Earlier findings:
1. Failing `gate` because the failure test depends on privileges: addressed. The failure test now puts a plain file where a folder must be, so it fails for every user, and the read-only variant skips its assertions when permission bits are not enforced. GitHub's checks on this head passed (4 checks).
2. Move-back failure is swallowed and the rollback has no test: declined by the builder. I accept it. It needs two filesystem operations to fail in a row, the index stays unchanged either way, and it was raised as a question.
3. Temp file name was visible in the vault: addressed. `write_atomic` now writes `.<name>.tmp` in the same folder, which a scan skips. A new test checks that no temp file is left behind.

New: nothing a fix introduced. In the read-only test, when permission bits are not enforced the move and rename really run and the test returns without checking. That is deliberate and harmless, because the plain-file test still covers the failure path for every user.

Tests: I did not run the suite, as instructed. I read the diff from 77072b7 to d406df8, which touches only `core/bud-core/src/edit.rs` and `core/bud-core/tests/edit.rs`. No SwiftUI file or protected path is touched. The host's four required checks passed on d406df8.

verdict: approved
