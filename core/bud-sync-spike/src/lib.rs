//! Shared plumbing for the spike: the fixture loader, a deterministic edit
//! generator and a tiny timer. Neither CRDT library is used here.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

pub const BODY_EDITS: usize = 1_000;
pub const CONCURRENT_EDITS: usize = 200;

/// One bud: its path relative to the vault, its frontmatter pairs and its body.
pub struct Bud {
    pub path: String,
    pub props: Vec<(String, String)>,
    pub body: String,
}

/// An edit expressed in fractions so it applies to any body length.
#[derive(Clone)]
pub struct Edit {
    pub bud: usize,
    pub at: f64,
    pub delete: usize,
    pub insert: String,
}

pub fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../bud-core/tests/fixtures/vault")
}

pub fn load_vault(root: &Path) -> Vec<Bud> {
    let mut found = Vec::new();
    walk(root, root, &mut found);
    found.sort_by(|a, b| a.path.cmp(&b.path));
    found
}

fn walk(root: &Path, dir: &Path, out: &mut Vec<Bud>) {
    let mut entries: Vec<_> = fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).collect();
    entries.sort();
    for path in entries {
        let name = path.file_name().unwrap().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        if path.is_dir() {
            walk(root, &path, out);
        } else if name.ends_with(".md") {
            let text = fs::read_to_string(&path).unwrap();
            let rel = path.strip_prefix(root).unwrap().to_string_lossy().to_string();
            out.push(parse(&rel, &text));
        }
    }
}

fn parse(path: &str, text: &str) -> Bud {
    let mut props = Vec::new();
    let mut body = text;
    if let Some(rest) = text.strip_prefix("---\n") {
        if let Some(end) = rest.find("\n---\n").map(|i| (i, 5)).or_else(|| {
            rest.strip_suffix("\n---").map(|r| (r.len(), 4))
        }) {
            for line in rest[..end.0].lines() {
                if let Some((k, v)) = line.split_once(':') {
                    props.push((k.trim().to_string(), v.trim().to_string()));
                }
            }
            body = rest.get(end.0 + end.1..).unwrap_or("");
        }
    }
    Bud { path: path.to_string(), props, body: body.to_string() }
}

/// Deterministic xorshift generator, so both libraries see the same edits.
pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Rng(seed.max(1))
    }
    pub fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    pub fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }
}

const WORDS: [&str; 8] = ["paper", "issue", "warm", "draft", "inbox", "name", "ship", "reader"];

pub fn make_edits(rng: &mut Rng, buds: usize, count: usize) -> Vec<Edit> {
    (0..count)
        .map(|_| {
            let bud = (rng.next() as usize) % buds;
            let at = rng.unit();
            let delete = if rng.next() % 4 == 0 { (rng.next() % 6) as usize } else { 0 };
            let insert = if rng.next() % 5 == 0 {
                String::new()
            } else {
                let w = WORDS[(rng.next() as usize) % WORDS.len()];
                format!("{w} ")
            };
            Edit { bud, at, delete, insert }
        })
        .collect()
}

/// Turn a fractional position into a char index and a clamped delete length.
pub fn resolve(edit: &Edit, len_chars: usize) -> (usize, usize) {
    let pos = ((edit.at * (len_chars as f64 + 1.0)) as usize).min(len_chars);
    (pos, edit.delete.min(len_chars - pos))
}

pub fn time<T>(f: impl FnOnce() -> T) -> (T, f64) {
    let start = Instant::now();
    let value = f();
    (value, start.elapsed().as_secs_f64() * 1000.0)
}

/// Median of several timed runs, in milliseconds.
pub fn median_ms(runs: usize, mut f: impl FnMut() -> f64) -> f64 {
    let mut all: Vec<f64> = (0..runs).map(|_| f()).collect();
    all.sort_by(|a, b| a.partial_cmp(b).unwrap());
    all[all.len() / 2]
}

pub fn report(lib: &str, rows: &[(&str, String)]) {
    println!("library: {lib}");
    for (k, v) in rows {
        println!("  {k}: {v}");
    }
}
