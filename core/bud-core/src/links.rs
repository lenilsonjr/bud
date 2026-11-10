//! Links between buds: `[[Target]]` and `[[Target|label]]` written in a body, and the embeds
//! beside them: `![[photo.png]]` and `![alt](photo.png)`. The index keeps every link under the
//! row of the bud it is written in, so a rename or a move of that bud keeps its links; the target
//! stays the text as written and is resolved when it is read, so planting or renaming the bud it
//! names needs no rewrite of the index.
//!
//! A link's target resolves to the one bud whose title it is, then to the one bud whose title it
//! is in any case, then to the bud at that path, with or without `.md`. An embed's target
//! resolves to the one attachment whose file name is the target's, then whose file name is it in
//! any case, then the one the target is the path of; among several, the one in the bud's own
//! folder comes first, then the one beside the bud's file, then the one at the path from the
//! vault root. A path is read from the bud's folder, `..` and a leading `/` included. More than
//! one at the first rank that has any, or none at all, leaves it unresolved. Trash is never a
//! target.

use crate::{lock, prose, Result, Vault};
use rusqlite::{params, Connection, OptionalExtension};
use std::collections::HashMap;

/// One link as written, with the bud it resolves to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Link {
    /// The bud the link is written in.
    pub from: String,
    /// The text between the brackets, without the label or a `#heading`.
    pub target: String,
    /// The text after `|`, when there is one.
    pub label: Option<String>,
    /// The bud the target names; none when no bud, or more than one, does.
    pub to: Option<String>,
}

/// One embed as written, with the attachment it resolves to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Embed {
    /// The bud the embed is written in.
    pub from: String,
    /// The file as written: the text between the brackets, or the path in the parentheses.
    pub target: String,
    /// The text after `|` or between the square brackets, when there is one.
    pub label: Option<String>,
    /// The attachment the target names; none when no attachment, or more than one, does.
    pub to: Option<String>,
}

/// Whether a row of the link index is a `[[link]]` or an embed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Kind {
    Link,
    Embed,
}

impl Kind {
    fn as_str(self) -> &'static str {
        match self {
            Kind::Link => "link",
            Kind::Embed => "embed",
        }
    }
}

/// One link or embed as the parser read it: target, label, byte offset of where it starts.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Parsed {
    pub kind: Kind,
    pub target: String,
    pub label: Option<String>,
    pub position: usize,
}

/// The links and embeds in a body, in order. Fenced code and code spans hold none, and neither
/// spans lines. An embed starts at its `!`, a link at its brackets.
pub(crate) fn parse(body: &str) -> Vec<Parsed> {
    let mut out = Vec::new();
    for (start, line) in prose::lines(body) {
        let bytes = line.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            if bytes[i] == b'[' && bytes.get(i + 1) == Some(&b'[') {
                if let Some(len) = line[i + 2..].find("]]") {
                    let inner = &line[i + 2..i + 2 + len];
                    if !inner.contains(['[', ']']) {
                        let embed = i > 0 && bytes[i - 1] == b'!';
                        if let Some((target, label)) = split(inner) {
                            out.push(if embed {
                                Parsed {
                                    kind: Kind::Embed,
                                    target,
                                    label,
                                    position: start + i - 1,
                                }
                            } else {
                                Parsed {
                                    kind: Kind::Link,
                                    target,
                                    label,
                                    position: start + i,
                                }
                            });
                        }
                        i += len + 4;
                        continue;
                    }
                }
            } else if bytes[i] == b'!' && bytes.get(i + 1) == Some(&b'[') {
                if let Some((target, label, len)) = image(&line[i..]) {
                    out.push(Parsed {
                        kind: Kind::Embed,
                        target,
                        label,
                        position: start + i,
                    });
                    i += len;
                    continue;
                }
            }
            i += 1;
        }
    }
    out
}

/// `Target#heading|label` as its target and label; none when the target is empty.
fn split(inner: &str) -> Option<(String, Option<String>)> {
    let (target, label) = match inner.split_once('|') {
        Some((t, l)) => (t, Some(l.trim().to_string()).filter(|l| !l.is_empty())),
        None => (inner, None),
    };
    let target = target.split('#').next().unwrap_or("").trim();
    (!target.is_empty()).then(|| (target.to_string(), label))
}

/// `![alt](path "title")` at the start of `text`: the path, the alt text and how many bytes the
/// whole takes. The path may sit in `<...>` when it has spaces, and otherwise ends at the first
/// space; a `#fragment` is left off it, and `%20` and its kin are decoded, as Obsidian writes
/// them. None when there is no such image, or the path is empty.
fn image(text: &str) -> Option<(String, Option<String>, usize)> {
    let alt_len = text[2..].find(']')?;
    let alt = &text[2..2 + alt_len];
    if alt.contains('[') {
        return None;
    }
    let after = 2 + alt_len + 1;
    if text.as_bytes().get(after) != Some(&b'(') {
        return None;
    }
    let inner = text[after + 1..].trim_start();
    // The path sits in `<...>`, or ends at the first space or the closing parenthesis.
    let (path, rest) = match inner.strip_prefix('<') {
        Some(rest) => rest.split_once('>')?,
        None => inner.split_at(inner.find([' ', '\t', ')']).unwrap_or(inner.len())),
    };
    if path.contains(['(', ')']) {
        return None;
    }
    // After the path comes the closing parenthesis, or a quoted title and then it; the title may
    // hold anything but its own quote.
    let rest = rest.trim_start();
    let close = match rest.chars().next() {
        Some(quote @ ('"' | '\'')) => {
            let title_len = rest[1..].find(quote)?;
            rest[1 + title_len + 1..].trim_start()
        }
        _ => rest,
    };
    if !close.starts_with(')') {
        return None;
    }
    let target = percent_decode(path.split('#').next().unwrap_or("").trim());
    if target.is_empty() {
        return None;
    }
    let label = Some(alt.trim().to_string()).filter(|l| !l.is_empty());
    Some((target, label, text.len() - close.len() + 1))
}

/// `text` with each `%XX` as the byte it stands for; what is not valid UTF-8 after that, or not
/// a `%XX`, stays as written.
fn percent_decode(text: &str) -> String {
    if !text.contains('%') {
        return text.to_string();
    }
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let hex = bytes
            .get(i + 1..i + 3)
            .filter(|_| bytes[i] == b'%')
            .and_then(|pair| std::str::from_utf8(pair).ok())
            .and_then(|pair| u8::from_str_radix(pair, 16).ok());
        match hex {
            Some(byte) => {
                out.push(byte);
                i += 3;
            }
            None => {
                out.push(bytes[i]);
                i += 1;
            }
        }
    }
    String::from_utf8(out).unwrap_or_else(|_| text.to_string())
}

/// Replace the links and embeds of the bud at `path` with the ones in `body`.
pub(crate) fn relink(conn: &Connection, path: &str, body: &str) -> Result<()> {
    let row: i64 = conn.query_row(
        "SELECT rowid FROM buds WHERE path = ?1",
        params![path],
        |r| r.get(0),
    )?;
    conn.execute("DELETE FROM links WHERE source = ?1", params![row])?;
    let mut insert = conn.prepare_cached(
        "INSERT INTO links (source, target, label, position, kind) VALUES (?1, ?2, ?3, ?4, ?5)",
    )?;
    for parsed in parse(body) {
        insert.execute(params![
            row,
            parsed.target,
            parsed.label,
            parsed.position as i64,
            parsed.kind.as_str()
        ])?;
    }
    Ok(())
}

/// The bud `target` names, by the order in the module comment.
fn resolve(conn: &Connection, target: &str) -> Result<Option<String>> {
    let mut stmt = conn.prepare_cached(
        "SELECT path, title FROM buds WHERE place != 'trash'
         AND (title = ?1 COLLATE NOCASE OR path = ?1 OR path = ?1 || '.md')",
    )?;
    let found: Vec<(String, String)> = stmt
        .query_map(params![target], |r| Ok((r.get(0)?, r.get(1)?)))?
        .collect::<std::result::Result<_, _>>()?;
    // The query found only buds that match by title in any case, or by path.
    let rank = |(_, title): &(String, String)| {
        if title == target {
            0
        } else if title.to_lowercase() == target.to_lowercase() {
            1
        } else {
            2
        }
    };
    Ok(one_at_best(found, rank))
}

/// `target` read from the folder `dir`: `.` and `..` are resolved, a leading `/` starts at the
/// vault root, and `..` above the root is dropped.
fn path_from(dir: &str, target: &str) -> String {
    let (dir, target) = match target.strip_prefix('/') {
        Some(root_relative) => ("", root_relative),
        None => (dir, target),
    };
    let mut parts: Vec<&str> = dir.split('/').filter(|p| !p.is_empty()).collect();
    for part in target.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            _ => parts.push(part),
        }
    }
    parts.join("/")
}

/// The attachment `target` names from the bud at `from`, by the order in the module comment.
fn resolve_embed(conn: &Connection, from: &str, target: &str) -> Result<Option<String>> {
    let name = target.rsplit('/').next().unwrap_or(target);
    // The target as a path from the bud's own folder, from the folder its file is in, and from
    // the vault root.
    let own = path_from(from.strip_suffix(".md").unwrap_or(from), target);
    let beside = path_from(from.rsplit_once('/').map_or("", |(dir, _)| dir), target);
    let exact = path_from("", target);
    let mut stmt = conn.prepare_cached(
        "SELECT path, name FROM attachments WHERE substr(path, 1, 7) != '.trash/'
         AND (name = ?1 COLLATE NOCASE OR path IN (?2, ?3, ?4))",
    )?;
    let found: Vec<(String, String)> = stmt
        .query_map(params![name, own, beside, exact], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })?
        .collect::<std::result::Result<_, _>>()?;
    let rank = |(path, found_name): &(String, String)| {
        let by_name = if found_name == name {
            0
        } else if found_name.to_lowercase() == name.to_lowercase() {
            1
        } else {
            2
        };
        let by_path = if *path == own {
            0
        } else if *path == beside {
            1
        } else if *path == exact {
            2
        } else {
            3
        };
        (by_name, by_path)
    };
    Ok(one_at_best(found, rank))
}

/// The path of the one row at the best rank; none when no row, or more than one, is there.
fn one_at_best<R: Ord>(
    found: Vec<(String, String)>,
    rank: impl Fn(&(String, String)) -> R,
) -> Option<String> {
    let best = found.iter().map(&rank).min()?;
    let mut at_best = found.into_iter().filter(|b| rank(b) == best);
    match (at_best.next(), at_best.next()) {
        (Some((path, _)), None) => Some(path),
        _ => None,
    }
}

type Written = (String, String, Option<String>);

fn rows(conn: &Connection, sql: &str, args: impl rusqlite::Params) -> Result<Vec<Written>> {
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map(args, |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?;
    Ok(rows.collect::<std::result::Result<_, _>>()?)
}

fn read(conn: &Connection, sql: &str, args: impl rusqlite::Params) -> Result<Vec<Link>> {
    // One lookup per distinct target, however often it is written.
    let mut resolved: HashMap<String, Option<String>> = HashMap::new();
    rows(conn, sql, args)?
        .into_iter()
        .map(|(from, target, label)| {
            let to = match resolved.get(&target) {
                Some(to) => to.clone(),
                None => {
                    let to = resolve(conn, &target)?;
                    resolved.insert(target.clone(), to.clone());
                    to
                }
            };
            Ok(Link {
                from,
                target,
                label,
                to,
            })
        })
        .collect()
}

fn read_embeds(conn: &Connection, sql: &str, args: impl rusqlite::Params) -> Result<Vec<Embed>> {
    // One lookup per distinct target in a bud, however often it is written there.
    let mut resolved: HashMap<(String, String), Option<String>> = HashMap::new();
    rows(conn, sql, args)?
        .into_iter()
        .map(|(from, target, label)| {
            let key = (from.clone(), target.clone());
            let to = match resolved.get(&key) {
                Some(to) => to.clone(),
                None => {
                    let to = resolve_embed(conn, &from, &target)?;
                    resolved.insert(key, to.clone());
                    to
                }
            };
            Ok(Embed {
                from,
                target,
                label,
                to,
            })
        })
        .collect()
}

const LINKS: &str = "SELECT buds.path, links.target, links.label FROM links
     JOIN buds ON buds.rowid = links.source WHERE buds.place != 'trash' AND links.kind = 'link'";

const EMBEDS: &str = "SELECT buds.path, links.target, links.label FROM links
     JOIN buds ON buds.rowid = links.source WHERE buds.place != 'trash' AND links.kind = 'embed'";

impl Vault {
    /// The links written in the bud at `path`, in the order they appear.
    pub fn links(&self, path: &str) -> Result<Vec<Link>> {
        read(
            &lock(&self.conn),
            &format!("{LINKS} AND buds.path = ?1 ORDER BY links.position"),
            params![path],
        )
    }

    /// The links that resolve to the bud at `path`, by the bud they are written in.
    pub fn backlinks(&self, path: &str) -> Result<Vec<Link>> {
        let conn = lock(&self.conn);
        let Some(title) = conn
            .query_row(
                "SELECT title FROM buds WHERE path = ?1",
                params![path],
                |r| r.get::<_, String>(0),
            )
            .optional()?
        else {
            return Ok(Vec::new());
        };
        let bare = path.strip_suffix(".md").unwrap_or(path);
        let found = read(
            &conn,
            &format!(
                "{LINKS} AND (links.target = ?1 COLLATE NOCASE OR links.target = ?2 OR links.target = ?3)
                 ORDER BY buds.path, links.position"
            ),
            params![title, path, bare],
        )?;
        Ok(found
            .into_iter()
            .filter(|l| l.to.as_deref() == Some(path))
            .collect())
    }

    /// Every link that names no bud, or more than one.
    pub fn unresolved_links(&self) -> Result<Vec<Link>> {
        let found = read(
            &lock(&self.conn),
            &format!("{LINKS} ORDER BY buds.path, links.position"),
            [],
        )?;
        Ok(found.into_iter().filter(|l| l.to.is_none()).collect())
    }

    /// The embeds written in the bud at `path`, in the order they appear.
    pub fn embeds(&self, path: &str) -> Result<Vec<Embed>> {
        read_embeds(
            &lock(&self.conn),
            &format!("{EMBEDS} AND buds.path = ?1 ORDER BY links.position"),
            params![path],
        )
    }

    /// The first embed of the bud at `path` that resolves to an attachment: the picture its card
    /// shows.
    pub fn first_embed(&self, path: &str) -> Result<Option<Embed>> {
        Ok(self.embeds(path)?.into_iter().find(|e| e.to.is_some()))
    }

    /// The embeds that resolve to the attachment at `path`, by the bud they are written in.
    pub fn embedding(&self, path: &str) -> Result<Vec<Embed>> {
        let conn = lock(&self.conn);
        let Some(name) = conn
            .query_row(
                "SELECT name FROM attachments WHERE path = ?1",
                params![path],
                |r| r.get::<_, String>(0),
            )
            .optional()?
        else {
            return Ok(Vec::new());
        };
        // Any embed that names the attachment ends in its file name, whatever path it gives.
        let found = read_embeds(
            &conn,
            &format!(
                "{EMBEDS} AND (links.target = ?1 COLLATE NOCASE
                     OR substr(links.target, -length(?1) - 1) = '/' || ?1 COLLATE NOCASE)
                 ORDER BY buds.path, links.position"
            ),
            params![name],
        )?;
        Ok(found
            .into_iter()
            .filter(|e| e.to.as_deref() == Some(path))
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::{parse, Kind};

    fn targets(body: &str) -> Vec<(String, Option<String>)> {
        parse(body)
            .into_iter()
            .filter(|p| p.kind == Kind::Link)
            .map(|p| (p.target, p.label))
            .collect()
    }

    fn embeds(body: &str) -> Vec<(String, Option<String>)> {
        parse(body)
            .into_iter()
            .filter(|p| p.kind == Kind::Embed)
            .map(|p| (p.target, p.label))
            .collect()
    }

    #[test]
    fn reads_targets_labels_and_headings() {
        assert_eq!(
            targets("See [[Plan]] and [[Launch/Welcome list|the list]], [[Notes#Week 2]]."),
            vec![
                ("Plan".into(), None),
                ("Launch/Welcome list".into(), Some("the list".into())),
                ("Notes".into(), None),
            ]
        );
    }

    #[test]
    fn code_holds_no_links() {
        let body = "`[[Not this]]` but [[This]]\n```\n[[Nor this]]\n```\n~~~\n[[Or this]]\n~~~\n[[After]]\n";
        assert_eq!(
            targets(body),
            vec![("This".into(), None), ("After".into(), None)]
        );
    }

    #[test]
    fn broken_and_empty_brackets_are_not_links() {
        assert_eq!(
            targets("[[]] [[ ]] [[open\nclose]] [[a [b] c]] [[#only heading]] ![[photo.png]]"),
            vec![]
        );
    }

    #[test]
    fn backticks_without_a_partner_are_plain_text() {
        assert_eq!(
            targets("Don`t forget [[Plan]]"),
            vec![("Plan".into(), None)]
        );
        assert_eq!(
            targets("``[[x]] ` [[y]]`` then [[z]]"),
            vec![("z".into(), None)]
        );
    }

    #[test]
    fn a_fence_closes_only_on_its_own_run() {
        let body = "````\n```\n[[Inside]]\n```rust\n````\n[[Outside]]\n";
        assert_eq!(targets(body), vec![("Outside".into(), None)]);
    }

    #[test]
    fn offsets_point_at_the_brackets() {
        let body = "one\ntwo [[X]]";
        assert_eq!(parse(body)[0].position, body.find("[[").unwrap());
    }

    #[test]
    fn an_embed_is_read_in_both_forms_and_is_not_a_link() {
        let body = "![[photo.png]] ![[Pics/photo.png|wide]] ![[photo.png#x]]\n\
                    ![a photo](photo.png) ![](Pics/photo%20two.png \"title\") ![](<Pics/a b.png>)";
        assert_eq!(
            embeds(body),
            vec![
                ("photo.png".into(), None),
                ("Pics/photo.png".into(), Some("wide".into())),
                ("photo.png".into(), None),
                ("photo.png".into(), Some("a photo".into())),
                ("Pics/photo two.png".into(), None),
                ("Pics/a b.png".into(), None),
            ]
        );
        assert_eq!(targets(body), vec![]);
    }

    #[test]
    fn an_image_keeps_its_title_and_leaves_off_a_fragment() {
        let body = "![](photo.png \"a (b)\") ![](photo.png#center) ![](<a b.png> 'c)d') [[After]]";
        assert_eq!(
            embeds(body),
            vec![
                ("photo.png".into(), None),
                ("photo.png".into(), None),
                ("a b.png".into(), None),
            ]
        );
        assert_eq!(targets(body), vec![("After".into(), None)]);
        let found = parse(body);
        assert_eq!(
            found[3].position,
            body.find("[[After").unwrap(),
            "the title's parenthesis did not end the image early"
        );
    }

    #[test]
    fn an_image_needs_its_parentheses_and_a_path() {
        assert_eq!(
            embeds("![alt] (x.png) ![alt](x.png ![]() ![a [b]](x.png) [not](x.png) ![ok](y.png)"),
            vec![("y.png".into(), Some("ok".into()))]
        );
        assert_eq!(embeds("`![](code.png)` ![](after.png)").len(), 1);
    }

    #[test]
    fn an_embed_starts_at_its_bang() {
        let body = "a ![[X.png]] b ![](Y.png)";
        let found = parse(body);
        assert_eq!(found[0].position, body.find("![[").unwrap());
        assert_eq!(found[1].position, body.find("![]").unwrap());
    }
}
