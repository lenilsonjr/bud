// Same fixture loading and edit generation as the library binaries, with no
// CRDT, so the binary size added by each library is a difference.
use bud_sync_spike::*;

fn main() {
    let buds = load_vault(&fixture_dir());
    let mut rng = Rng::new(7);
    let edits = make_edits(&mut rng, buds.len(), BODY_EDITS);
    println!("buds: {}, edits: {}", buds.len(), edits.len());
}
