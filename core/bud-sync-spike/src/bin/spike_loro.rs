use bud_sync_spike::*;
use loro::{ExportMode, LoroDoc, TreeParentId};

fn build(bud: &Bud) -> LoroDoc {
    let doc = LoroDoc::new();
    let props = doc.get_map("props");
    for (k, v) in &bud.props {
        props.insert(k, v.as_str()).unwrap();
    }
    doc.get_map("meta").insert("path", bud.path.as_str()).unwrap();
    doc.get_text("body").insert(0, &bud.body).unwrap();
    doc.commit();
    doc
}

fn apply(doc: &LoroDoc, edit: &Edit) {
    let body = doc.get_text("body");
    let len = body.len_unicode();
    let (pos, del) = resolve(edit, len);
    if del > 0 {
        body.delete(pos, del).unwrap();
    }
    if !edit.insert.is_empty() {
        body.insert(pos, &edit.insert).unwrap();
    }
    doc.commit();
}

fn export_markdown(doc: &LoroDoc) -> String {
    let props = doc.get_map("props");
    let mut keys: Vec<String> = props.keys().map(|k| k.to_string()).collect();
    keys.sort();
    let mut out = String::from("---\n");
    for key in keys {
        let value = props.get(&key).unwrap().get_deep_value().into_string().unwrap();
        out.push_str(&format!("{key}: {}\n", *value));
    }
    out.push_str("---\n");
    out.push_str(&doc.get_text("body").to_string());
    out
}

fn snapshot(doc: &LoroDoc) -> Vec<u8> {
    doc.export(ExportMode::Snapshot).unwrap()
}

fn total_size(docs: &[LoroDoc]) -> usize {
    docs.iter().map(|d| snapshot(d).len()).sum()
}

fn main() {
    let buds = load_vault(&fixture_dir());
    let mut rng = Rng::new(7);
    let edits = make_edits(&mut rng, buds.len(), BODY_EDITS);

    let (docs, load_ms) = time(|| buds.iter().map(build).collect::<Vec<_>>());
    let loaded_size = total_size(&docs);
    let raw: usize = buds.iter().map(|b| b.body.len()).sum();

    let ((), edit_ms) = time(|| edits.iter().for_each(|e| apply(&docs[e.bud], e)));
    let edited_size = total_size(&docs);

    // Two replicas of every document, 100 edits each (200 in all), then merge.
    let a: Vec<LoroDoc> = docs.iter().map(|d| d.fork()).collect();
    let b: Vec<LoroDoc> = docs.iter().map(|d| d.fork()).collect();
    let ea = make_edits(&mut Rng::new(11), buds.len(), CONCURRENT_EDITS / 2);
    let eb = make_edits(&mut Rng::new(13), buds.len(), CONCURRENT_EDITS / 2);
    ea.iter().for_each(|e| apply(&a[e.bud], e));
    eb.iter().for_each(|e| apply(&b[e.bud], e));
    let (_, merge_ms) = time(|| {
        for (x, y) in a.iter().zip(b.iter()) {
            let from_y = y.export(ExportMode::updates(&x.oplog_vv())).unwrap();
            x.import(&from_y).unwrap();
        }
    });
    let merged_size = total_size(&a);

    // A tree document for paths, with a move.
    let tree_doc = LoroDoc::new();
    let tree = tree_doc.get_tree("paths");
    let root = tree.create(TreeParentId::Root).unwrap();
    let child = tree.create(TreeParentId::Node(root)).unwrap();
    let other = tree.create(TreeParentId::Root).unwrap();
    let moved = tree.mov(child, TreeParentId::Node(other)).is_ok();

    let export_ms = median_ms(9, || time(|| a.iter().map(export_markdown).collect::<Vec<_>>()).1);
    let sample = export_markdown(&a[0]);

    report(
        "loro",
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
            ("tree type with move", format!("yes, LoroTree::mov worked: {moved}")),
            ("sample export bytes", sample.len().to_string()),
        ],
    );
}
