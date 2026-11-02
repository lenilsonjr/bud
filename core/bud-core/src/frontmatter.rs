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
    }
}

/// The keys this module writes, in the order new ones are appended.
const KEYS: [&str; 6] = ["state", "when", "due", "pinned", "created", "source"];

/// The text of each key as it is written; none means the key is absent.
fn wanted(props: &Properties) -> [Option<String>; 6] {
    [
        props.state.map(|s| s.as_str().to_string()),
        props.when.as_deref().map(scalar),
        props.due.as_deref().map(scalar),
        props.pinned.then(|| "true".to_string()),
        props.created.as_deref().map(scalar),
        props.source.as_deref().map(scalar),
    ]
}

/// A YAML scalar for `value`: plain when that reads back as the same string, else double-quoted.
fn scalar(value: &str) -> String {
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
        let block = edit_block("", &wanted, eol);
        return format!("---{eol}{block}---{eol}{text}");
    };
    let open_len = if text.starts_with("---\r\n") { 5 } else { 4 };
    let open = &text[..open_len];
    let close = &text[open_len + yaml.len()..text.len() - body.len()];
    let eol = if open.ends_with("\r\n") { "\r\n" } else { "\n" };
    format!("{open}{}{close}{body}", edit_block(yaml, &wanted, eol))
}

fn edit_block(yaml: &str, wanted: &[Option<String>; 6], eol: &str) -> String {
    let mut out = String::with_capacity(yaml.len() + 64);
    let mut seen = [false; 6];
    let mut in_value = false;
    for line in yaml.split_inclusive('\n') {
        // Indented lines under a key belong to its value.
        if in_value && line.starts_with([' ', '\t']) && !line.trim().is_empty() {
            continue;
        }
        in_value = false;
        let hit = KEYS.iter().position(|key| {
            line.strip_prefix(key)
                .is_some_and(|rest| rest.starts_with(':'))
        });
        match hit {
            Some(i) => {
                in_value = true;
                if !seen[i] {
                    seen[i] = true;
                    if let Some(value) = &wanted[i] {
                        out.push_str(&format!("{}: {value}{}", KEYS[i], line_ending(line)));
                    }
                }
            }
            None => out.push_str(line),
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
            }
        );
    }

    #[test]
    fn bad_yaml_is_no_properties() {
        assert_eq!(parse("state: [\n"), Properties::default());
        assert_eq!(parse("- a list\n"), Properties::default());
        assert_eq!(parse("state: maybe\n").state, None);
    }
}
