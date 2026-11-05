//! Tags: the `tags` key of a bud's frontmatter and the `#tags` in its prose. The index keeps each
//! tag a bud carries once, under the bud's row like its links, with where it was written. Tags
//! compare without case, accented letters included: `#Home` and `#home` are one tag, shown the
//! way most buds write it.
//!
//! The frontmatter key stays the file's own text (an unknown key to [`crate::Properties`]), so
//! reading tags never rewrites a file.

use crate::{frontmatter, lock, prose, read_bud, Bud, Error, Result, Vault, SELECT};
use rusqlite::{params, Connection};

/// Where a bud's tag was written.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TagOrigin {
    Frontmatter,
    Body,
}

impl TagOrigin {
    fn as_str(self) -> &'static str {
        match self {
            TagOrigin::Frontmatter => "frontmatter",
            TagOrigin::Body => "body",
        }
    }
}

/// A tag and how many buds carry it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TagCount {
    pub tag: String,
    pub buds: usize,
}

/// A character a tag can hold: a letter, a digit, `_`, `-` or `/` (for nested tags).
fn tag_char(c: char) -> bool {
    c.is_alphanumeric() || matches!(c, '_' | '-' | '/')
}

/// A tag as written, without a leading `#` and trailing `/`; none when it holds no letter (`#1`
/// and `#-` are not tags) or anything a tag cannot.
fn clean(raw: &str) -> Option<String> {
    let tag = raw.trim().trim_start_matches('#').trim_end_matches('/');
    let ok = tag.chars().all(tag_char) && tag.chars().any(char::is_alphabetic);
    ok.then(|| tag.to_string())
}

/// What two spellings of one tag share.
fn key(tag: &str) -> String {
    tag.to_lowercase()
}

/// The tags of a frontmatter block: `tags: [a, b]`, a list under the key, or one string of tags
/// split on commas and spaces.
pub(crate) fn from_frontmatter(yaml: &str) -> Vec<String> {
    let Ok(value) = serde_yaml::from_str::<serde_yaml::Value>(yaml) else {
        return Vec::new();
    };
    let words: Vec<String> = match value.get("tags") {
        Some(serde_yaml::Value::Sequence(items)) => items
            .iter()
            .filter_map(|item| match item {
                serde_yaml::Value::String(s) => Some(s.clone()),
                serde_yaml::Value::Number(n) => Some(n.to_string()),
                _ => None,
            })
            .collect(),
        Some(serde_yaml::Value::String(s)) => s.split([',', ' ']).map(str::to_string).collect(),
        _ => Vec::new(),
    };
    words.iter().filter_map(|w| clean(w)).collect()
}

/// The `#tags` in a body's prose: a `#` at the start of a line or after a space or a comma, then
/// tag characters. A heading's `# ` is not a tag, nor is a `#` inside a word or a
/// link (`page#part`, `[[Note#Part]]`), nor anything in code.
pub(crate) fn from_body(body: &str) -> Vec<String> {
    spans(body).into_iter().map(|(_, tag)| tag).collect()
}

/// Each `#tag` of a body with the byte offset of its first character after the `#`.
fn spans(body: &str) -> Vec<(usize, String)> {
    let mut out = Vec::new();
    for (start, line) in prose::lines(body) {
        let mut previous: Option<char> = None;
        let mut chars = line.char_indices().peekable();
        while let Some((i, c)) = chars.next() {
            let starts = c == '#' && previous.is_none_or(|p| p.is_whitespace() || p == ',');
            if starts {
                let rest = &line[i + 1..];
                let len = rest.find(|c: char| !tag_char(c)).unwrap_or(rest.len());
                if let Some(tag) = clean(&rest[..len]) {
                    out.push((start + i + 1, tag));
                }
                for _ in 0..rest[..len].chars().count() {
                    chars.next();
                }
                previous = rest[..len].chars().last().or(Some('#'));
                continue;
            }
            previous = Some(c);
        }
    }
    out
}

/// A change to the tags a bud carries.
#[derive(Clone, Copy)]
enum Change<'a> {
    Add(&'a str),
    Remove(&'a str),
    /// `from` and the tags nested under it (`from/x`) take `to` in its place.
    Rename {
        from: &'a str,
        to: &'a str,
    },
}

/// `tag` with `from`, in any case, swapped for `to` when it is `from` or nested under it.
fn renamed(tag: &str, from: &str, to: &str) -> Option<String> {
    let cut = tag
        .char_indices()
        .nth(from.chars().count())
        .map_or(tag.len(), |(i, _)| i);
    let (head, rest) = tag.split_at(cut);
    (key(head) == key(from) && (rest.is_empty() || rest.starts_with('/')))
        .then(|| format!("{to}{rest}"))
}

/// One entry of a frontmatter tag list: its text as written and the tag it reads as.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Item {
    raw: String,
    tag: Option<String>,
}

impl Item {
    fn written(raw: &str) -> Item {
        let (value, _) = comment(raw);
        let value = value.trim();
        let unquoted = value
            .strip_prefix('\'')
            .and_then(|r| r.strip_suffix('\''))
            .or_else(|| value.strip_prefix('"').and_then(|r| r.strip_suffix('"')))
            .unwrap_or(value);
        Item {
            raw: raw.to_string(),
            tag: clean(unquoted),
        }
    }

    fn new(tag: &str) -> Item {
        Item {
            raw: frontmatter::scalar(tag),
            tag: Some(tag.to_string()),
        }
    }

    fn is(&self, tag: &str) -> bool {
        self.tag.as_deref().is_some_and(|own| key(own) == key(tag))
    }
}

/// Calls `at` with each character of `text` outside quotes and the character before it, until
/// `at` returns true. A quote opens only where a scalar starts (first, or after a space, a tab,
/// `[` or `,`), so the `'` in `don't` is a letter; inside double quotes a backslash escapes.
fn outside_quotes(text: &str, mut at: impl FnMut(usize, char, Option<char>) -> bool) {
    let mut quote: Option<char> = None;
    let mut escaped = false;
    let mut previous: Option<char> = None;
    for (i, c) in text.char_indices() {
        match quote {
            Some('"') if escaped => escaped = false,
            Some('"') if c == '\\' => escaped = true,
            Some(q) if c == q => quote = None,
            Some(_) => {}
            None if c == '"' || c == '\'' => {
                let starts = previous.is_none_or(|p| matches!(p, ' ' | '\t' | '[' | ','));
                // `''` inside single quotes closes and opens again: one quote character.
                if starts || (c == '\'' && previous == Some('\'')) {
                    quote = Some(c);
                }
            }
            None => {
                if at(i, c, previous) {
                    return;
                }
            }
        }
        previous = Some(c);
    }
}

/// `text` split before a YAML comment: a `#` at the start or after a space or tab, outside
/// quotes. The comment keeps the space before it.
fn comment(text: &str) -> (&str, &str) {
    let mut cut = text.len();
    outside_quotes(text, |i, c, previous| {
        let found = c == '#' && previous.is_none_or(|p| p == ' ' || p == '\t');
        if found {
            cut = text[..i].trim_end_matches([' ', '\t']).len();
        }
        found
    });
    text.split_at(cut)
}

/// The items of a one-line flow list's inside, split on commas outside quotes.
fn flow_items(inner: &str) -> Vec<Item> {
    let mut cuts = vec![];
    outside_quotes(inner, |i, c, _| {
        if c == ',' {
            cuts.push(i);
        }
        false
    });
    let mut out = Vec::new();
    let mut from = 0;
    for cut in cuts {
        out.push(&inner[from..cut]);
        from = cut + 1;
    }
    out.push(&inner[from..]);
    out.into_iter()
        .map(str::trim)
        .filter(|raw| !raw.is_empty())
        .map(Item::written)
        .collect()
}

/// How a file writes its `tags` key, so an edit writes it back the same way.
enum Shape {
    /// `tags: [a, b]`
    Flow,
    /// `tags:` and one `- a` line per tag, with the indent before the dash.
    Block(String),
    /// `tags: a, b` or `tags: a b`: one string, with what goes between tags.
    Words(&'static str),
}

/// The tag list after `change`, or none when it changes nothing. A rename that lands on a tag
/// the list has already merges the two; other repeats the file wrote stay.
fn changed(items: &[Item], change: Change<'_>) -> Option<Vec<Item>> {
    let mut out = items.to_vec();
    match change {
        Change::Add(tag) => {
            if !out.iter().any(|item| item.is(tag)) {
                out.push(Item::new(tag));
            }
        }
        Change::Remove(tag) => out.retain(|item| !item.is(tag)),
        Change::Rename { from, to } => {
            let mut landed = std::collections::HashSet::new();
            for item in &mut out {
                if let Some(new) = item.tag.as_deref().and_then(|tag| renamed(tag, from, to)) {
                    landed.insert(key(&new));
                    *item = Item::new(&new);
                }
            }
            let mut seen = std::collections::HashSet::new();
            out.retain(|item| {
                item.tag
                    .as_deref()
                    .map(key)
                    .is_none_or(|k| !landed.contains(&k) || seen.insert(k))
            });
        }
    }
    (out != items).then_some(out)
}

/// The `tags` key as lines; empty when no entry is left. `note` is a comment the key line had.
fn write_key(shape: &Shape, items: &[Item], note: &str, eol: &str) -> String {
    if items.iter().all(|item| item.raw.starts_with('#')) {
        return String::new();
    }
    let raws: Vec<&str> = items.iter().map(|item| item.raw.as_str()).collect();
    match shape {
        // Words are not quoted, so a tag that needs quotes turns the string into a flow list.
        Shape::Words(between) if !raws.iter().any(|raw| raw.starts_with(['"', '\''])) => {
            format!("tags: {}{note}{eol}", raws.join(between))
        }
        Shape::Block(indent) => {
            let mut out = format!("tags:{note}{eol}");
            for raw in raws {
                let dash = if raw.starts_with('#') { "" } else { "- " };
                out.push_str(&format!("{indent}{dash}{raw}{eol}"));
            }
            out
        }
        _ => format!("tags: [{}]{note}{eol}", raws.join(", ")),
    }
}

/// The shape, entries and key-line comment of a `tags` key, from its line and the lines that
/// continue it.
fn read_key(chunk: &str) -> (Shape, Vec<Item>, String) {
    let mut lines = chunk.lines();
    let first = lines.next().unwrap_or("");
    let after = first.split_once(':').map_or("", |(_, value)| value);
    let (value, note) = comment(after);
    let value = value.trim();
    let rest: Vec<&str> = lines.filter(|line| !line.trim().is_empty()).collect();
    let inner = value
        .strip_prefix('[')
        .and_then(|v| v.strip_suffix(']'))
        .filter(|inner| !inner.contains(['[', ']', '{', '}']));
    if let (true, Some(inner)) = (rest.is_empty(), inner) {
        return (Shape::Flow, flow_items(inner), note.to_string());
    }
    let dashed = |line: &&str| line.trim_start().starts_with("- ") || line.trim() == "-";
    let remark = |line: &&str| line.trim_start().starts_with('#');
    let items_at = rest.iter().position(dashed);
    if let (true, Some(first)) = (value.is_empty(), items_at) {
        if rest.iter().all(|line| dashed(line) || remark(line)) {
            let line = rest[first];
            let indent = line[..line.len() - line.trim_start().len()].to_string();
            // A comment line stays where it is, as an entry that is no tag.
            let items = rest
                .iter()
                .filter_map(|line| {
                    let line = line.trim_start();
                    match line.strip_prefix('-') {
                        Some(raw) => Some(raw.trim())
                            .filter(|raw| !raw.is_empty())
                            .map(Item::written),
                        None => Some(Item {
                            raw: line.trim_end().to_string(),
                            tag: None,
                        }),
                    }
                })
                .collect();
            return (Shape::Block(indent), items, note.to_string());
        }
    }
    let plain = !value.starts_with(['"', '\'', '[', '{', '|', '>', '&', '*', '!']);
    if rest.is_empty() && plain && !value.is_empty() {
        let between = if value.contains(',') { ", " } else { " " };
        let items = value
            .split([',', ' '])
            .filter(|raw| !raw.is_empty())
            .map(Item::written)
            .collect();
        return (Shape::Words(between), items, note.to_string());
    }
    // Any other way of writing the list is read the lenient way and written back as a flow list.
    let items = from_frontmatter(chunk)
        .iter()
        .map(|tag| Item::new(tag))
        .collect();
    let note = if rest.is_empty() { note } else { "" };
    (Shape::Flow, items, note.to_string())
}

/// Whether a line of a block starts the `tags` key: `tags:` or `tags :`.
fn is_tags_line(line: &str) -> bool {
    line.strip_prefix("tags")
        .is_some_and(|rest| rest.trim_start_matches([' ', '\t']).starts_with(':'))
}

/// The lines from `at` that belong to the key starting there: indented lines, a flow list's
/// lines up to its `]`, and for a key with no value its unindented `- ` lines. A blank line
/// belongs when more of the key follows it.
fn key_end(lines: &[&str], at: usize) -> usize {
    let after = lines[at].split_once(':').map_or("", |(_, value)| value);
    let value = comment(after).0.trim();
    let mut end = at + 1;
    if value.starts_with('[') && !value.ends_with(']') {
        while end < lines.len() {
            end += 1;
            if lines[end - 1].contains(']') {
                break;
            }
        }
        return end;
    }
    let mut last = end;
    while end < lines.len() {
        let line = lines[end];
        let indented = line.starts_with([' ', '\t']) && !line.trim().is_empty();
        let dashed = value.is_empty() && line.starts_with('-');
        if indented || dashed {
            end += 1;
            last = end;
        } else if line.trim().is_empty() {
            end += 1;
        } else {
            break;
        }
    }
    last
}

/// `text` with `change` made to the `tags` key of its frontmatter, or none when that changes
/// nothing. Every other line of the file stays as it was, and a list keeps the way it is written.
/// A file with no `tags` key gets `tags: [tag]` at the end of its block, made when it has none;
/// a block left with nothing in it goes.
fn rewrite_frontmatter(text: &str, change: Change<'_>) -> Option<String> {
    let first = text.split_inclusive('\n').next().unwrap_or("");
    let file_eol = if first.ends_with("\r\n") {
        "\r\n"
    } else {
        "\n"
    };
    let (Some(yaml), body) = frontmatter::split(text) else {
        let Change::Add(tag) = change else {
            return None;
        };
        let line = write_key(&Shape::Flow, &[Item::new(tag)], "", file_eol);
        return Some(format!("---{file_eol}{line}---{file_eol}{text}"));
    };
    let open = if text.starts_with("---\r\n") { 5 } else { 4 };
    let close = &text[open + yaml.len()..text.len() - body.len()];

    let mut lines: Vec<&str> = yaml.split_inclusive('\n').collect();
    let block = match lines.iter().position(|line| is_tags_line(line)) {
        None => {
            let Change::Add(tag) = change else {
                return None;
            };
            let mut block = yaml.to_string();
            if !block.is_empty() && !block.ends_with('\n') {
                block.push_str(file_eol);
            }
            block.push_str(&write_key(&Shape::Flow, &[Item::new(tag)], "", file_eol));
            block
        }
        Some(at) => {
            let end = key_end(&lines, at);
            let chunk: String = lines[at..end].concat();
            let eol = if lines[at].ends_with("\r\n") {
                "\r\n"
            } else {
                file_eol
            };
            let (shape, items, note) = read_key(&chunk);
            let after = changed(&items, change)?;
            let written = write_key(&shape, &after, &note, eol);
            lines.splice(at..end, [written.as_str()]);
            lines.concat()
        }
    };
    // A body that starts with a fence of its own would read as the block once this one went.
    let body_fenced = body
        .lines()
        .next()
        .is_some_and(|line| line.trim_end() == "---");
    if block.trim().is_empty() && !body_fenced {
        return Some(body.to_string());
    }
    Some(format!("{}{block}{close}{body}", &text[..open]))
}

/// The tags a frontmatter block should read as once `change` is made, by key.
fn expected(yaml: &str, change: Change<'_>) -> std::collections::BTreeSet<String> {
    let mut tags: Vec<String> = from_frontmatter(yaml);
    match change {
        Change::Add(tag) => tags.push(tag.to_string()),
        Change::Remove(tag) => tags.retain(|own| key(own) != key(tag)),
        Change::Rename { from, to } => {
            for own in &mut tags {
                if let Some(new) = renamed(own, from, to) {
                    *own = new;
                }
            }
        }
    }
    tags.iter().map(|tag| key(tag)).collect()
}

/// [`rewrite_frontmatter`], checked: the new block must parse whenever the old one did, keep
/// every property it had, and read as exactly the tags the change asks for. A file whose list
/// cannot be rewritten that way is refused rather than written.
fn write_frontmatter(text: &str, change: Change<'_>) -> Result<Option<String>> {
    let old = frontmatter::split(text).0.unwrap_or("");
    let keys = |yaml: &str| -> std::collections::BTreeSet<String> {
        from_frontmatter(yaml).iter().map(|tag| key(tag)).collect()
    };
    let Some(written) = rewrite_frontmatter(text, change) else {
        // Nothing to write must mean nothing to change, not a list read wrong.
        if keys(old) != expected(old, change) {
            return Err(refused());
        }
        return Ok(None);
    };
    let new = frontmatter::split(&written).0.unwrap_or("");
    let parses = |yaml: &str| serde_yaml::from_str::<serde_yaml::Value>(yaml).is_ok();
    let sound = (parses(new) || !parses(old))
        && frontmatter::parse(new) == frontmatter::parse(old)
        && keys(new) == expected(old, change)
        && frontmatter::split(&written).1 == frontmatter::split(text).1;
    if !sound {
        return Err(refused());
    }
    Ok(Some(written))
}

fn refused() -> Error {
    Error::Invalid(
        "the tags in this file are written in a way Bud cannot change safely".to_string(),
    )
}

/// `body` with every `#from`, and every tag nested under it, renamed to `to`; none when it has
/// none.
fn rename_in_body(body: &str, from: &str, to: &str) -> Option<String> {
    let mut out = body.to_string();
    let mut any = false;
    for (start, tag) in spans(body).into_iter().rev() {
        if let Some(new) = renamed(&tag, from, to) {
            out.replace_range(start..start + tag.len(), &new);
            any = true;
        }
    }
    any.then_some(out)
}

/// One file a tag change rewrote: its text before and after, so the change can be undone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TagEdit {
    pub path: String,
    pub before: String,
    pub after: String,
}

/// Replace the tags of the bud at `path` with the ones in its frontmatter and body. A tag
/// written both ways counts once, as frontmatter.
pub(crate) fn retag(conn: &Connection, path: &str, yaml: Option<&str>, body: &str) -> Result<()> {
    let row: i64 = conn.query_row(
        "SELECT rowid FROM buds WHERE path = ?1",
        params![path],
        |r| r.get(0),
    )?;
    conn.execute("DELETE FROM bud_tags WHERE source = ?1", params![row])?;
    let mut insert = conn.prepare_cached(
        "INSERT OR IGNORE INTO bud_tags (source, key, tag, origin, position)
         VALUES (?1, ?2, ?3, ?4, ?5)",
    )?;
    let front = yaml.map(from_frontmatter).unwrap_or_default();
    let found = front
        .into_iter()
        .map(|tag| (tag, TagOrigin::Frontmatter))
        .chain(
            from_body(body)
                .into_iter()
                .map(|tag| (tag, TagOrigin::Body)),
        );
    for (position, (tag, origin)) in found.enumerate() {
        insert.execute(params![
            row,
            key(&tag),
            tag,
            origin.as_str(),
            position as i64
        ])?;
    }
    Ok(())
}

impl Vault {
    /// Every tag outside the Trash with the number of buds that carry it, most used first, each
    /// shown the way most of its buds write it (the first in order on a tie).
    pub fn tags(&self) -> Result<Vec<TagCount>> {
        let conn = lock(&self.conn);
        let mut stmt = conn.prepare(
            "SELECT bud_tags.key, bud_tags.tag, count(*) FROM bud_tags
             JOIN buds ON buds.rowid = bud_tags.source WHERE buds.place != 'trash'
             GROUP BY bud_tags.key, bud_tags.tag ORDER BY bud_tags.key, count(*) DESC, bud_tags.tag",
        )?;
        let rows: Vec<(String, String, i64)> = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
            .collect::<std::result::Result<_, _>>()?;
        let mut out: Vec<TagCount> = Vec::new();
        let mut last_key: Option<String> = None;
        for (key, tag, buds) in rows {
            let buds = usize::try_from(buds).unwrap_or(0);
            match out.last_mut() {
                // Spellings of one key come together, the most used first: it names the tag.
                Some(last) if last_key.as_deref() == Some(key.as_str()) => last.buds += buds,
                _ => out.push(TagCount { tag, buds }),
            }
            last_key = Some(key);
        }
        out.sort_by(|a, b| {
            b.buds
                .cmp(&a.buds)
                .then_with(|| a.tag.to_lowercase().cmp(&b.tag.to_lowercase()))
        });
        Ok(out)
    }

    /// The tags of the bud at `path`, in the order the file gives them.
    pub fn tags_of(&self, path: &str) -> Result<Vec<String>> {
        let conn = lock(&self.conn);
        let mut stmt = conn.prepare(
            "SELECT bud_tags.tag FROM bud_tags JOIN buds ON buds.rowid = bud_tags.source
             WHERE buds.path = ?1 ORDER BY bud_tags.position",
        )?;
        let rows = stmt.query_map(params![path], |r| r.get(0))?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Add `tag` to the frontmatter of the bud at `path`; a list that has it already, in any
    /// case, is left as it is. A `#tag` in the body does not count: the list is the bud's own.
    pub fn add_tag(&mut self, path: &str, tag: &str) -> Result<()> {
        let tag = clean(tag).ok_or_else(|| Error::Invalid(format!("not a tag: {tag}")))?;
        self.change_frontmatter(path, Change::Add(&tag)).map(|_| ())
    }

    /// Take `tag` out of the frontmatter of the bud at `path`. A `#tag` in its body stays: that
    /// is the bud's own text. Returns the file's text before and after, when it rewrote one.
    pub fn remove_tag(&mut self, path: &str, tag: &str) -> Result<Option<TagEdit>> {
        let tag = clean(tag).ok_or_else(|| Error::Invalid(format!("not a tag: {tag}")))?;
        self.change_frontmatter(path, Change::Remove(&tag))
    }

    /// Rename `from` to `to` in every bud outside the Trash, in frontmatter lists and `#tags`
    /// alike, and the tags nested under it with it (`#home/kitchen` becomes `#house/kitchen`).
    /// Renaming onto a tag in use merges the two. Returns each file it rewrote, before and after.
    pub fn rename_tag(&mut self, from: &str, to: &str) -> Result<Vec<TagEdit>> {
        let from = clean(from).ok_or_else(|| Error::Invalid(format!("not a tag: {from}")))?;
        let to = clean(to).ok_or_else(|| Error::Invalid(format!("not a tag: {to}")))?;
        if from == to {
            return Ok(Vec::new());
        }
        let paths: Vec<String> = {
            let conn = lock(&self.conn);
            let mut stmt = conn.prepare(
                "SELECT DISTINCT buds.path FROM bud_tags JOIN buds ON buds.rowid = bud_tags.source
                 WHERE buds.place != 'trash' AND buds.path LIKE '%.md'
                 AND (bud_tags.key = ?1 OR substr(bud_tags.key, 1, length(?1) + 1) = ?1 || '/')
                 ORDER BY buds.path",
            )?;
            let rows = stmt.query_map(params![key(&from)], |r| r.get(0))?;
            rows.collect::<std::result::Result<_, _>>()?
        };
        let mut edits = Vec::new();
        for path in paths {
            let before = std::fs::read_to_string(self.root.join(&path))?;
            let change = Change::Rename {
                from: &from,
                to: &to,
            };
            // A list that cannot be rewritten safely stays as it is; the body is still renamed.
            let written = write_frontmatter(&before, change).ok().flatten();
            let mut after = written.unwrap_or_else(|| before.clone());
            let (_, body) = frontmatter::split(&after);
            if let Some(body_after) = rename_in_body(body, &from, &to) {
                after = format!("{}{body_after}", &after[..after.len() - body.len()]);
            }
            if after != before {
                self.write_file(&path, &after, None)?;
                edits.push(TagEdit {
                    path,
                    before,
                    after,
                });
            }
        }
        Ok(edits)
    }

    /// Put back the text a file had before a tag rename, when the file still holds `expected`,
    /// the text the rename wrote: an edit made since is never undone. Returns whether it wrote.
    pub fn restore_text(&mut self, path: &str, expected: &str, text: &str) -> Result<bool> {
        let now = std::fs::read_to_string(self.root.join(path))?;
        if now != expected {
            return Ok(false);
        }
        self.write_file(path, text, None)?;
        Ok(true)
    }

    fn change_frontmatter(&mut self, path: &str, change: Change<'_>) -> Result<Option<TagEdit>> {
        self.bud(path)?
            .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
        let text = if path.ends_with(".md") {
            std::fs::read_to_string(self.root.join(path))?
        } else {
            String::new()
        };
        let Some(written) = write_frontmatter(&text, change)? else {
            return Ok(None);
        };
        self.write_file(path, &written, None)?;
        Ok(path.ends_with(".md").then(|| TagEdit {
            path: path.to_string(),
            before: text,
            after: written,
        }))
    }

    /// The buds outside the Trash that carry `tag`, in any case, by path.
    pub fn tagged(&self, tag: &str) -> Result<Vec<Bud>> {
        let Some(tag) = clean(tag) else {
            return Ok(Vec::new());
        };
        let conn = lock(&self.conn);
        let mut stmt = conn.prepare(&format!(
            "{SELECT} WHERE place != 'trash' AND rowid IN
             (SELECT source FROM bud_tags WHERE key = ?1) ORDER BY path"
        ))?;
        let rows = stmt.query_map(params![key(&tag)], read_bud)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }
}

#[cfg(test)]
mod tests {
    use super::{from_body, from_frontmatter};

    #[test]
    fn frontmatter_tags_come_as_a_list_or_one_string() {
        assert_eq!(
            from_frontmatter("tags: [home, '#work', 2026]\n"),
            ["home", "work"]
        );
        assert_eq!(
            from_frontmatter("tags:\n  - garden/roses\n  - kitchen\n"),
            ["garden/roses", "kitchen"]
        );
        assert_eq!(
            from_frontmatter("tags: home, work errands\n"),
            ["home", "work", "errands"]
        );
        assert!(from_frontmatter("title: no tags\n").is_empty());
        assert_eq!(from_frontmatter("tags: [has space, ok]\n"), ["ok"]);
    }

    #[test]
    fn body_tags_start_a_word_and_stay_out_of_code_and_headings() {
        let body = "# Heading\n## Another\nBuy #milk, #eggs, not page#part, [see](#setup), #- or #1.\n`#code` then #après-ski #a/b/\n```\n#fenced\n```\n[[Note#Part]] #end";
        assert_eq!(from_body(body), ["milk", "eggs", "après-ski", "a/b", "end"]);
    }
}
