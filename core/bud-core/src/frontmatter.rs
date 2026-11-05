//! The YAML block at the top of a bud's file, read leniently (ADR-002 §4).
//!
//! Only the keys a lens needs are read. Anything else in the block is left alone, and a block
//! that does not parse means a note with no properties; a file is never rejected.

use crate::State;

/// The properties a lens needs. Everything is optional; `pinned` defaults to false.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Properties {
    pub state: Option<State>,
    pub when: Option<String>,
    pub due: Option<String>,
    pub pinned: bool,
    pub created: Option<String>,
    pub source: Option<String>,
    /// Where a planted bud came from: the source and the item id, as in `mail:M1234`. The key
    /// that finds an item already planted.
    pub from: Option<String>,
}

/// Split a file into its frontmatter YAML (without the `---` fences) and its body.
///
/// A block starts with `---` on the first line and ends at the next line that is exactly `---`.
/// Without a closing fence there is no block and the whole text is the body.
pub fn split(text: &str) -> (Option<&str>, &str) {
    let rest = match text
        .strip_prefix("---\n")
        .or_else(|| text.strip_prefix("---\r\n"))
    {
        Some(rest) => rest,
        None => return (None, text),
    };
    let mut offset = 0;
    for line in rest.split_inclusive('\n') {
        if line.trim_end_matches(['\r', '\n']) == "---" {
            let yaml = &rest[..offset];
            let body = &rest[offset + line.len()..];
            return (Some(yaml), body);
        }
        offset += line.len();
    }
    (None, text)
}

/// Read the known keys out of a YAML block. Unknown keys and bad values are ignored.
pub fn parse(yaml: &str) -> Properties {
    let value: serde_yaml::Value = match serde_yaml::from_str(yaml) {
        Ok(value) => value,
        Err(_) => return Properties::default(),
    };
    let Some(map) = value.as_mapping() else {
        return Properties::default();
    };
    let text = |key: &str| -> Option<String> {
        match map.get(key)? {
            serde_yaml::Value::String(s) => Some(s.clone()),
            serde_yaml::Value::Number(n) => Some(n.to_string()),
            _ => None,
        }
    };
    let pinned = match map.get("pinned") {
        Some(serde_yaml::Value::Bool(b)) => *b,
        Some(serde_yaml::Value::String(s)) => s == "true",
        _ => false,
    };
    Properties {
        state: text("state").and_then(|s| State::parse(&s)),
        when: text("when"),
        due: text("due"),
        pinned,
        created: text("created"),
        source: text("source"),
        from: text("from"),
    }
}

/// The keys of a block that [`Properties`] does not carry, as the file wrote them, and the order
/// of every key of the block. Two replicas that agree on a layout write the same block.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Layout {
    /// Each unknown key with its lines (the key line and what is indented or commented under it),
    /// in the order of the block.
    pub extras: Vec<(String, String)>,
    /// Every key of the block in order; empty while there are no unknown keys.
    pub order: Vec<String>,
}

/// The lines before the first key, then each top-level key with its lines.
fn chunks(yaml: &str) -> (String, Vec<(String, String)>) {
    let mut pre = String::new();
    let mut out: Vec<(String, String)> = Vec::new();
    for line in yaml.split_inclusive('\n') {
        let key = (!line.starts_with([' ', '\t', '#', '-', '\r', '\n']))
            .then(|| line.split_once(':').map(|(key, _)| key.trim().to_string()))
            .flatten()
            .filter(|key| !key.is_empty());
        match (key, out.last_mut()) {
            (Some(key), _) => out.push((key, line.to_string())),
            (None, Some((_, text))) => text.push_str(line),
            (None, None) => pre.push_str(line),
        }
    }
    (pre, out)
}

/// The unknown keys of a YAML block and the order of all its keys. A key that repeats counts once,
/// at its first line.
pub fn layout(yaml: &str) -> Layout {
    let (_, found) = chunks(yaml);
    let mut seen = std::collections::HashSet::new();
    let mut layout = Layout::default();
    for (key, text) in found {
        if !seen.insert(key.clone()) {
            continue;
        }
        if !KEYS.contains(&key.as_str()) {
            layout.extras.push((key.clone(), text));
        }
        layout.order.push(key);
    }
    if layout.extras.is_empty() {
        layout.order.clear();
    }
    layout
}

/// Return `text` with the unknown keys of its block set to `layout`: the ones it lacks are added,
/// the ones that differ are replaced, the ones it has beyond are removed, and with any unknown key
/// the block's keys follow `layout.order`. Known keys keep their lines. With no unknown key in
/// `layout` and none in the file the text comes back as it was.
pub fn write_layout(text: &str, layout: &Layout) -> String {
    let (yaml, body) = match split(text) {
        (Some(yaml), body) => (yaml, body),
        (None, _) if layout.extras.is_empty() => return text.to_string(),
        (None, _) => ("", text),
    };
    let had_block = split(text).0.is_some();
    let eol = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let (pre, found) = chunks(yaml);
    let mut seen = std::collections::HashSet::new();
    let mut kept: Vec<(String, String)> = Vec::new();
    for (key, chunk) in found {
        if !seen.insert(key.clone()) && !KEYS.contains(&key.as_str()) {
            continue;
        }
        if KEYS.contains(&key.as_str()) {
            kept.push((key, chunk));
        } else if let Some((_, wanted)) = layout.extras.iter().find(|(k, _)| *k == key) {
            kept.push((key, wanted.clone()));
        }
    }
    for (key, wanted) in &layout.extras {
        if !seen.contains(key) {
            kept.push((key.clone(), wanted.clone()));
        }
    }
    if !layout.extras.is_empty() {
        let at = |key: &str| layout.order.iter().position(|k| k == key);
        kept.sort_by_key(|(key, _)| at(key).unwrap_or(usize::MAX));
    }
    let mut block = pre;
    for (_, chunk) in kept {
        if !block.is_empty() && !block.ends_with('\n') {
            block.push_str(eol);
        }
        block.push_str(&chunk);
        if !block.ends_with('\n') {
            block.push_str(eol);
        }
    }
    if had_block {
        let open_len = if text.starts_with("---\r\n") { 5 } else { 4 };
        let close = &text[open_len + yaml.len()..text.len() - body.len()];
        format!("{}{block}{close}{body}", &text[..open_len])
    } else {
        format!("---{eol}{block}---{eol}{text}")
    }
}

/// The keys this module writes, in the order new ones are appended.
const KEYS: [&str; 7] = [
    "state", "when", "due", "pinned", "created", "source", "from",
];

/// The text of each key as it is written; none means the key is absent.
fn wanted(props: &Properties) -> [Option<String>; 7] {
    [
        props.state.map(|s| s.as_str().to_string()),
        props.when.as_deref().map(scalar),
        props.due.as_deref().map(scalar),
        props.pinned.then(|| "true".to_string()),
        props.created.as_deref().map(scalar),
        props.source.as_deref().map(scalar),
        props.from.as_deref().map(scalar),
    ]
}

/// A YAML scalar for `value`: plain when that reads back as the same string, else double-quoted.
pub(crate) fn scalar(value: &str) -> String {
    let plain = value.chars().next().is_some_and(|c| c.is_alphanumeric())
        && !value.contains(": ")
        && !value.contains(" #")
        && !value.ends_with([' ', ':'])
        && !value.contains(['\n', '\r', '\t'])
        && matches!(
            serde_yaml::from_str::<serde_yaml::Value>(value),
            Ok(serde_yaml::Value::String(ref s)) if s == value
        );
    if plain {
        return value.to_string();
    }
    let mut out = String::from("\"");
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn line_ending(line: &str) -> &'static str {
    if line.ends_with("\r\n") {
        "\r\n"
    } else if line.ends_with('\n') {
        "\n"
    } else {
        ""
    }
}

/// Return `text` with the known keys set to `props`. Only those keys change.
///
/// An existing key line is replaced in place, a missing key is appended at the end of the block,
/// and a key that is none is removed. A file with no block gets one only when something is set.
/// Every other line of the block and the whole body are kept byte for byte, and new lines use the
/// file's own line ending.
pub fn write(text: &str, props: &Properties) -> String {
    let wanted = wanted(props);
    let (Some(yaml), body) = split(text) else {
        if wanted.iter().all(Option::is_none) {
            return text.to_string();
        }
        let eol = if text
            .split_inclusive('\n')
            .next()
            .is_some_and(|l| l.ends_with("\r\n"))
        {
            "\r\n"
        } else {
            "\n"
        };
        let block = edit_block("", props, &wanted, eol);
        return format!("---{eol}{block}---{eol}{text}");
    };
    let open_len = if text.starts_with("---\r\n") { 5 } else { 4 };
    let open = &text[..open_len];
    let close = &text[open_len + yaml.len()..text.len() - body.len()];
    let eol = if open.ends_with("\r\n") { "\r\n" } else { "\n" };
    format!(
        "{open}{}{close}{body}",
        edit_block(yaml, props, &wanted, eol)
    )
}

/// Whether the key's existing text (its line and continuation) already reads as the wanted value.
fn unchanged(key: usize, chunk: &str, current: &Properties) -> bool {
    let existing = parse(chunk);
    match key {
        0 => existing.state == current.state,
        1 => existing.when == current.when,
        2 => existing.due == current.due,
        3 => existing.pinned == current.pinned,
        4 => existing.created == current.created,
        5 => existing.source == current.source,
        _ => existing.from == current.from,
    }
}

fn edit_block(yaml: &str, current: &Properties, wanted: &[Option<String>; 7], eol: &str) -> String {
    let mut out = String::with_capacity(yaml.len() + 64);
    let mut seen = [false; 7];
    let mut lines = yaml.split_inclusive('\n').peekable();
    while let Some(line) = lines.next() {
        let hit = KEYS.iter().position(|key| {
            line.strip_prefix(key)
                .is_some_and(|rest| rest.starts_with(':'))
        });
        let Some(i) = hit else {
            out.push_str(line);
            continue;
        };
        // Indented lines under a key belong to its value.
        let mut chunk = line.to_string();
        while let Some(next) = lines.peek() {
            if next.starts_with([' ', '\t']) && !next.trim().is_empty() {
                chunk.push_str(next);
                lines.next();
            } else {
                break;
            }
        }
        if seen[i] {
            continue;
        }
        seen[i] = true;
        if unchanged(i, &chunk, current) {
            // The value already reads as wanted: keep the user's own text for it.
            out.push_str(&chunk);
        } else if let Some(value) = &wanted[i] {
            out.push_str(&format!("{}: {value}{}", KEYS[i], line_ending(line)));
        }
    }
    for (i, value) in wanted.iter().enumerate() {
        if let (false, Some(value)) = (seen[i], value) {
            if !out.is_empty() && !out.ends_with('\n') {
                out.push_str(eol);
            }
            out.push_str(&format!("{}: {value}{eol}", KEYS[i]));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    const UNKNOWN: &str = "---\n# kept\ntags: [brand, 'launch']\nstate: open\naliases:\n  - Sender\n  - \"Mail\"\nwhen: 2026-11-02\n---\nBody line\n\nLast\n";

    fn props() -> Properties {
        Properties {
            state: Some(State::Done),
            when: Some("2026-11-02".into()),
            due: Some("2026-11-05".into()),
            pinned: true,
            created: Some("2026-10-02T11:00:00Z".into()),
            source: Some("phone".into()),
            from: None,
        }
    }

    #[test]
    fn replaces_in_place_and_keeps_unknown_keys_and_comments() {
        let out = write(
            UNKNOWN,
            &Properties {
                state: Some(State::Done),
                when: Some("2026-11-02".into()),
                ..Default::default()
            },
        );
        assert_eq!(
            out,
            "---\n# kept\ntags: [brand, 'launch']\nstate: done\naliases:\n  - Sender\n  - \"Mail\"\nwhen: 2026-11-02\n---\nBody line\n\nLast\n"
        );
    }

    #[test]
    fn appends_new_keys_at_the_end_of_the_block() {
        let out = write(
            "---\ntags: [a]\n---\nBody",
            &Properties {
                state: Some(State::Open),
                due: Some("2026-11-05".into()),
                ..Default::default()
            },
        );
        assert_eq!(
            out,
            "---\ntags: [a]\nstate: open\ndue: 2026-11-05\n---\nBody"
        );
    }

    #[test]
    fn none_removes_a_key_with_its_indented_lines() {
        let out = write(
            "---\nsource: phone\ndue: x\n  more\nkeep: 1\n---\nB",
            &Properties::default(),
        );
        assert_eq!(out, "---\nkeep: 1\n---\nB");
    }

    #[test]
    fn no_block_gets_one_only_when_something_is_set() {
        assert_eq!(write("Just text\n", &Properties::default()), "Just text\n");
        let out = write(
            "Just text\n",
            &Properties {
                pinned: true,
                ..Default::default()
            },
        );
        assert_eq!(out, "---\npinned: true\n---\nJust text\n");
    }

    #[test]
    fn an_empty_block_is_filled() {
        let out = write("---\n---\nB", &props());
        assert_eq!(parse(split(&out).0.unwrap()), props());
    }

    #[test]
    fn written_formats_snapshot() {
        let out = write("Body\n", &props());
        assert_eq!(
            out,
            "---\nstate: done\nwhen: 2026-11-02\ndue: 2026-11-05\npinned: true\ncreated: 2026-10-02T11:00:00Z\nsource: phone\n---\nBody\n"
        );
    }

    #[test]
    fn pinned_false_is_absent() {
        let out = write("---\npinned: true\n---\n", &Properties::default());
        assert_eq!(out, "---\n---\n");
    }

    #[test]
    fn crlf_is_kept() {
        let out = write(
            "---\r\ntags: a\r\nstate: open\r\n---\r\nBody\r\n",
            &Properties {
                state: Some(State::Done),
                due: Some("2026-11-05".into()),
                ..Default::default()
            },
        );
        assert_eq!(
            out,
            "---\r\ntags: a\r\nstate: done\r\ndue: 2026-11-05\r\n---\r\nBody\r\n"
        );
        let fresh = write("Hi\r\nthere\r\n", &props());
        assert!(fresh.starts_with("---\r\nstate: done\r\n"));
        assert!(fresh.ends_with("---\r\nHi\r\nthere\r\n"));
    }

    #[test]
    fn awkward_values_are_quoted_and_read_back() {
        for source in [
            "a: b",
            "true",
            "12",
            "say \"hi\"",
            "- x",
            "line\nbreak",
            "#tag",
        ] {
            let p = Properties {
                source: Some(source.into()),
                ..Default::default()
            };
            let out = write("", &p);
            assert_eq!(
                parse(split(&out).0.unwrap()).source.as_deref(),
                Some(source)
            );
        }
    }

    #[test]
    fn known_keys_that_already_read_right_keep_their_own_text() {
        let text = "---\nsource: \"phone\"\nstate: open # check\npinned: yes\nwhen: '2026-11-02'\ndue: 2026-11-04\n  # note\n---\nB\n";
        let (yaml, _) = split(text);
        let mut props = parse(yaml.unwrap());
        props.state = Some(State::Done);
        assert_eq!(
            write(text, &props),
            "---\nsource: \"phone\"\nstate: done\npinned: yes\nwhen: '2026-11-02'\ndue: 2026-11-04\n  # note\n---\nB\n"
        );
        props.state = Some(State::Open);
        assert_eq!(write(text, &props), text);
    }

    #[test]
    fn writing_what_is_read_changes_nothing() {
        let (yaml, _) = split(UNKNOWN);
        let read = parse(yaml.unwrap());
        assert_eq!(write(UNKNOWN, &read), UNKNOWN);
    }

    #[test]
    fn splits_a_block_from_its_body() {
        let (yaml, body) = split("---\nstate: open\n---\nHello\n");
        assert_eq!(yaml, Some("state: open\n"));
        assert_eq!(body, "Hello\n");
    }

    #[test]
    fn no_fence_means_no_block() {
        assert_eq!(split("Just text"), (None, "Just text"));
        assert_eq!(
            split("---\nstate: open\nno close"),
            (None, "---\nstate: open\nno close")
        );
    }

    #[test]
    fn crlf_is_fine() {
        let (yaml, body) = split("---\r\ndue: 2026-11-03\r\n---\r\nBody");
        assert_eq!(yaml, Some("due: 2026-11-03\r\n"));
        assert_eq!(body, "Body");
    }

    #[test]
    fn reads_the_known_keys_and_ignores_the_rest() {
        let props =
            parse("state: done\nwhen: 2026-11-02\npinned: true\ntags: [brand]\nsource: phone\n");
        assert_eq!(
            props,
            Properties {
                state: Some(State::Done),
                when: Some("2026-11-02".into()),
                due: None,
                pinned: true,
                created: None,
                source: Some("phone".into()),
                from: None,
            }
        );
    }

    #[test]
    fn from_is_read_and_written_after_the_other_keys() {
        let props = Properties {
            state: Some(State::Open),
            from: Some("mail:M-1".into()),
            ..Default::default()
        };
        let out = write("Body\n", &props);
        assert_eq!(out, "---\nstate: open\nfrom: mail:M-1\n---\nBody\n");
        assert_eq!(
            parse(split(&out).0.unwrap()).from.as_deref(),
            Some("mail:M-1")
        );
    }

    #[test]
    fn the_unknown_keys_and_the_order_of_all_keys_are_read() {
        let found = layout(UNKNOWN.split("---\n").nth(1).unwrap());
        assert_eq!(found.order, ["tags", "state", "aliases", "when"]);
        assert_eq!(
            found.extras,
            [
                ("tags".to_string(), "tags: [brand, 'launch']\n".to_string()),
                (
                    "aliases".to_string(),
                    "aliases:\n  - Sender\n  - \"Mail\"\n".to_string()
                ),
            ]
        );
        assert_eq!(layout("state: open\ndue: x\n"), Layout::default());
    }

    #[test]
    fn a_layout_is_written_in_its_order_and_read_back() {
        let from = "---\nzeta: 1\nstate: open\nalpha:\n  - a\n# note\ncreated: x\n---\nB\n";
        let found = layout(split(from).0.unwrap());
        let known = write("B\n", &parse(split(from).0.unwrap()));
        assert_eq!(write_layout(&known, &found), from);
        // A second write changes nothing.
        let once = write_layout(from, &found);
        assert_eq!(once, from);
        assert_eq!(write_layout(&once, &found), once);
    }

    #[test]
    fn a_layout_replaces_and_removes_unknown_keys_only() {
        let text = "---\ntags: a\nstate: open\nold: 1\n---\nB\n";
        let wanted = Layout {
            extras: vec![("tags".into(), "tags: [b]\n".into())],
            order: vec!["state".into(), "tags".into()],
        };
        assert_eq!(
            write_layout(text, &wanted),
            "---\nstate: open\ntags: [b]\n---\nB\n"
        );
    }

    #[test]
    fn no_unknown_keys_leaves_a_file_with_the_six_keys_alone() {
        let text = "---\n# c\nstate: open\ndue: x\n  more\n---\nB\n";
        assert_eq!(write_layout(text, &Layout::default()), text);
        assert_eq!(write_layout("Plain\n", &Layout::default()), "Plain\n");
    }

    #[test]
    fn a_layout_makes_a_block_when_the_file_has_none() {
        let wanted = Layout {
            extras: vec![("tags".into(), "tags: [a]\n".into())],
            order: vec!["tags".into()],
        };
        assert_eq!(write_layout("Hi\n", &wanted), "---\ntags: [a]\n---\nHi\n");
    }

    #[test]
    fn bad_yaml_is_no_properties() {
        assert_eq!(parse("state: [\n"), Properties::default());
        assert_eq!(parse("- a list\n"), Properties::default());
        assert_eq!(parse("state: maybe\n").state, None);
    }
}
