//! The parts of a Markdown body that are prose: what links and tags are read from. Fenced code
//! is left out whole, and a code span keeps its place but reads as spaces.

/// Each line of `body` outside fenced code, with its byte offset and its code spans blanked.
/// Offsets into a returned line are offsets into the original line.
pub(crate) fn lines(body: &str) -> Vec<(usize, String)> {
    let mut out = Vec::new();
    // The fence that is open: its character and the length of its run.
    let mut fence: Option<(u8, usize)> = None;
    let mut offset = 0;
    for line in body.split_inclusive('\n') {
        let start = offset;
        offset += line.len();
        let trimmed = line.trim_start().trim_end_matches(['\n', '\r']);
        let run = |c: u8| trimmed.bytes().take_while(|&b| b == c).count();
        if let Some((c, len)) = fence {
            // A fence closes on a run of its character at least as long, with nothing after it.
            if run(c) >= len && trimmed.trim_start_matches(c as char).trim().is_empty() {
                fence = None;
            }
            continue;
        }
        if let Some(c) = b"`~".iter().copied().find(|&c| run(c) >= 3) {
            fence = Some((c, run(c)));
            continue;
        }
        out.push((start, blank_code(line)));
    }
    out
}

/// `line` with each code span, backticks included, as spaces of the same length. A run of
/// backticks without a closing run of exactly as many is plain text.
fn blank_code(line: &str) -> String {
    let bytes = line.as_bytes();
    let mut out = line.as_bytes().to_vec();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] != b'`' {
            i += 1;
            continue;
        }
        let n = bytes[i..].iter().take_while(|&&b| b == b'`').count();
        match closing_run(&bytes[i + n..], n) {
            Some(close) => {
                let end = i + n + close + n;
                out[i..end].fill(b' ');
                i = end;
            }
            None => i += n,
        }
    }
    // Only whole code spans became spaces, and a span starts and ends on a backtick, so the
    // bytes are still UTF-8.
    String::from_utf8(out).unwrap_or_else(|_| line.to_string())
}

/// Where a run of exactly `n` backticks starts in `bytes`.
fn closing_run(bytes: &[u8], n: usize) -> Option<usize> {
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'`' {
            let len = bytes[i..].iter().take_while(|&&b| b == b'`').count();
            if len == n {
                return Some(i);
            }
            i += len;
        } else {
            i += 1;
        }
    }
    None
}
