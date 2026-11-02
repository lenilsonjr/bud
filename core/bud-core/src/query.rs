//! The questions the views ask of the index: search, Today, the counts on a card, the Next step
//! pill and the Todos and Pinned lenses. Every query reads the index and nothing else.
//!
//! Trails are computed in SQL: a recursive CTE walks `parent` up from each result, and the titles
//! come back root first. The trail leaves out the bud itself and is empty at the top of a place.

use crate::{lock, read_bud, Bud, Result, Vault, SELECT};
use rusqlite::{params, Connection};
use std::collections::HashSet;

/// A search result: where the bud is, what it is called, what holds it and why it matched.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hit {
    pub path: String,
    pub title: String,
    /// The titles of the ancestors, root first.
    pub trail: Vec<String>,
    /// A short piece of the body around the match, or its start when only the title matched.
    pub snippet: String,
}

/// A bud with the titles of the buds above it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub bud: Bud,
    /// The titles of the ancestors, root first.
    pub trail: Vec<String>,
}

/// What is under a bud: every descendant, and the open to-dos among them.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Counts {
    pub inside: usize,
    pub open_todos: usize,
}

/// The lenses of the sidebar that are a plain list.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lens {
    /// Every open to-do, soonest due first.
    Todos,
    /// Every pinned bud.
    Pinned,
}

/// Soonest `due`, then soonest `when`, then oldest `created`; a bud with none of a key comes
/// after the buds that have it.
const BY_URGENCY: &str = "ORDER BY due IS NULL, due, when_date IS NULL, when_date,
     created IS NULL, created, path";

const OPEN_TODO: &str = "state = 'open' AND place != 'trash'";

/// The first `days` characters of a date, so `2026-11-02T09:00` counts as the day `2026-11-02`.
const DUE_DAY: &str = "substr(due, 1, 10)";
const WHEN_DAY: &str = "substr(when_date, 1, 10)";

/// Words of `query` as an FTS5 expression: each word quoted, so nothing in it is syntax, and a
/// prefix match on the last one. None when there is no word.
fn match_expression(query: &str) -> Option<String> {
    let words: Vec<&str> = query
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    let (last, rest) = words.split_last()?;
    let mut expr = String::new();
    for word in rest {
        expr.push_str(&format!("\"{word}\" "));
    }
    expr.push_str(&format!("\"{last}\"*"));
    Some(expr)
}

fn trail(conn: &Connection, path: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare_cached(
        "WITH RECURSIVE up(parent, title, depth) AS (
             SELECT parent, title, 0 FROM buds WHERE path = ?1
             UNION ALL
             SELECT b.parent, b.title, up.depth + 1 FROM buds b JOIN up ON b.path = up.parent
         )
         SELECT title FROM up WHERE depth > 0 ORDER BY depth DESC",
    )?;
    let titles = stmt.query_map(params![path], |row| row.get(0))?;
    Ok(titles.collect::<std::result::Result<_, _>>()?)
}

fn rows(conn: &Connection, sql: &str, args: impl rusqlite::Params) -> Result<Vec<Row>> {
    let buds: Vec<Bud> = {
        let mut stmt = conn.prepare_cached(sql)?;
        let found = stmt.query_map(args, read_bud)?;
        found.collect::<std::result::Result<_, _>>()?
    };
    buds.into_iter()
        .map(|bud| {
            let trail = trail(conn, &bud.path)?;
            Ok(Row { bud, trail })
        })
        .collect()
}

/// Matches of `expr` ranked best first, the title weighing more than the body, Trash left out.
fn matches(conn: &Connection, expr: &str, limit: usize) -> Result<Vec<(String, String, String)>> {
    let mut stmt = conn.prepare_cached(
        "SELECT b.path, b.title, snippet(buds_fts, 1, '', '', '...', 12)
         FROM buds_fts JOIN buds b ON b.rowid = buds_fts.rowid
         WHERE buds_fts MATCH ?1 AND b.place != 'trash'
         ORDER BY bm25(buds_fts, 10.0, 1.0), b.path
         LIMIT ?2",
    )?;
    let found = stmt.query_map(params![expr, limit as i64], |row| {
        Ok((row.get(0)?, row.get(1)?, row.get(2)?))
    })?;
    Ok(found.collect::<std::result::Result<_, _>>()?)
}

impl Vault {
    /// Buds whose title or body has every word of `query`, the last word as a prefix. Hits in the
    /// title come first, then hits in the body, each best match first. Trash is left out; the Inbox
    /// and the Archive are in. At most `limit` hits.
    pub fn search(&self, query: &str, limit: usize) -> Result<Vec<Hit>> {
        let Some(expr) = match_expression(query) else {
            return Ok(Vec::new());
        };
        if limit == 0 {
            return Ok(Vec::new());
        }
        let conn = lock(&self.conn);
        let mut found = matches(&conn, &format!("title : ({expr})"), limit)?;
        if found.len() < limit {
            let seen: HashSet<String> = found.iter().map(|(path, _, _)| path.clone()).collect();
            let wider = matches(&conn, &expr, limit + seen.len())?;
            let rest = wider
                .into_iter()
                .filter(|(path, _, _)| !seen.contains(path));
            found.extend(rest.take(limit - seen.len()));
        }
        found
            .into_iter()
            .map(|(path, title, snippet)| {
                let trail = trail(&conn, &path)?;
                Ok(Hit {
                    path,
                    title,
                    trail,
                    snippet,
                })
            })
            .collect()
    }

    /// The open to-dos for `date` (`YYYY-MM-DD`): those with `due` on or before it, by `due`, then
    /// those with `when` on or before it, by `when`. A to-do is listed once.
    pub fn today(&self, date: &str) -> Result<Vec<Row>> {
        let due_now = format!("({DUE_DAY} <= ?1)");
        let when_now = format!("({WHEN_DAY} <= ?1)");
        let sql = format!(
            "{SELECT} WHERE {OPEN_TODO} AND ({due_now} OR {when_now})
             ORDER BY CASE WHEN {due_now} THEN 0 ELSE 1 END,
                      CASE WHEN {due_now} THEN due ELSE when_date END,
                      created IS NULL, created, path"
        );
        rows(&lock(&self.conn), &sql, params![date])
    }

    /// Everything under `path`, however deep, and how many of it are open to-dos.
    pub fn counts(&self, path: &str) -> Result<Counts> {
        let conn = lock(&self.conn);
        let (inside, open): (i64, i64) = conn.query_row(
            "WITH RECURSIVE sub(path, state) AS (
                 SELECT path, state FROM buds WHERE parent = ?1
                 UNION ALL
                 SELECT b.path, b.state FROM buds b JOIN sub ON b.parent = sub.path
             )
             SELECT count(*), coalesce(sum(state = 'open'), 0) FROM sub",
            params![path],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?;
        Ok(Counts {
            inside: inside as usize,
            open_todos: open as usize,
        })
    }

    /// The open to-do to do next under the bud `under` (or in the whole vault): the soonest `due`,
    /// then the soonest `when`, then the oldest `created`. `date` is the day the pill is read on;
    /// an overdue to-do already sorts first, so the order does not depend on it.
    pub fn next_step(&self, under: Option<&str>, _date: &str) -> Result<Option<Row>> {
        let conn = lock(&self.conn);
        let found = match under {
            Some(path) => rows(
                &conn,
                &format!(
                    "WITH RECURSIVE sub(path) AS (
                         SELECT path FROM buds WHERE parent = ?1
                         UNION ALL
                         SELECT b.path FROM buds b JOIN sub ON b.parent = sub.path
                     )
                     {SELECT} WHERE {OPEN_TODO} AND path IN (SELECT path FROM sub)
                     {BY_URGENCY} LIMIT 1"
                ),
                params![path],
            )?,
            None => rows(
                &conn,
                &format!("{SELECT} WHERE {OPEN_TODO} {BY_URGENCY} LIMIT 1"),
                [],
            )?,
        };
        Ok(found.into_iter().next())
    }

    /// A lens that is a plain list: every open to-do, or every pinned bud. Trash is left out.
    pub fn lens(&self, lens: Lens) -> Result<Vec<Row>> {
        let sql = match lens {
            Lens::Todos => format!("{SELECT} WHERE {OPEN_TODO} {BY_URGENCY}"),
            Lens::Pinned => format!(
                "{SELECT} WHERE pinned = 1 AND place != 'trash'
                 ORDER BY created IS NULL, created, title COLLATE NOCASE, path"
            ),
        };
        rows(&lock(&self.conn), &sql, [])
    }
}
