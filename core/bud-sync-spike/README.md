# bud-sync-spike

Throwaway spike for BUD-38. Not a workspace member; this branch is for reading and is closed without merge.

Run from this directory, once per library:

    cargo build --release --features automerge,loro
    target/release/spike-automerge
    target/release/spike-loro
    ls -l target/release/baseline target/release/spike-automerge target/release/spike-loro

Each bud becomes one document: a map for properties and path, a text for the body. Edits are generated from a fixed seed, so both libraries see the same ones: 1,000 body edits on one replica, then 100 + 100 concurrent edits on two forks of every document, merged.

## Results (11 fixture buds, 287 bytes of body in total)

| Measure | automerge 0.12 | loro 1.17 |
| --- | --- | --- |
| Size on disk, fixture after load | 2,954 B | 5,880 B |
| Size on disk after 1,000 edits | 14,596 B | 19,504 B |
| Merge of 200 concurrent edits | 4.38 ms | 0.88 ms |
| Export all bodies as Markdown (median of 9) | 0.260 ms | 0.031 ms |
| Load fixture into documents | 0.88 ms | 0.22 ms |
| 1,000 body edits | 28.9 ms | 1.8 ms |
| Binary size added (release, LTO, size-optimised, stripped) | 927 KB | 1,845 KB |
| Move operation in the tree type | no tree type; a move is delete plus insert | yes, `LoroTree::mov` |

Binary sizes: baseline 312,832 B, automerge binary 1,239,992 B, loro binary 2,157,712 B.

## Reading the numbers

- The fixture is tiny, so every absolute time is small and sizes are dominated by per-document overhead. Loro's snapshots carry more fixed overhead per document, which is why it is larger here. The gap narrows as edits accumulate (about 2x after load, 1.3x after 1,000 edits). A larger vault would show whether it closes.
- Automerge has no tree type, so the paths document would be a map of maps, and a move would lose identity and concurrent-move safety. Loro's tree has a real move that resolves concurrent moves without cycles.
- Loro is roughly 5 to 15 times faster on every timed step. Automerge costs about half the binary size.
- Timings are a single run on one machine class and one seed, apart from export, which is a median.

## Recommendation

Choose loro. The paths document needs a move that survives concurrent edits (renaming and reparenting buds), and only loro has it as a first-class operation. It is also much faster on edits, merge and export. The costs are about 0.9 MB more binary and larger documents on a tiny vault; both are acceptable for an app of this kind. Revisit only if a larger-vault measurement shows documents growing much faster than automerge's.
