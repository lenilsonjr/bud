//! Tags: the `tags` key of a bud's frontmatter and the `#tags` in its prose. The index keeps each
//! tag a bud carries once, under the bud's row like its links, with where it was written. Tags
//! compare without case, accented letters included: `#Home` and `#home` are one tag, shown the
//! way most buds write it.
//!
//! The frontmatter key stays the file's own text (an unknown key to [`crate::Properties`]), so
//! reading tags never rewrites a file.

use crate::{lock, prose, read_bud, Bud, Result, Vault, SELECT};
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
    let mut out = Vec::new();
    for (_, line) in prose::lines(body) {
        let mut previous: Option<char> = None;
        let mut chars = line.char_indices().peekable();
        while let Some((i, c)) = chars.next() {
            let starts = c == '#' && previous.is_none_or(|p| p.is_whitespace() || p == ',');
            if starts {
                let rest = &line[i + 1..];
                let len = rest.find(|c: char| !tag_char(c)).unwrap_or(rest.len());
                if let Some(tag) = clean(&rest[..len]) {
                    out.push(tag);
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
