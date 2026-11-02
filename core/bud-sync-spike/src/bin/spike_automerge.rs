use automerge::transaction::Transactable;
use automerge::{AutoCommit, ObjType, ReadDoc, ROOT};
use bud_sync_spike::*;

fn build(bud: &Bud) -> AutoCommit {
    let mut doc = AutoCommit::new();
    let props = doc.put_object(&ROOT, "props", ObjType::Map).unwrap();
    for (k, v) in &bud.props {
        doc.put(&props, k.as_str(), v.as_str()).unwrap();
    }
    doc.put(&ROOT, "path", bud.path.as_str()).unwrap();
    let body = doc.put_object(&ROOT, "body", ObjType::Text).unwrap();
    doc.splice_text(&body, 0, 0, &bud.body).unwrap();
    doc
}

fn body_id(doc: &AutoCommit) -> automerge::ObjId {
    doc.get(&ROOT, "body").unwrap().unwrap().1
}

fn apply(doc: &mut AutoCommit, edit: &Edit) {
    let body = body_id(doc);
    let len = doc.text(&body).unwrap().chars().count();
    let (pos, del) = resolve(edit, len);
    doc.splice_text(&body, pos, del as isize, &edit.insert).unwrap();
}

fn export_markdown(doc: &AutoCommit) -> String {
    let props = doc.get(&ROOT, "props").unwrap().unwrap().1;
    let mut out = String::from("---\n");
    for key in doc.keys(&props) {
        let value = doc.get(&props, &key).unwrap().unwrap().0.into_string().unwrap();
        out.push_str(&format!("{key}: {value}\n"));
    }
    out.push_str("---\n");
    out.push_str(&doc.text(&body_id(doc)).unwrap());
    out
}

fn total_size(docs: &mut [AutoCommit]) -> usize {
    docs.iter_mut().map(|d| d.save().len()).sum()
}

fn main() {
    let buds = load_vault(&fixture_dir());
    let mut rng = Rng::new(7);
    let edits = make_edits(&mut rng, buds.len(), BODY_EDITS);

    let (mut docs, load_ms) = time(|| buds.iter().map(build).collect::<Vec<_>>());
    let loaded_size = total_size(&mut docs);
    let raw: usize = buds.iter().map(|b| b.body.len()).sum();

    let ((), edit_ms) = time(|| edits.iter().for_each(|e| apply(&mut docs[e.bud], e)));
    let edited_size = total_size(&mut docs);

    // Two replicas of every document, 100 edits each (200 in all), then merge.
    let mut a: Vec<AutoCommit> = docs.iter_mut().map(|d| d.fork()).collect();
    let mut b: Vec<AutoCommit> = docs.iter_mut().map(|d| d.fork()).collect();
    let ea = make_edits(&mut Rng::new(11), buds.len(), CONCURRENT_EDITS / 2);
    let eb = make_edits(&mut Rng::new(13), buds.len(), CONCURRENT_EDITS / 2);
    ea.iter().for_each(|e| apply(&mut a[e.bud], e));
    eb.iter().for_each(|e| apply(&mut b[e.bud], e));
    let (_, merge_ms) = time(|| {
        for (x, y) in a.iter_mut().zip(b.iter_mut()) {
            x.merge(y).unwrap();
        }
    });
    let merged_size = total_size(&mut a);

    let export_ms = median_ms(9, || time(|| a.iter().map(export_markdown).collect::<Vec<_>>()).1);
    let sample = export_markdown(&a[0]);

    report(
        "automerge",
        &[
            ("documents", docs.len().to_string()),
            ("raw body bytes", raw.to_string()),
            ("load all (ms)", format!("{load_ms:.3}")),
            ("size on disk after load (bytes)", loaded_size.to_string()),
            ("1000 body edits (ms)", format!("{edit_ms:.3}")),
            ("size after 1000 edits (bytes)", edited_size.to_string()),
            ("merge 200 concurrent edits (ms)", format!("{merge_ms:.3}")),
            ("size after merge (bytes)", merged_size.to_string()),
            ("export all markdown, median of 9 (ms)", format!("{export_ms:.3}")),
            ("tree type with move", "no (maps and lists only; a move is delete plus insert)".into()),
            ("sample export bytes", sample.len().to_string()),
        ],
    );
}
