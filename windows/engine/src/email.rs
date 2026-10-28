//! An email message (.eml, or Apple Mail's .emlx), read into what a person sees: who, when, the subject, the body (the
//! sender's HTML when there is one, else plain text) and the attachments. The port of `Models/Email.swift`. Read
//! entirely here; nothing in it is ever fetched from the network (that's the viewer's job to keep true).
//!
//! As on the Mac, the message is read as Latin-1, one character per byte, so the structure can be cut as text and each
//! part's bytes recovered exactly; a part's own charset is applied only when it's turned into words.

use std::collections::HashMap;

use base64::engine::general_purpose::{GeneralPurpose, GeneralPurposeConfig};
use base64::engine::DecodePaddingMode;
use base64::Engine as _;

#[derive(Clone, Debug, Default)]
pub struct Email {
    pub from: String,
    pub to: String,
    pub cc: String,
    pub subject: String,
    /// Seconds since 2001.
    pub date: Option<f64>,
    pub html: Option<String>,
    pub text: Option<String>,
    pub attachments: Vec<Attachment>,
    /// Pictures the HTML shows by Content-ID ("cid:…"): their type and bytes.
    pub inline: HashMap<String, (String, Vec<u8>)>,
}

#[derive(Clone, Debug)]
pub struct Attachment {
    pub name: String,
    pub kind: String,
    pub data: Vec<u8>,
}

/// How deep parts may sit inside parts (and messages inside messages) before the rest is left unread, so a message
/// built to nest forever can't crash the app.
const DEEPEST: usize = 16;

/// At most this many inline pictures: putting each in place costs a pass over the whole page, so an email built with
/// thousands of tiny ones would otherwise take minutes to show. Past it they're listed as attachments.
const MOST_INLINE: usize = 256;

/// Reads a message. None when the bytes don't look like one at all.
pub fn parse(data: &[u8]) -> Option<Email> {
    parse_at(data, 0)
}

fn latin1(bytes: &[u8]) -> String {
    bytes.iter().map(|&b| b as char).collect()
}

fn latin1_bytes(text: &str) -> Vec<u8> {
    text.chars().map(|c| c as u32 as u8).collect()
}

fn parse_at(data: &[u8], depth: usize) -> Option<Email> {
    let raw = latin1(unwrap_emlx(data));
    let top = Part::new(&raw);
    if !["from", "subject", "content-type"].iter().any(|h| top.headers.contains_key(*h)) {
        return None;
    }
    let header = |name: &str| decode_words(top.headers.get(name).map(String::as_str).unwrap_or(""));
    let mut email = Email {
        from: header("from"),
        to: header("to"),
        cc: header("cc"),
        subject: header("subject"),
        date: top.headers.get("date").and_then(|d| parse_date(d)),
        ..Email::default()
    };
    email.take(&top, depth);
    Some(email)
}

impl Email {
    /// The words in it, for search: who, the subject and the body without its markup.
    pub fn words(&self) -> String {
        let body = self.text.clone().or_else(|| self.html.as_deref().map(strip_tags)).unwrap_or_default();
        let names: Vec<&str> = self.attachments.iter().map(|a| a.name.as_str()).collect();
        [self.from.as_str(), &self.to, &self.cc, &self.subject, &body, &names.join(" ")].join("\n")
    }

    /// Walks a part and everything inside it, keeping the first HTML and plain-text bodies and every attachment.
    fn take(&mut self, part: &Part, depth: usize) {
        if depth >= DEEPEST {
            return;
        }
        let (kind, params) = part.content_type();
        let kind = kind.to_lowercase();
        if kind.starts_with("multipart/") {
            for child in part.children() {
                self.take(&child, depth + 1);
            }
            return;
        }
        if kind == "message/rfc822" {
            // A forwarded message: its body is shown as part of this one.
            if let Some(inner) = parse_at(&part.decoded_body(), depth + 1) {
                self.html = self.html.take().or(inner.html);
                self.text = self.text.take().or(inner.text);
                self.attachments.extend(inner.attachments);
                for (id, picture) in inner.inline {
                    if !self.inline.contains_key(&id) && self.inline.len() < MOST_INLINE {
                        self.inline.insert(id, picture);
                    }
                }
            }
            return;
        }
        let (disposition, disposition_params) = parameters(part.headers.get("content-disposition").map(String::as_str).unwrap_or(""));
        let disposition = disposition.to_lowercase();
        let name = file_name(&disposition_params, &params);
        let is_attachment = disposition == "attachment" || (name.is_some() && !kind.starts_with("text/"));
        if let Some(id) = part.headers.get("content-id") {
            if kind.starts_with("image/") && disposition != "attachment" && self.inline.len() < MOST_INLINE {
                let id = id.trim_matches(|c| c == '<' || c == '>' || c == ' ').to_owned();
                self.inline.insert(id, (kind, part.decoded_body()));
                return;
            }
        }
        if is_attachment {
            self.attachments.push(Attachment { name: name.unwrap_or_else(|| "Attachment".into()), kind, data: part.decoded_body() });
        } else if kind == "text/html" {
            if self.html.is_none() {
                self.html = Some(part.text());
            }
        } else if kind == "text/plain" || kind.is_empty() {
            if self.text.is_none() {
                self.text = Some(part.text());
            }
        } else {
            let data = part.decoded_body();
            if !data.is_empty() {
                self.attachments.push(Attachment { name: name.unwrap_or_else(|| "Attachment".into()), kind, data });
            }
        }
    }

    /// The HTML to show: the sender's, with inline pictures put in place, or the plain text set as a page.
    pub fn page(&self) -> String {
        if let Some(html) = &self.html {
            let mut html = html.clone();
            // Each reference gets a whole copy of its picture, so a small email naming one picture thousands of times
            // would grow into gigabytes: past 64 MB of pictures, the rest stay unshown.
            let mut budget: usize = 64 << 20;
            for (id, (kind, data)) in &self.inline {
                let reference = format!("cid:{id}");
                let uri = format!("data:{kind};base64,{}", base64::engine::general_purpose::STANDARD.encode(data));
                let uses = html.matches(&reference).count();
                if uses == 0 || uses.saturating_mul(uri.len()) > budget {
                    continue;
                }
                budget -= uses * uri.len();
                html = html.replace(&reference, &uri);
            }
            return html;
        }
        let escaped = self.text.as_deref().unwrap_or("").replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
        format!("<pre style=\"white-space:pre-wrap;font:13px 'Segoe UI',sans-serif\">{escaped}</pre>")
    }
}

// MARK: Parts

struct Part {
    headers: HashMap<String, String>,
    body: String,
}

impl Part {
    fn new(raw: &str) -> Part {
        // Headers end at the first empty line; lines starting with a space or tab continue the one before.
        let normalized = raw.replace("\r\n", "\n");
        // A part with no headers starts with its empty line.
        let (head, body) = if let Some(rest) = normalized.strip_prefix('\n') {
            ("", rest)
        } else if let Some(at) = normalized.find("\n\n") {
            (&normalized[..at], &normalized[at + 2..])
        } else {
            (normalized.as_str(), "")
        };
        let mut headers: HashMap<String, String> = HashMap::new();
        let mut current: Option<(String, String)> = None;
        for line in head.split('\n') {
            if line.starts_with([' ', '\t']) {
                if let Some(current) = current.as_mut() {
                    current.1.push(' ');
                    current.1.push_str(line.trim_matches([' ', '\t']));
                    continue;
                }
            }
            if let Some((name, value)) = current.take() {
                headers.entry(name).or_insert(value);
            }
            if let Some((name, value)) = line.split_once(':') {
                current = Some((name.to_lowercase().trim_matches([' ', '\t']).to_owned(), value.trim_matches([' ', '\t']).to_owned()));
            }
        }
        if let Some((name, value)) = current {
            headers.entry(name).or_insert(value);
        }
        Part { headers, body: body.to_owned() }
    }

    fn content_type(&self) -> (String, HashMap<String, String>) {
        parameters(self.headers.get("content-type").map(String::as_str).unwrap_or("text/plain"))
    }

    /// The parts of a multipart, cut at its boundary lines.
    fn children(&self) -> Vec<Part> {
        let (_, params) = self.content_type();
        let Some(boundary) = params.get("boundary").filter(|b| !b.is_empty()) else { return Vec::new() };
        let marker = format!("--{boundary}");
        let end = format!("{marker}--");
        let mut parts = Vec::new();
        let mut current: Option<Vec<&str>> = None;
        for line in self.body.split('\n') {
            let trimmed = line.trim_matches([' ', '\t']);
            if trimmed == end {
                break;
            }
            if trimmed == marker {
                if let Some(lines) = current.take() {
                    parts.push(Part::new(&lines.join("\n")));
                }
                current = Some(Vec::new());
            } else if let Some(lines) = current.as_mut() {
                lines.push(line);
            }
        }
        if let Some(lines) = current.filter(|l| !l.is_empty()) {
            parts.push(Part::new(&lines.join("\n")));
        }
        parts
    }

    /// The body's bytes, undoing base64 or quoted-printable.
    fn decoded_body(&self) -> Vec<u8> {
        match self.headers.get("content-transfer-encoding").map(|e| e.trim().to_lowercase()).as_deref() {
            Some("base64") => {
                let clean: String = self.body.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '+' || *c == '/' || *c == '=').collect();
                LENIENT.decode(clean.trim_end_matches('=')).unwrap_or_default()
            }
            Some("quoted-printable") => quoted_printable(&self.body),
            _ => latin1_bytes(&self.body),
        }
    }

    /// The body as words, in the charset it says it uses.
    fn text(&self) -> String {
        let (_, params) = self.content_type();
        string(&self.decoded_body(), params.get("charset").map(String::as_str))
    }
}

/// Base64 that takes padding or none, as mail is sent with either.
const LENIENT: GeneralPurpose = GeneralPurpose::new(
    &base64::alphabet::STANDARD,
    GeneralPurposeConfig::new().with_decode_padding_mode(DecodePaddingMode::Indifferent).with_decode_allow_trailing_bits(true),
);

// MARK: Decoding

/// Apple Mail's .emlx: a byte count on the first line, the message, then a property list after it.
fn unwrap_emlx(data: &[u8]) -> &[u8] {
    let Some(newline) = data.iter().take(20).position(|&b| b == b'\n') else { return data };
    let Ok(count) = std::str::from_utf8(&data[..newline]).unwrap_or("").trim().parse::<usize>() else { return data };
    let start = newline + 1;
    // A count that's nonsense (zero, or bigger than the file) leaves the bytes as they are.
    if count == 0 || count > data.len() - start {
        return data;
    }
    &data[start..start + count]
}

/// Bytes as text in the named charset; failing that UTF-8, failing that Latin-1.
pub fn string(data: &[u8], charset: Option<&str>) -> String {
    if let Some(charset) = charset {
        let label = charset.trim_matches(|c| c == '"' || c == ' ');
        if let Some(encoding) = encoding_rs::Encoding::for_label(label.as_bytes()) {
            if let Some(text) = encoding.decode_without_bom_handling_and_without_replacement(data) {
                return text.into_owned();
            }
        }
    }
    String::from_utf8(data.to_vec()).unwrap_or_else(|_| latin1(data))
}

/// Quoted-printable ("=C3=A9", "=" at a line's end joining lines) back to bytes. The text came from Latin-1, so each
/// character is one original byte.
pub fn quoted_printable(text: &str) -> Vec<u8> {
    let s: Vec<char> = text.chars().collect();
    let hex = |c: char| c.to_digit(16).map(|d| d as u8);
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        if s[i] == '=' {
            if i + 1 < s.len() && s[i + 1] == '\n' {
                i += 2;
                continue;
            }
            if i + 2 < s.len() && s[i + 1] == '\r' && s[i + 2] == '\n' {
                i += 3;
                continue;
            }
            if i + 2 < s.len() {
                if let (Some(high), Some(low)) = (hex(s[i + 1]), hex(s[i + 2])) {
                    out.push(high << 4 | low);
                    i += 3;
                    continue;
                }
            }
        }
        out.push(s[i] as u32 as u8);
        i += 1;
    }
    out
}

/// One "=?charset?B|Q?payload?=" at `at`: its charset, kind and payload, and where it ends.
fn encoded_word(s: &[char], at: usize) -> Option<(String, char, String, usize)> {
    if s.get(at..at + 2)? != ['=', '?'] {
        return None;
    }
    let mut i = at + 2;
    let charset_start = i;
    while *s.get(i)? != '?' {
        i += 1;
    }
    if i == charset_start {
        return None;
    }
    let charset: String = s[charset_start..i].iter().collect();
    let kind = s.get(i + 1)?.to_ascii_uppercase();
    if !matches!(kind, 'B' | 'Q') || *s.get(i + 2)? != '?' {
        return None;
    }
    i += 3;
    let payload_start = i;
    while *s.get(i)? != '?' {
        i += 1;
    }
    if *s.get(i + 1)? != '=' {
        return None;
    }
    Some((charset, kind, s[payload_start..i].iter().collect(), i + 2))
}

/// Header words like "=?UTF-8?B?…?=" or "=?iso-8859-1?Q?…?=", decoded; plain words left as they are.
pub fn decode_words(header: &str) -> String {
    let s: Vec<char> = header.chars().collect();
    let mut out = String::new();
    let (mut last, mut i) = (0, 0);
    let mut previous_was_encoded = false;
    while i < s.len() {
        let Some((charset, kind, payload, end)) = encoded_word(&s, i) else {
            i += 1;
            continue;
        };
        let between: String = s[last..i].iter().collect();
        // Space between two encoded words is dropped, as the standard says.
        if !(previous_was_encoded && between.trim().is_empty()) {
            out.push_str(&plain_header(&between));
        }
        let charset = charset.split('*').next().unwrap_or("").to_owned();
        let bytes = if kind == 'B' {
            let clean: String = payload.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '+' || *c == '/').collect();
            LENIENT.decode(clean).unwrap_or_default()
        } else {
            quoted_printable(&payload.replace('_', " "))
        };
        out.push_str(&string(&bytes, Some(&charset)));
        last = end;
        i = end;
        previous_was_encoded = true;
    }
    out.push_str(&plain_header(&s[last..].iter().collect::<String>()));
    out.trim_matches([' ', '\t']).to_owned()
}

/// Unencoded header text: its bytes were read as Latin-1; most senders meant UTF-8.
fn plain_header(text: &str) -> String {
    if text.chars().any(|c| c as u32 > 0xFF) {
        return text.to_owned();
    }
    String::from_utf8(latin1_bytes(text)).unwrap_or_else(|_| text.to_owned())
}

/// "text/html; charset=utf-8; name=\"a b.pdf\"" → ("text/html", {"charset": "utf-8", "name": "a b.pdf"}).
pub fn parameters(header: &str) -> (String, HashMap<String, String>) {
    let mut pieces = Vec::new();
    let mut current = String::new();
    let mut quoted = false;
    for c in header.chars() {
        if c == '"' {
            quoted = !quoted;
            continue;
        }
        if c == ';' && !quoted {
            pieces.push(std::mem::take(&mut current));
            continue;
        }
        current.push(c);
    }
    pieces.push(current);
    let mut params = HashMap::new();
    for piece in &pieces[1..] {
        if let Some((name, value)) = piece.split_once('=') {
            params.insert(name.trim().to_lowercase(), value.trim().to_owned());
        }
    }
    (pieces[0].trim().to_owned(), params)
}

/// An attachment's name: RFC 2231 "filename*=UTF-8''…" first, then filename=, then the type's name=.
fn file_name(disposition: &HashMap<String, String>, kind: &HashMap<String, String>) -> Option<String> {
    if let Some(starred) = disposition.get("filename*").or_else(|| kind.get("name*")) {
        let parts: Vec<&str> = starred.split("''").collect();
        let encoded = if parts.len() == 2 { parts[1] } else { starred.as_str() };
        if let Some(decoded) = percent_decoded(encoded) {
            return Some(decoded);
        }
    }
    disposition.get("filename").or_else(|| kind.get("name")).map(|n| decode_words(n))
}

/// %XX escapes as UTF-8, or None when they aren't valid ones (`removingPercentEncoding`).
fn percent_decoded(text: &str) -> Option<String> {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let high = (*bytes.get(i + 1)? as char).to_digit(16)?;
            let low = (*bytes.get(i + 2)? as char).to_digit(16)?;
            out.push((high << 4 | low) as u8);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// "Thu, 23 Oct 2026 10:15:00 +0200" (the day's name, the seconds and a trailing "(CET)" may be missing) as seconds
/// since 2001.
fn parse_date(header: &str) -> Option<f64> {
    // A trailing "(CET)"-style comment goes: everything from the first "(".
    let cleaned = header.split('(').next().unwrap_or("").trim();
    let mut words: Vec<&str> = cleaned.split_whitespace().collect();
    if words.first().is_some_and(|w| w.ends_with(',')) {
        words.remove(0);
    }
    let [day, month, year, time, zone] = words.as_slice() else { return None };
    let day: i64 = day.parse().ok().filter(|d| (1..=31).contains(d))?;
    let month = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        .iter()
        .position(|m| month.eq_ignore_ascii_case(m))? as i64
        + 1;
    let year: i64 = year.parse().ok().filter(|y| (1000..=9999).contains(y))?;
    let clock: Vec<i64> = time.split(':').map(|p| p.parse().ok()).collect::<Option<_>>()?;
    let (hour, minute, second) = match clock.as_slice() {
        [h, m] => (*h, *m, 0),
        [h, m, s] => (*h, *m, *s),
        _ => return None,
    };
    if hour > 23 || minute > 59 || second > 60 {
        return None;
    }
    let offset = match *zone {
        "GMT" | "UT" | "UTC" | "Z" => 0,
        zone if zone.len() == 5 && (zone.starts_with('+') || zone.starts_with('-')) => {
            let hours: i64 = zone[1..3].parse().ok()?;
            let minutes: i64 = zone[3..5].parse().ok()?;
            let sign = if zone.starts_with('-') { -1 } else { 1 };
            sign * (hours * 3600 + minutes * 60)
        }
        _ => return None,
    };
    let unix = days_from_civil(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second - offset;
    Some((unix - 978_307_200) as f64)
}

/// Days since 1970-01-01 for a date in the proleptic Gregorian calendar (Howard Hinnant's algorithm).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

/// The words of an HTML part, for search: tags, styles and scripts out. One pass, so time grows with the length.
pub fn strip_tags(html: &str) -> String {
    let text: Vec<char> = html.chars().collect();
    let lower: Vec<char> = text.iter().map(|c| c.to_lowercase().next().unwrap_or(*c)).collect();
    let mut out = String::with_capacity(text.len());
    // Once a search for a closing has failed, it fails from anywhere later too: never searched again.
    let mut no_more: Vec<&str> = Vec::new();
    let find = |closing: &'static str, from: usize, no_more: &mut Vec<&str>| -> Option<usize> {
        if no_more.contains(&closing) {
            return None;
        }
        let needle: Vec<char> = closing.chars().collect();
        let found = (from..=lower.len().saturating_sub(needle.len())).find(|&i| lower[i..].starts_with(&needle));
        if found.is_none() {
            no_more.push(closing);
        }
        found
    };
    let starts = |word: &str, at: usize| {
        let w: Vec<char> = word.chars().collect();
        lower.get(at..at + w.len()).is_some_and(|s| s == w.as_slice())
    };
    let mut i = 0;
    while i < text.len() {
        if text[i] != '<' {
            out.push(text[i]);
            i += 1;
            continue;
        }
        if starts("<style", i) {
            if let Some(end) = find("</style>", i, &mut no_more) {
                i = end + 8;
                out.push(' ');
                continue;
            }
        }
        if starts("<script", i) {
            if let Some(end) = find("</script>", i, &mut no_more) {
                i = end + 9;
                out.push(' ');
                continue;
            }
        }
        if i + 1 < text.len() && text[i + 1] != '>' {
            if let Some(end) = find(">", i + 1, &mut no_more) {
                i = end + 1;
                out.push(' ');
                continue;
            }
        }
        out.push(text[i]);
        i += 1;
    }
    out.replace("&nbsp;", " ").split_whitespace().collect::<Vec<_>>().join(" ")
}
