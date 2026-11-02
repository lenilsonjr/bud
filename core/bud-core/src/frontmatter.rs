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

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

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
