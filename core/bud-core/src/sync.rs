//! One CRDT document per bud, kept in step with the Markdown file (ADR-001: the file stays the
//! truth a person can read; the document is what replicas merge).
//!
//! A bud's document has a text `body` and a map `props` of the frontmatter keys. A second document
//! holds the tree of buds, one node per bud keyed by the bud's identity: a rename sets the node's
//! name, a move re-parents the node, trashing sets a flag. Two replicas that move the same bud
//! converge on one parent.
//!
//! The table `docs` maps a path to the identity of its document and keeps the document bytes and
//! the last full file text the document knew. A file that differs from that text was edited by
//! someone else; the difference becomes text operations and map sets. A document that differs from
//! its file is written back through [`Vault::set_properties`] and [`Vault::set_body`], the writers
//! every other edit uses. When the two agree nothing is written.
//!
//! Identity contract: a bud's identity is made by the replica that first syncs it. Another
//! replica of the same vault takes it over with [`Vault::adopt_doc`] and [`Vault::merge_tree`]
//! before it syncs on its own; two replicas that each sync a vault alone make different
//! identities. A file renamed or moved by another program is a removed path and a new path, so it
//! gets a new identity.

use crate::frontmatter;
use crate::lock;
use crate::{Error, Place, Properties, Result, State, Vault};
use loro::{
    ExportMode, LoroDoc, LoroMap, LoroText, LoroTree, LoroValue, TreeID, TreeParentId,
    ValueOrContainer, VersionVector,
};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

const KEYS: [&str; 6] = ["state", "when", "due", "pinned", "created", "source"];

/// A middle part longer than this (in characters, both sides multiplied) is replaced in one
/// operation instead of diffed.
const DIFF_LIMIT: usize = 4_000_000;

/// What a sync did.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct SyncReport {
    /// Documents made for buds that had none.
    pub created: usize,
    /// Documents that took operations from an outside edit of their file.
    pub updated: usize,
    /// Files written because their document had moved on.
    pub written: usize,
    /// Buds renamed, moved, trashed or restored on disk to follow the tree document.
    pub moved: usize,
    /// Operations added to the documents, the tree document included.
    pub ops: usize,
}

impl SyncReport {
    pub(crate) fn add(&mut self, other: SyncReport) {
        self.created += other.created;
        self.updated += other.updated;
        self.written += other.written;
        self.moved += other.moved;
        self.ops += other.ops;
    }
}

/// How far each document of a replica has come: version vectors, encoded.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Heads {
    tree: Vec<u8>,
    docs: Vec<(String, Vec<u8>)>,
}

/// The changes one replica sends another: new operations, or a whole document when the other
/// has none.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Updates {
    tree: Option<Vec<u8>>,
    docs: Vec<DocUpdate>,
}

impl Updates {
    pub fn is_empty(&self) -> bool {
        self.tree.is_none() && self.docs.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct DocUpdate {
    id: String,
    whole: bool,
    bytes: Vec<u8>,
}

struct Stored {
    id: String,
    doc: LoroDoc,
    known: String,
}

fn snapshot(doc: &LoroDoc) -> Result<Vec<u8>> {
    doc.export(ExportMode::Snapshot)
        .map_err(|err| Error::Invalid(format!("document export: {err}")))
}

fn open_doc(bytes: &[u8]) -> Result<LoroDoc> {
    LoroDoc::from_snapshot(bytes).map_err(|err| Error::Invalid(format!("document: {err}")))
}

fn text_of(value: Option<ValueOrContainer>) -> Option<String> {
    match value? {
        ValueOrContainer::Value(LoroValue::String(s)) => Some(s.to_string()),
        _ => None,
    }
}

fn flag_of(value: Option<ValueOrContainer>) -> bool {
    matches!(value, Some(ValueOrContainer::Value(LoroValue::Bool(true))))
}

/// The text of each key as the document keeps it; none means the key is absent.
fn wanted(props: &Properties) -> [Option<String>; 6] {
    [
        props.state.map(|s| s.as_str().to_string()),
        props.when.clone(),
        props.due.clone(),
        props.pinned.then(|| "true".to_string()),
        props.created.clone(),
        props.source.clone(),
    ]
}

fn props_of(map: &LoroMap) -> Properties {
    let get = |key: &str| text_of(map.get(key));
    Properties {
        state: get("state").and_then(|s| State::parse(&s)),
        when: get("when"),
        due: get("due"),
        pinned: get("pinned").is_some(),
        created: get("created"),
        source: get("source"),
    }
}

fn set_props(map: &LoroMap, props: &Properties) -> Result<()> {
    for (key, value) in KEYS.iter().zip(wanted(props)) {
        if text_of(map.get(key)) == value {
            continue;
        }
        match value {
            Some(value) => map.insert(key, value.as_str()),
            None => map.delete(key),
        }
        .map_err(|err| Error::Invalid(format!("document: {err}")))?;
    }
    Ok(())
}

/// Whether the document keeps the unknown keys at all: a document made before they travelled has
/// no order entry, and its file is the truth for them until it is looked at once.
fn tracks_layout(doc: &LoroDoc) -> bool {
    text_of(doc.get_map("layout").get("order")).is_some()
}

/// The unknown keys the document holds, in the order it holds for them.
fn layout_of(doc: &LoroDoc) -> frontmatter::Layout {
    let order: Vec<String> = text_of(doc.get_map("layout").get("order"))
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect();
    let map = doc.get_map("extra");
    let mut extras: Vec<(String, String)> = map
        .keys()
        .filter_map(|key| Some((key.to_string(), text_of(map.get(&key))?)))
        .collect();
    let at = |key: &str| order.iter().position(|k| k == key).unwrap_or(usize::MAX);
    extras.sort_by(|a, b| at(&a.0).cmp(&at(&b.0)).then_with(|| a.0.cmp(&b.0)));
    frontmatter::Layout { extras, order }
}

/// Make the document hold the unknown keys of the block `yaml`, each as its lines.
fn set_layout(doc: &LoroDoc, yaml: Option<&str>) -> Result<()> {
    let fail = |err: loro::LoroError| Error::Invalid(format!("document: {err}"));
    let wanted = yaml.map(frontmatter::layout).unwrap_or_default();
    let map = doc.get_map("extra");
    let stale: Vec<String> = map
        .keys()
        .map(|key| key.to_string())
        .filter(|key| !wanted.extras.iter().any(|(k, _)| k == key))
        .collect();
    for key in stale {
        map.delete(&key).map_err(fail)?;
    }
    for (key, text) in &wanted.extras {
        if text_of(map.get(key)).as_deref() != Some(text.as_str()) {
            map.insert(key, text.as_str()).map_err(fail)?;
        }
    }
    let order = wanted.order.join("\n");
    let layout = doc.get_map("layout");
    if text_of(layout.get("order")).as_deref() != Some(order.as_str()) {
        layout.insert("order", order.as_str()).map_err(fail)?;
    }
    Ok(())
}

/// Turn the difference between the text the document has and `new` into text operations.
fn set_text(text: &LoroText, new: &str) -> Result<()> {
    let old: Vec<char> = text.to_string().chars().collect();
    let new: Vec<char> = new.chars().collect();
    let prefix = old.iter().zip(&new).take_while(|(a, b)| a == b).count();
    let suffix = old[prefix..]
        .iter()
        .rev()
        .zip(new[prefix..].iter().rev())
        .take_while(|(a, b)| a == b)
        .count();
    let old = &old[prefix..old.len() - suffix];
    let new = &new[prefix..new.len() - suffix];
    let fail = |err: loro::LoroError| Error::Invalid(format!("document: {err}"));
    if old.len().saturating_mul(new.len()) > DIFF_LIMIT {
        text.delete(prefix, old.len()).map_err(fail)?;
        return text
            .insert(prefix, &new.iter().collect::<String>())
            .map_err(fail);
    }
    let mut pos = prefix;
    for step in diff::slice(old, new) {
        match step {
            diff::Result::Both(..) => pos += 1,
            diff::Result::Left(_) => text.delete(pos, 1).map_err(fail)?,
            diff::Result::Right(c) => {
                text.insert(pos, &c.to_string()).map_err(fail)?;
                pos += 1;
            }
        }
    }
    Ok(())
}

/// Bring `doc` to what `file` says. Returns how many operations that took.
fn absorb(doc: &LoroDoc, file: &str) -> Result<usize> {
    let before = doc.len_ops();
    let (yaml, body) = frontmatter::split(file);
    set_text(&doc.get_text("body"), body)?;
    set_props(
        &doc.get_map("props"),
        &yaml.map(frontmatter::parse).unwrap_or_default(),
    )?;
    set_layout(doc, yaml)?;
    doc.commit();
    Ok(doc.len_ops() - before)
}

fn tree_fail(err: loro::LoroError) -> Error {
    Error::Invalid(format!("tree document: {err}"))
}

/// The tree of buds, keyed by bud identity.
struct Tree {
    doc: LoroDoc,
    tree: LoroTree,
}

impl Tree {
    fn new(doc: LoroDoc) -> Tree {
        let tree = doc.get_tree("buds");
        Tree { doc, tree }
    }

    /// Bud identity to node.
    fn nodes(&self) -> HashMap<String, TreeID> {
        self.tree
            .nodes()
            .into_iter()
            .filter(|node| !self.tree.is_node_deleted(node).unwrap_or(true))
            .filter_map(|node| {
                let id = text_of(self.tree.get_meta(node).ok()?.get("bud"))?;
                Some((id, node))
            })
            .collect()
    }

    fn meta(&self, node: TreeID) -> Result<LoroMap> {
        self.tree.get_meta(node).map_err(tree_fail)
    }

    fn name(&self, node: TreeID) -> Option<String> {
        text_of(self.meta(node).ok()?.get("name"))
    }

    fn place(&self, node: TreeID) -> Option<Place> {
        Place::parse(&text_of(self.meta(node).ok()?.get("place"))?)
    }

    fn own_trashed(&self, node: TreeID) -> bool {
        self.meta(node)
            .map(|meta| flag_of(meta.get("trashed")))
            .unwrap_or(false)
    }

    fn parent(&self, node: TreeID) -> Option<TreeID> {
        match self.tree.parent(node)? {
            TreeParentId::Node(parent) => Some(parent),
            _ => None,
        }
    }

    /// Trashed itself or under a bud that is.
    fn trashed(&self, node: TreeID) -> bool {
        let mut at = Some(node);
        while let Some(node) = at {
            if self.own_trashed(node) {
                return true;
            }
            at = self.parent(node);
        }
        false
    }

    fn depth(&self, node: TreeID) -> usize {
        let mut depth = 0;
        let mut at = self.parent(node);
        while let Some(node) = at {
            depth += 1;
            at = self.parent(node);
        }
        depth
    }

    fn set_name(&self, node: TreeID, name: &str) -> Result<()> {
        self.meta(node)?.insert("name", name).map_err(tree_fail)
    }

    fn set_place(&self, node: TreeID, place: Place) -> Result<()> {
        self.meta(node)?
            .insert("place", place.as_str())
            .map_err(tree_fail)
    }

    fn set_trashed(&self, node: TreeID, trashed: bool) -> Result<()> {
        self.meta(node)?
            .insert("trashed", trashed)
            .map_err(tree_fail)
    }

    fn set_parent(&self, node: TreeID, parent: Option<TreeID>) -> Result<()> {
        let parent = parent.map_or(TreeParentId::Root, TreeParentId::Node);
        self.tree.mov(node, parent).map_err(tree_fail)
    }
}

fn place_root(place: Place) -> Option<&'static str> {
    match place {
        Place::Inbox => Some("Inbox"),
        Place::Archive => Some("Archive"),
        _ => None,
    }
}

impl Vault {
    /// Reconcile every bud with its document: make documents for new buds, turn outside edits of
    /// files into operations, write back what a document has that its file lacks, and record
    /// renames, moves and trashing in the tree document. Call after [`Vault::rescan`].
    pub fn sync(&mut self) -> Result<SyncReport> {
        let mut report = SyncReport::default();
        let buds = self.all()?;
        let live: std::collections::HashSet<&str> = buds.iter().map(|b| b.path.as_str()).collect();
        let stale: Vec<String> = {
            let conn = lock(&self.conn);
            let mut stmt = conn.prepare("SELECT path FROM docs")?;
            let rows = stmt.query_map([], |row| row.get::<_, String>(0))?;
            rows.collect::<std::result::Result<Vec<_>, _>>()?
        };
        let mut tree = self.load_tree()?;
        let nodes = tree.nodes();
        let before = tree.doc.len_ops();
        for path in stale.iter().filter(|p| !live.contains(p.as_str())) {
            let conn = lock(&self.conn);
            let id: Option<String> = conn
                .query_row("SELECT id FROM docs WHERE path = ?1", params![path], |r| {
                    r.get(0)
                })
                .optional()?;
            conn.execute("DELETE FROM docs WHERE path = ?1", params![path])?;
            if let Some(node) = id.and_then(|id| nodes.get(&id)) {
                tree.tree.delete(*node).map_err(tree_fail)?;
            }
        }
        for bud in &buds {
            // A folder the trash only holds for the sake of a bud inside it is not a bud.
            if bud.place == Place::Trash && !bud.path.ends_with(".md") {
                continue;
            }
            report.add(self.sync_path(&bud.path)?);
        }
        self.observe_tree(&mut tree)?;
        tree.doc.commit();
        report.ops += tree.doc.len_ops() - before;
        self.store_tree(&tree.doc)?;
        Ok(report)
    }

    /// How many files differ from what their document knows, or have no document yet: the edits
    /// the next sync will take. Looks at the index, so call after [`Vault::rescan`].
    pub fn pending_changes(&self) -> Result<usize> {
        let known: HashMap<String, String> = {
            let conn = lock(&self.conn);
            let mut stmt = conn.prepare("SELECT path, known_text FROM docs")?;
            let rows = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
            rows.collect::<std::result::Result<_, _>>()?
        };
        let mut pending = 0;
        for bud in self.all()? {
            if !bud.path.ends_with(".md") {
                continue;
            }
            let file = std::fs::read_to_string(self.root.join(&bud.path)).unwrap_or_default();
            if known.get(&bud.path) != Some(&file) {
                pending += 1;
            }
        }
        Ok(pending)
    }

    /// The identity of the bud's document.
    pub fn doc_id(&self, path: &str) -> Result<Option<String>> {
        Ok(lock(&self.conn)
            .query_row("SELECT id FROM docs WHERE path = ?1", params![path], |r| {
                r.get(0)
            })
            .optional()?)
    }

    /// The bud's document as bytes another replica can merge.
    pub fn doc_bytes(&self, path: &str) -> Result<Option<Vec<u8>>> {
        Ok(lock(&self.conn)
            .query_row(
                "SELECT bytes FROM docs WHERE path = ?1",
                params![path],
                |r| r.get(0),
            )
            .optional()?)
    }

    /// The body text the bud's document holds.
    pub fn doc_text(&self, path: &str) -> Result<Option<String>> {
        let Some(bytes) = self.doc_bytes(path)? else {
            return Ok(None);
        };
        Ok(Some(open_doc(&bytes)?.get_text("body").to_string()))
    }

    /// The tree document as bytes another replica can merge.
    pub fn tree_bytes(&self) -> Result<Vec<u8>> {
        snapshot(&self.load_tree()?.doc)
    }

    /// Take the document another replica made for the bud at `path`, under that replica's
    /// identity `id`, and reconcile it with the file there. For a bud this replica has no
    /// document for yet.
    pub fn adopt_doc(&mut self, path: &str, id: &str, bytes: &[u8]) -> Result<SyncReport> {
        self.bud(path)?
            .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
        open_doc(bytes)?;
        lock(&self.conn).execute(
            "INSERT INTO docs (path, id, bytes, known_text) VALUES (?1, ?2, ?3, '')",
            params![path, id, bytes],
        )?;
        self.sync_path(path)
    }

    /// Merge the document bytes another replica holds for the bud with identity `id`, then
    /// write the file if the merged document differs from it.
    pub fn merge_doc(&mut self, id: &str, bytes: &[u8]) -> Result<SyncReport> {
        let path: String = lock(&self.conn)
            .query_row("SELECT path FROM docs WHERE id = ?1", params![id], |r| {
                r.get(0)
            })
            .optional()?
            .ok_or_else(|| Error::NoSuchBud(id.to_string()))?;
        let stored = self.load(&path)?.ok_or(Error::NoSuchBud(path.clone()))?;
        let before = stored.doc.len_ops();
        // An outside edit the document has not seen goes in first, while the document still
        // holds what the file was diffed from; imported changes then merge with it.
        let file = if path.ends_with(".md") {
            std::fs::read_to_string(self.root.join(&path))?
        } else {
            String::new()
        };
        if file != stored.known {
            absorb(&stored.doc, &file)?;
        }
        stored
            .doc
            .import(bytes)
            .map_err(|err| Error::Invalid(format!("document: {err}")))?;
        let ops = stored.doc.len_ops() - before;
        self.store(&path, &stored.id, &stored.doc, Some(&file))?;
        let mut report = self.sync_path(&path)?;
        report.ops += ops;
        Ok(report)
    }

    /// What this replica has: the version of the tree document and of every bud's document. A peer
    /// answers with [`Vault::updates_for`].
    pub fn heads(&self) -> Result<Heads> {
        let rows: Vec<(String, Vec<u8>)> = {
            let conn = lock(&self.conn);
            let mut stmt = conn.prepare("SELECT id, bytes FROM docs ORDER BY id")?;
            let found = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
            found.collect::<std::result::Result<_, _>>()?
        };
        let mut docs = Vec::with_capacity(rows.len());
        for (id, bytes) in rows {
            docs.push((id, open_doc(&bytes)?.oplog_vv().encode()));
        }
        Ok(Heads {
            tree: self.load_tree()?.doc.oplog_vv().encode(),
            docs,
        })
    }

    /// The changes `theirs` lacks: only the new operations of a document the peer has, the whole
    /// document of one it has not, and nothing for what it already holds.
    pub fn updates_for(&self, theirs: &Heads) -> Result<Updates> {
        let seen = |bytes: &[u8]| {
            VersionVector::decode(bytes)
                .map_err(|err| Error::Invalid(format!("document version: {err}")))
        };
        let behind = |doc: &LoroDoc, theirs: &VersionVector| {
            let ours = doc.oplog_vv();
            !matches!(
                ours.partial_cmp(theirs),
                Some(std::cmp::Ordering::Less | std::cmp::Ordering::Equal)
            )
        };
        let export = |doc: &LoroDoc, from: &VersionVector| {
            doc.export(ExportMode::updates(from))
                .map_err(|err| Error::Invalid(format!("document export: {err}")))
        };
        let tree = self.load_tree()?.doc;
        let their_tree = seen(&theirs.tree)?;
        let tree = if behind(&tree, &their_tree) {
            Some(export(&tree, &their_tree)?)
        } else {
            None
        };
        let known: HashMap<&str, &Vec<u8>> = theirs
            .docs
            .iter()
            .map(|(id, vv)| (id.as_str(), vv))
            .collect();
        let rows: Vec<(String, Vec<u8>)> = {
            let conn = lock(&self.conn);
            let mut stmt = conn.prepare("SELECT id, bytes FROM docs ORDER BY id")?;
            let found = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
            found.collect::<std::result::Result<_, _>>()?
        };
        let mut docs = Vec::new();
        for (id, bytes) in rows {
            match known.get(id.as_str()) {
                None => docs.push(DocUpdate {
                    id,
                    whole: true,
                    bytes,
                }),
                Some(vv) => {
                    let doc = open_doc(&bytes)?;
                    let vv = seen(vv)?;
                    if behind(&doc, &vv) {
                        docs.push(DocUpdate {
                            id,
                            whole: false,
                            bytes: export(&doc, &vv)?,
                        });
                    }
                }
            }
        }
        Ok(Updates { tree, docs })
    }

    /// Apply what a peer sent: merge the tree document, merge every document this replica has,
    /// and make a file for each document it has not, where the tree says it belongs. A document
    /// the tree does not place yet waits for the next exchange. Files are written through the
    /// same writers every other edit uses.
    pub fn apply_updates(&mut self, updates: &Updates) -> Result<SyncReport> {
        let mut report = SyncReport::default();
        if let Some(bytes) = &updates.tree {
            report.add(self.merge_tree(bytes)?);
        }
        let mut fresh = Vec::new();
        for update in &updates.docs {
            if self.path_of(&update.id).is_ok() {
                report.add(self.merge_doc(&update.id, &update.bytes)?);
            } else if update.whole {
                fresh.push(update);
            }
        }
        // Parents first, so a bud's folder is there when its children are made.
        let tree = self.load_tree()?;
        let nodes = tree.nodes();
        fresh.sort_by_key(|u| nodes.get(&u.id).map_or(usize::MAX, |n| tree.depth(*n)));
        for update in fresh {
            report.add(self.materialize(&tree, &update.id, &update.bytes)?);
        }
        Ok(report)
    }

    /// Make the file for a document that came from a peer, placed where the tree puts it. A file
    /// already at that place that has no document of its own takes the identity over, as
    /// [`Vault::adopt_doc`] does.
    fn materialize(&mut self, tree: &Tree, id: &str, bytes: &[u8]) -> Result<SyncReport> {
        let Some(node) = tree.nodes().get(id).copied() else {
            return Ok(SyncReport::default());
        };
        if tree.trashed(node) {
            return Ok(SyncReport::default());
        }
        let parent = match tree.parent(node) {
            Some(parent) => {
                let parent_id = tree
                    .nodes()
                    .into_iter()
                    .find_map(|(id, n)| (n == parent).then_some(id));
                let Some(parent_id) = parent_id else {
                    return Ok(SyncReport::default());
                };
                match self.path_of(&parent_id) {
                    Ok(path) => Some(path),
                    Err(_) => return Ok(SyncReport::default()),
                }
            }
            None => place_root(tree.place(node).unwrap_or(Place::Everything)).map(str::to_string),
        };
        let title = tree.name(node).unwrap_or_else(|| "Untitled".to_string());
        let dir = self.parent_dir(parent.as_deref())?;
        let leaf = crate::sanitize_filename(&title);
        let path = if dir.is_empty() {
            format!("{leaf}.md")
        } else {
            format!("{dir}/{leaf}.md")
        };
        if self.bud(&path)?.is_some() {
            if self.doc_id(&path)?.is_some() {
                // Another bud holds the place under its own identity: leave both alone.
                return Ok(SyncReport::default());
            }
            return self.adopt_doc(&path, id, bytes);
        }
        let path = self.create(parent.as_deref(), &title, crate::Kind::Note, None)?;
        // The file starts empty: what it holds comes from the document, not from the defaults
        // `create` writes, which would leave an empty property block behind.
        let absolute = self.root.join(&path);
        crate::edit::write_atomic(&absolute, "")?;
        let mtime = crate::edit::mtime_of(&absolute);
        lock(&self.written).insert(path.clone(), mtime);
        lock(&self.conn).execute(
            "UPDATE buds SET created = NULL, mtime = ?1 WHERE path = ?2",
            params![mtime, path],
        )?;
        let text = String::new();
        lock(&self.conn).execute(
            "INSERT INTO docs (path, id, bytes, known_text) VALUES (?1, ?2, ?3, ?4)",
            params![path, id, bytes, text],
        )?;
        let mut report = self.sync_path(&path)?;
        report.created += 1;
        Ok(report)
    }

    /// Merge the tree document another replica holds, then rename, move, trash and restore
    /// files until the folder matches it.
    pub fn merge_tree(&mut self, bytes: &[u8]) -> Result<SyncReport> {
        let tree = self.load_tree()?;
        let before = tree.doc.len_ops();
        tree.doc
            .import(bytes)
            .map_err(|err| Error::Invalid(format!("tree document: {err}")))?;
        self.store_tree(&tree.doc)?;
        let mut report = SyncReport {
            ops: tree.doc.len_ops() - before,
            ..Default::default()
        };
        self.apply_tree(&tree, &mut report)?;
        Ok(report)
    }

    fn load(&self, path: &str) -> Result<Option<Stored>> {
        let row: Option<(String, Vec<u8>, String)> = lock(&self.conn)
            .query_row(
                "SELECT id, bytes, known_text FROM docs WHERE path = ?1",
                params![path],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?;
        row.map(|(id, bytes, known)| {
            Ok(Stored {
                id,
                doc: open_doc(&bytes)?,
                known,
            })
        })
        .transpose()
    }

    /// Save the document; the known text only when one is given.
    fn store(&self, path: &str, id: &str, doc: &LoroDoc, known: Option<&str>) -> Result<()> {
        let bytes = snapshot(doc)?;
        let conn = lock(&self.conn);
        conn.execute(
            "INSERT INTO docs (path, id, bytes, known_text) VALUES (?1, ?2, ?3, COALESCE(?4, ''))
             ON CONFLICT(path) DO UPDATE SET
                bytes = excluded.bytes, known_text = COALESCE(?4, known_text)",
            params![path, id, bytes, known],
        )?;
        Ok(())
    }

    fn load_tree(&self) -> Result<Tree> {
        let bytes: Option<Vec<u8>> = lock(&self.conn)
            .query_row("SELECT bytes FROM tree_doc WHERE id = 1", [], |r| r.get(0))
            .optional()?;
        Ok(Tree::new(match bytes {
            Some(bytes) => open_doc(&bytes)?,
            None => LoroDoc::new(),
        }))
    }

    fn store_tree(&self, doc: &LoroDoc) -> Result<()> {
        let bytes = snapshot(doc)?;
        lock(&self.conn).execute(
            "INSERT INTO tree_doc (id, bytes) VALUES (1, ?1)
             ON CONFLICT(id) DO UPDATE SET bytes = excluded.bytes",
            params![bytes],
        )?;
        Ok(())
    }

    /// Reconcile one bud with its document.
    fn sync_path(&mut self, path: &str) -> Result<SyncReport> {
        let mut report = SyncReport::default();
        let is_file = path.ends_with(".md");
        let file = if is_file {
            std::fs::read_to_string(self.root.join(path))?
        } else {
            String::new()
        };
        let Some(stored) = self.load(path)? else {
            let id: String =
                lock(&self.conn)
                    .query_row("SELECT lower(hex(randomblob(16)))", [], |r| r.get(0))?;
            let doc = LoroDoc::new();
            report.ops = absorb(&doc, &file)?;
            report.created = 1;
            self.store(path, &id, &doc, Some(&file))?;
            return Ok(report);
        };
        let Stored { id, doc, known } = stored;
        if file != known {
            report.ops = absorb(&doc, &file)?;
            report.updated = 1;
        } else if !tracks_layout(&doc) {
            let before = doc.len_ops();
            set_layout(&doc, frontmatter::split(&file).0)?;
            doc.commit();
            report.ops = doc.len_ops() - before;
        }
        // The document first, so a failed write leaves it with what it was given.
        self.store(path, &id, &doc, None)?;

        let props = props_of(&doc.get_map("props"));
        let body = doc.get_text("body").to_string();
        let (yaml, file_body) = frontmatter::split(&file);
        let file_props = yaml.map(frontmatter::parse).unwrap_or_default();
        let mut path = path.to_string();
        let mut wrote = false;
        let layout = layout_of(&doc);
        if props != file_props || frontmatter::write_layout(&file, &layout) != file {
            self.write_properties(&path, &props, Some(&layout))?;
            if !is_file {
                self.docs_follow(&path, &format!("{path}.md"))?;
                path.push_str(".md");
            }
            wrote = true;
        }
        if body != file_body {
            self.set_body(&path, &body)?;
            wrote = true;
        }
        let known = if wrote {
            std::fs::read_to_string(self.root.join(&path))?
        } else {
            file
        };
        lock(&self.conn).execute(
            "UPDATE docs SET known_text = ?1 WHERE path = ?2",
            params![known, path],
        )?;
        report.written = usize::from(wrote);
        Ok(report)
    }

    fn docs_follow(&self, from: &str, to: &str) -> Result<()> {
        lock(&self.conn).execute(
            "UPDATE docs SET path = ?1 WHERE path = ?2",
            params![to, from],
        )?;
        Ok(())
    }

    /// Record in the tree what the folder has: new buds, renames, moves, trashing.
    fn observe_tree(&self, tree: &mut Tree) -> Result<()> {
        let rows: Vec<(String, String)> = {
            let conn = lock(&self.conn);
            let mut stmt = conn.prepare(
                "SELECT docs.id, docs.path FROM docs JOIN buds ON buds.path = docs.path
                 ORDER BY length(docs.path), docs.path",
            )?;
            let found = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
            found.collect::<std::result::Result<_, _>>()?
        };
        let id_of: HashMap<&str, &str> = rows
            .iter()
            .map(|(id, path)| (path.as_str(), id.as_str()))
            .collect();
        let mut nodes = tree.nodes();
        for (id, path) in &rows {
            let Some(bud) = self.bud(path)? else {
                continue;
            };
            let parent = bud
                .parent
                .as_deref()
                .and_then(|p| id_of.get(p))
                .and_then(|p| nodes.get(*p))
                .copied();
            let trashed = bud.place == Place::Trash;
            let Some(node) = nodes.get(id).copied() else {
                let node = tree
                    .tree
                    .create(parent.map_or(TreeParentId::Root, TreeParentId::Node))
                    .map_err(tree_fail)?;
                let meta = tree.meta(node)?;
                meta.insert("bud", id.as_str()).map_err(tree_fail)?;
                tree.set_name(node, &bud.title)?;
                tree.set_place(node, bud.place)?;
                if trashed {
                    tree.set_trashed(node, true)?;
                }
                nodes.insert(id.clone(), node);
                continue;
            };
            if trashed {
                // A bud under a trashed bud went with it; only the one that was trashed is marked.
                if !tree.trashed(node) {
                    tree.set_trashed(node, true)?;
                }
                continue;
            }
            if tree.own_trashed(node) {
                tree.set_trashed(node, false)?;
            }
            if tree.name(node).as_deref() != Some(bud.title.as_str()) {
                tree.set_name(node, &bud.title)?;
            }
            if parent.is_none() && tree.place(node) != Some(bud.place) {
                tree.set_place(node, bud.place)?;
            }
            if tree.parent(node) != parent {
                tree.set_parent(node, parent)?;
            }
        }
        Ok(())
    }

    /// Make the folder follow the tree: parents first, so a bud's place is settled before its
    /// children are looked at.
    fn apply_tree(&mut self, tree: &Tree, report: &mut SyncReport) -> Result<()> {
        let nodes = tree.nodes();
        let mut order: Vec<(usize, String, TreeID)> = nodes
            .iter()
            .map(|(id, node)| (tree.depth(*node), id.clone(), *node))
            .collect();
        order.sort();
        for (_, id, node) in order {
            let path: Option<String> = lock(&self.conn)
                .query_row("SELECT path FROM docs WHERE id = ?1", params![id], |r| {
                    r.get(0)
                })
                .optional()?;
            let Some(mut path) = path else { continue };
            let Some(mut bud) = self.bud(&path)? else {
                continue;
            };
            if tree.trashed(node) {
                if bud.place != Place::Trash {
                    self.trash(&path)?;
                    report.moved += 1;
                }
                continue;
            }
            if bud.place == Place::Trash {
                path = self.restore(&path)?;
                report.moved += 1;
                bud = self.bud(&path)?.ok_or(Error::NoSuchBud(path.clone()))?;
            }
            if let Some(name) = tree.name(node).filter(|name| *name != bud.title) {
                path = self.rename(&path, &name)?;
                report.moved += 1;
                bud = self.bud(&path)?.ok_or(Error::NoSuchBud(path.clone()))?;
            }
            let parent = match tree.parent(node) {
                Some(parent) => {
                    let parent_id = tree
                        .nodes()
                        .into_iter()
                        .find_map(|(id, n)| (n == parent).then_some(id));
                    match parent_id {
                        Some(parent_id) => Some(self.path_of(&parent_id)?),
                        None => continue,
                    }
                }
                None => None,
            };
            let settled = match &parent {
                Some(parent) => bud.parent.as_deref() == Some(parent.as_str()),
                None => {
                    let place = tree.place(node).unwrap_or(Place::Everything);
                    bud.parent.is_none() && bud.place == place
                }
            };
            if !settled {
                let target = match &parent {
                    Some(parent) => Some(parent.as_str()),
                    None => place_root(tree.place(node).unwrap_or(Place::Everything)),
                };
                self.move_to(&path, target)?;
                report.moved += 1;
            }
        }
        Ok(())
    }

    fn path_of(&self, id: &str) -> Result<String> {
        lock(&self.conn)
            .query_row("SELECT path FROM docs WHERE id = ?1", params![id], |r| {
                r.get(0)
            })
            .optional()?
            .ok_or_else(|| Error::NoSuchBud(id.to_string()))
    }
}
