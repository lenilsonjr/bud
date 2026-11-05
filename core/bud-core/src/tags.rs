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
        let unquoted = raw
            .strip_prefix('\'')
            .and_then(|r| r.strip_suffix('\''))
            .or_else(|| raw.strip_prefix('"').and_then(|r| r.strip_suffix('"')))
            .unwrap_or(raw);
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

/// How a file writes its `tags` key, so an edit writes it back the same way.
enum Shape {
    /// `tags: [a, b]`
    Flow,
    /// `tags:` and one `- a` line per tag, with the indent before the dash.
    Block(String),
    /// `tags: a, b` or `tags: a b`: one string, with what goes between tags.
    Words(&'static str),
}

/// The tag list after `change`, or none when it changes nothing.
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
            for item in &mut out {
                if let Some(new) = item.tag.as_deref().and_then(|tag| renamed(tag, from, to)) {
                    *item = Item::new(&new);
                }
            }
            // A rename onto a tag the list has already merges the two.
            let mut seen = std::collections::HashSet::new();
            out.retain(|item| item.tag.as_deref().is_none_or(|tag| seen.insert(key(tag))));
        }
    }
    (out != items).then_some(out)
}

/// The `tags` key of a frontmatter block as lines, after `change`; empty when no tag is left.
fn write_key(shape: &Shape, items: &[Item], eol: &str) -> String {
    if items.is_empty() {
        return String::new();
    }
    match shape {
        Shape::Flow => {
            let raws: Vec<&str> = items.iter().map(|item| item.raw.as_str()).collect();
            format!("tags: [{}]{eol}", raws.join(", "))
        }
        Shape::Block(indent) => {
            let mut out = format!("tags:{eol}");
            for item in items {
                out.push_str(&format!("{indent}- {}{eol}", item.raw));
            }
            out
        }
        Shape::Words(between) => {
            // Words are not quoted: each is a tag's own text.
            let words: Vec<&str> = items
                .iter()
                .filter_map(|item| item.tag.as_deref())
                .collect();
            format!("tags: {}{eol}", words.join(between))
        }
    }
}

/// The shape and entries of a `tags` key, from its line and the lines that continue it.
fn read_key(chunk: &str) -> (Shape, Vec<Item>) {
    let mut lines = chunk.lines();
    let value = lines
        .next()
        .and_then(|line| line.strip_prefix("tags:"))
        .unwrap_or("")
        .trim();
    let rest: Vec<&str> = lines.collect();
    let dashed = |line: &&str| line.trim_start().starts_with('-');
    let inner = value
        .strip_prefix('[')
        .and_then(|v| v.strip_suffix(']'))
        .filter(|inner| !inner.contains(['[', ']', '{', '}']));
    if let (true, Some(inner)) = (rest.is_empty(), inner) {
        let items = inner
            .split(',')
            .map(str::trim)
            .filter(|raw| !raw.is_empty())
            .map(Item::written)
            .collect();
        return (Shape::Flow, items);
    }
    if value.is_empty() && !rest.is_empty() && rest.iter().all(dashed) {
        let indent = rest[0][..rest[0].len() - rest[0].trim_start().len()].to_string();
        let items = rest
            .iter()
            .map(|line| line.trim_start()[1..].trim())
            .filter(|raw| !raw.is_empty())
            .map(Item::written)
            .collect();
        return (Shape::Block(indent), items);
    }
    let plain = !value.starts_with(['"', '\'', '[', '{', '|', '>', '&', '*', '!']);
    if rest.is_empty() && plain && !value.is_empty() {
        let between = if value.contains(',') { ", " } else { " " };
        let items = value
            .split([',', ' '])
            .filter(|raw| !raw.is_empty())
            .map(Item::written)
            .collect();
        return (Shape::Words(between), items);
    }
    // Any other way of writing the list is read the lenient way and written back as a flow list.
    let items = from_frontmatter(chunk)
        .iter()
        .map(|tag| Item::new(tag))
        .collect();
    (Shape::Flow, items)
}

/// `text` with `change` made to the `tags` key of its frontmatter, or none when that changes
/// nothing. Every other line of the file stays as it was, and a list keeps the way it is written.
/// A file with no `tags` key gets `tags: [tag]` at the end of its block, made when it has none;
/// a block left with nothing in it goes.
fn write_frontmatter(text: &str, change: Change<'_>) -> Option<String> {
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
        let line = write_key(&Shape::Flow, &[Item::new(tag)], file_eol);
        return Some(format!("---{file_eol}{line}---{file_eol}{text}"));
    };
    let open = if text.starts_with("---\r\n") { 5 } else { 4 };
    let close = &text[open + yaml.len()..text.len() - body.len()];

    // Find the key and the lines that belong to it.
    let mut lines: Vec<&str> = yaml.split_inclusive('\n').collect();
    let at = lines.iter().position(|line| {
        line.strip_prefix("tags")
            .is_some_and(|rest| rest.starts_with(':'))
    });
    let block = match at {
        None => {
            let Change::Add(tag) = change else {
                return None;
            };
            let mut block = yaml.to_string();
            if !block.is_empty() && !block.ends_with('\n') {
                block.push_str(file_eol);
            }
            block.push_str(&write_key(&Shape::Flow, &[Item::new(tag)], file_eol));
            block
        }
        Some(at) => {
            let empty_value = lines[at]["tags:".len()..].trim().is_empty();
            let mut end = at + 1;
            while end < lines.len() {
                let line = lines[end];
                let indented = line.starts_with([' ', '\t']) && !line.trim().is_empty();
                let dashed = empty_value && line.starts_with('-');
                if !(indented || dashed) {
                    break;
                }
                end += 1;
            }
            let chunk: String = lines[at..end].concat();
            let eol = if lines[at].ends_with("\r\n") {
                "\r\n"
            } else {
                file_eol
            };
            let (shape, items) = read_key(&chunk);
            let after = changed(&items, change)?;
            let written = write_key(&shape, &after, eol);
            lines.splice(at..end, [written.as_str()]);
            lines.concat()
        }
    };
    if block.trim().is_empty() {
        return Some(body.to_string());
    }
    Some(format!("{}{block}{close}{body}", &text[..open]))
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

/// One file a tag rename rewrote: its text before and after, so the rename can be undone.
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

    /// Add `tag` to the frontmatter of the bud at `path`. A bud that carries it already, in the
    /// frontmatter or as a `#tag` in its body, is left as it is.
    pub fn add_tag(&mut self, path: &str, tag: &str) -> Result<()> {
        let tag = clean(tag).ok_or_else(|| Error::Invalid(format!("not a tag: {tag}")))?;
        if self.tags_of(path)?.iter().any(|own| key(own) == key(&tag)) {
            return Ok(());
        }
        self.change_frontmatter(path, Change::Add(&tag))
    }

    /// Take `tag` out of the frontmatter of the bud at `path`. A `#tag` in its body stays: that
    /// is the bud's own text.
    pub fn remove_tag(&mut self, path: &str, tag: &str) -> Result<()> {
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
            let mut after = write_frontmatter(&before, change).unwrap_or_else(|| before.clone());
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

    /// Write the whole text of the bud at `path`, as undoing a tag rename does with each file's
    /// text from before.
    pub fn set_text(&mut self, path: &str, text: &str) -> Result<()> {
        self.write_file(path, text, None)
    }

    fn change_frontmatter(&mut self, path: &str, change: Change<'_>) -> Result<()> {
        self.bud(path)?
            .ok_or_else(|| Error::NoSuchBud(path.to_string()))?;
        let text = if path.ends_with(".md") {
            std::fs::read_to_string(self.root.join(path))?
        } else {
            String::new()
        };
        match write_frontmatter(&text, change) {
            Some(written) => self.write_file(path, &written, None),
            None => Ok(()),
        }
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
