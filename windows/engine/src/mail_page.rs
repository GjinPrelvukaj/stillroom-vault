//! An email's message turned into plain blocks of styled words and pictures, for the app to draw with its own text
//! controls: the Mac's `MailPage` without a web engine. Windows has no web view without Chromium's networking (see
//! `PORT.md`), so nothing here is HTML any more by the time it's shown, and nothing in it can load anything: pictures
//! come only from the email's own bytes (`cid:` parts and `data:` addresses), every other address is dropped, and a
//! link's address is kept only as words to read.
//!
//! The reading is forgiving, as a browser's is, and takes time in step with the message's length however it's built:
//! one pass, raw-text elements skipped with one search each, a bounded stack of open elements.

use std::collections::HashMap;

use base64::Engine as _;
use serde::Serialize;

use crate::email::Email;

/// Everything to draw: blocks of words in order, and the pictures they show.
#[derive(Debug, Default, Serialize)]
pub struct Document {
    pub blocks: Vec<Block>,
    pub pictures: Vec<Picture>,
    /// Whether the message was longer than is shown.
    #[serde(skip_serializing_if = "is_false")]
    pub cut: bool,
}

/// A paragraph, heading, list item, table cell or line: runs of words drawn one after another, wrapping.
#[derive(Debug, Default, Serialize)]
pub struct Block {
    pub runs: Vec<Run>,
    /// 1 to 6 for a heading.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub heading: Option<u8>,
    /// A list item's bullet or number ("•", "3.").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub marker: Option<String>,
    /// How deep in lists.
    #[serde(skip_serializing_if = "is_zero")]
    pub indent: u8,
    /// How deep in quotes (an earlier message quoted in a reply).
    #[serde(skip_serializing_if = "is_zero")]
    pub quoted: u8,
    /// Spaces and line breaks kept as written.
    #[serde(skip_serializing_if = "is_false")]
    pub pre: bool,
    /// A horizontal line, with no runs.
    #[serde(skip_serializing_if = "is_false")]
    pub rule: bool,
}

/// Words in one style, or one picture.
#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Run {
    #[serde(skip_serializing_if = "String::is_empty")]
    pub text: String,
    /// The picture's place in `pictures`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub picture: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    #[serde(skip_serializing_if = "is_false")]
    pub bold: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub italic: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub underline: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub strike: bool,
    #[serde(skip_serializing_if = "is_false")]
    pub mono: bool,
    /// Where a link points, as words to read: never opened.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub link: Option<String>,
}

/// A picture's type and bytes (base64), from inside the email.
#[derive(Debug, Serialize)]
pub struct Picture {
    pub kind: String,
    pub data: String,
}

fn is_false(b: &bool) -> bool {
    !*b
}

fn is_zero(n: &u8) -> bool {
    *n == 0
}

/// The most characters shown; past it the message is cut.
const LONGEST: usize = 1_000_000;
/// The most pictures, and their bytes in all.
const MOST_PICTURES: usize = 512;
const PICTURE_BYTES: usize = 64 << 20;
/// The deepest the open elements are followed; deeper ones are read as text in the style around them.
const DEEPEST: usize = 512;
/// The kinds of picture drawn: plain bitmaps. SVG can name other files, so it isn't.
const PICTURE_KINDS: [&str; 9] =
    ["image/png", "image/jpeg", "image/jpg", "image/pjpeg", "image/gif", "image/bmp", "image/webp", "image/x-icon", "image/vnd.microsoft.icon"];

/// The message as blocks: the sender's HTML when there is one, else the plain text as written.
pub fn document(email: &Email) -> Document {
    match &email.html {
        Some(html) => Reader::new(&email.inline).read(html),
        None => {
            let text = email.text.as_deref().unwrap_or("").replace("\r\n", "\n");
            let mut document = Document::default();
            let shown: String = text.chars().take(LONGEST).collect();
            document.cut = shown.len() < text.len();
            if !shown.trim().is_empty() {
                document.blocks.push(Block { runs: vec![Run { text: shown, ..Run::default() }], pre: true, ..Block::default() });
            }
            document
        }
    }
}

// MARK: Reading

/// The style in force: what every open element adds up to.
#[derive(Clone, Default)]
struct Style {
    hidden: bool,
    bold: bool,
    italic: bool,
    underline: bool,
    strike: bool,
    mono: bool,
    pre: bool,
    link: Option<String>,
    heading: Option<u8>,
    indent: u8,
    quoted: u8,
}

struct Open {
    name: String,
    /// The style inside this element.
    style: Style,
    /// For a list: the next item's number, or None for bullets.
    number: Option<u32>,
}

struct Reader<'a> {
    inline: &'a HashMap<String, (String, Vec<u8>)>,
    stack: Vec<Open>,
    /// Elements past `DEEPEST`, counted so their ends are matched.
    beyond: usize,
    document: Document,
    block: Block,
    /// The next block's list marker.
    marker: Option<String>,
    length: usize,
    picture_bytes: usize,
    /// Pictures already taken, by their `cid:` id.
    taken: HashMap<String, usize>,
}

/// Elements that end a block where they start and end.
const BLOCKS: &[&str] = &[
    "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "table", "tr", "td", "th", "thead",
    "tbody", "tfoot", "caption", "section", "article", "header", "footer", "center", "dl", "dt", "dd", "address", "figure",
    "figcaption", "main", "nav", "aside", "form", "fieldset", "legend", "details", "summary", "body", "html", "hr", "listing",
];
/// Elements whose contents are never shown: their words aren't the message's (styles, scripts) or can't be drawn
/// without loading something (frames, media, objects).
const UNSHOWN: &[&str] = &[
    "head", "svg", "math", "video", "audio", "object", "embed", "iframe", "frame", "frameset", "canvas", "template", "select",
    "datalist", "map", "applet", "picture", "noframes", "noembed",
];
/// Elements whose contents are raw text up to their end tag, not markup.
const RAW: &[&str] = &["script", "style", "title", "textarea", "xmp", "iframe", "noembed", "noframes", "template", "plaintext"];
/// Elements with no end.
const VOID: &[&str] = &[
    "br", "img", "hr", "meta", "link", "input", "area", "base", "col", "embed", "param", "source", "track", "wbr", "keygen",
    "basefont", "bgsound", "frame", "image", "spacer",
];

impl<'a> Reader<'a> {
    fn new(inline: &'a HashMap<String, (String, Vec<u8>)>) -> Self {
        Reader {
            inline,
            stack: Vec::new(),
            beyond: 0,
            document: Document::default(),
            block: Block::default(),
            marker: None,
            length: 0,
            picture_bytes: 0,
            taken: HashMap::new(),
        }
    }

    fn style(&self) -> Style {
        self.stack.last().map(|o| o.style.clone()).unwrap_or_default()
    }

    fn read(mut self, html: &str) -> Document {
        let bytes = html.as_bytes();
        let mut i = 0;
        while i < bytes.len() && !self.document.cut {
            if bytes[i] != b'<' {
                let end = bytes[i..].iter().position(|&b| b == b'<').map_or(bytes.len(), |p| i + p);
                self.words(&decode_entities(&html[i..end]));
                i = end;
                continue;
            }
            let rest = &bytes[i..];
            if rest.starts_with(b"<!--") {
                i = find(bytes, b"-->", i + 4).map_or(bytes.len(), |at| at + 3);
            } else if rest.starts_with(b"<!") || rest.starts_with(b"<?") {
                i = find(bytes, b">", i + 2).map_or(bytes.len(), |at| at + 1);
            } else if rest.len() > 2 && rest[1] == b'/' && rest[2].is_ascii_alphabetic() {
                let (name, _, _, end) = tag(html, i + 2);
                self.end(&name);
                i = end;
            } else if rest.len() > 1 && rest[1].is_ascii_alphabetic() {
                let (name, attributes, closed, end) = tag(html, i + 1);
                i = end;
                if RAW.contains(&name.as_str()) {
                    // Its contents up to "</name" are text, not markup; with no end, the rest of the message is.
                    let closing = format!("</{name}");
                    let stop = find_folded(bytes, closing.as_bytes(), i).unwrap_or(bytes.len());
                    if matches!(name.as_str(), "textarea" | "xmp" | "plaintext") && !self.style().hidden {
                        self.start("pre", &[], false);
                        self.words(&decode_entities(&html[i..stop]));
                        self.end("pre");
                    }
                    i = find(bytes, b">", stop).map_or(bytes.len(), |at| at + 1);
                } else {
                    self.start(&name, &attributes, closed);
                }
            } else {
                self.words("<");
                i += 1;
            }
        }
        self.finish_block();
        self.document
    }

    // MARK: Elements

    fn start(&mut self, name: &str, attributes: &[(String, String)], closed: bool) {
        match name {
            "body" => {
                // A head left open ends where the body starts.
                if let Some(at) = self.stack.iter().rposition(|o| o.name == "head") {
                    self.stack.truncate(at);
                }
            }
            "li" => self.close_open(&["li"], &["ul", "ol"]),
            "td" | "th" => self.close_open(&["td", "th"], &["tr", "table"]),
            "tr" => self.close_open(&["tr"], &["table"]),
            "dt" | "dd" => self.close_open(&["dt", "dd"], &["dl"]),
            "p" => self.close_open(&["p"], &["div", "td", "th", "li", "blockquote", "body"]),
            _ => {}
        }
        if BLOCKS.contains(&name) {
            self.finish_block();
        }
        let style = self.style();
        match name {
            "br" => {
                if !style.hidden {
                    self.line_break();
                }
                return;
            }
            "hr" => {
                if !style.hidden {
                    self.finish_block();
                    self.document.blocks.push(Block { rule: true, quoted: style.quoted, ..Block::default() });
                }
                return;
            }
            "img" => {
                if !style.hidden && !is_hidden(attributes) {
                    self.picture(attributes);
                }
                return;
            }
            _ => {}
        }
        if VOID.contains(&name) || closed && !BLOCKS.contains(&name) && !UNSHOWN.contains(&name) {
            return;
        }
        let mut inner = style.clone();
        inner.hidden |= UNSHOWN.contains(&name) || is_hidden(attributes);
        let mut number = None;
        match name {
            "b" | "strong" | "th" => inner.bold = true,
            "i" | "em" | "cite" | "dfn" | "var" => inner.italic = true,
            "u" | "ins" => inner.underline = true,
            "s" | "strike" | "del" => inner.strike = true,
            "code" | "tt" | "kbd" | "samp" => inner.mono = true,
            "pre" | "listing" => {
                inner.pre = true;
                inner.mono = true;
            }
            "a" => {
                if let Some(href) = attribute(attributes, "href") {
                    let href: String = href.trim().chars().take(2048).collect();
                    if !href.is_empty() {
                        inner.link = Some(href);
                        inner.underline = true;
                    }
                }
            }
            "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
                inner.heading = Some(name.as_bytes()[1] - b'0');
                inner.bold = true;
            }
            "ul" | "ol" => {
                inner.indent = inner.indent.saturating_add(1).min(8);
                if name == "ol" {
                    number = Some(attribute(attributes, "start").and_then(|s| s.trim().parse().ok()).unwrap_or(1));
                }
            }
            "blockquote" => inner.quoted = inner.quoted.saturating_add(1).min(8),
            "dd" => inner.indent = inner.indent.saturating_add(1).min(8),
            "li" => {
                let list = self.stack.iter_mut().rev().find(|o| o.name == "ul" || o.name == "ol");
                self.marker = Some(match list.and_then(|l| l.number.as_mut()) {
                    Some(n) => {
                        let shown = format!("{n}.");
                        *n = n.saturating_add(1);
                        shown
                    }
                    None => "•".into(),
                });
            }
            _ => {}
        }
        if let Some(css) = attribute(attributes, "style") {
            let css = css.to_ascii_lowercase().replace([' ', '\t', '\n', '\r'], "");
            if ["font-weight:bold", "font-weight:bolder", "font-weight:600", "font-weight:700", "font-weight:800", "font-weight:900"]
                .iter()
                .any(|w| css.contains(w))
            {
                inner.bold = true;
            }
            if css.contains("font-style:italic") || css.contains("font-style:oblique") {
                inner.italic = true;
            }
            if css.contains("text-decoration:underline") {
                inner.underline = true;
            }
            if css.contains("line-through") {
                inner.strike = true;
            }
        }
        if self.stack.len() >= DEEPEST {
            self.beyond += 1;
            return;
        }
        self.stack.push(Open { name: name.to_owned(), style: inner, number });
    }

    fn end(&mut self, name: &str) {
        if name == "br" {
            // "</br>" is read as "<br>", as browsers do.
            return self.start("br", &[], true);
        }
        if BLOCKS.contains(&name) {
            self.finish_block();
        }
        if self.beyond > 0 && !self.stack.iter().any(|o| o.name == name) {
            self.beyond -= 1;
            return;
        }
        if let Some(at) = self.stack.iter().rposition(|o| o.name == name) {
            self.stack.truncate(at);
        }
        if name == "li" {
            self.marker = None;
        }
    }

    /// Ends an open `names` element before another starts, unless one of `walls` is open inside it first: a new list
    /// item ends the one before, but not one in an outer list.
    fn close_open(&mut self, names: &[&str], walls: &[&str]) {
        for at in (0..self.stack.len()).rev() {
            let open = self.stack[at].name.as_str();
            if walls.contains(&open) {
                return;
            }
            if names.contains(&open) {
                self.finish_block();
                self.stack.truncate(at);
                return;
            }
        }
    }

    // MARK: Contents

    fn words(&mut self, text: &str) {
        let style = self.style();
        if style.hidden || text.is_empty() {
            return;
        }
        if style.pre {
            let text = text.replace("\r\n", "\n");
            // A newline straight after <pre> isn't part of its text.
            let text = if self.block.runs.is_empty() { text.strip_prefix('\n').unwrap_or(&text).to_owned() } else { text };
            self.push(&text, &style);
            return;
        }
        // Each stretch of spaces and line ends becomes one space, kept in the style it was written in; none starts a
        // block or follows a line break.
        let mut collapsed = String::with_capacity(text.len());
        for c in text.chars() {
            if matches!(c, ' ' | '\t' | '\n' | '\r' | '\x0C') {
                if if collapsed.is_empty() { self.ends_in_words() } else { !collapsed.ends_with(' ') } {
                    collapsed.push(' ');
                }
                continue;
            }
            collapsed.push(c);
        }
        if !collapsed.is_empty() {
            self.push(&collapsed, &style);
        }
    }

    /// Whether the block so far ends in words or a picture (so a space may follow), not a space or line break.
    fn ends_in_words(&self) -> bool {
        self.block.runs.last().is_some_and(|r| r.picture.is_some() || r.text.chars().last().is_some_and(|c| c != '\n' && c != ' '))
    }

    fn push(&mut self, text: &str, style: &Style) {
        let mut text = text;
        if self.length + text.len() > LONGEST {
            self.document.cut = true;
            let mut fits = LONGEST - self.length;
            while !text.is_char_boundary(fits) {
                fits -= 1;
            }
            text = &text[..fits];
            if text.is_empty() {
                return;
            }
        }
        self.length += text.len();
        self.begin_block(style);
        let run = Run {
            bold: style.bold,
            italic: style.italic,
            underline: style.underline,
            strike: style.strike,
            mono: style.mono,
            link: style.link.clone(),
            ..Run::default()
        };
        match self.block.runs.last_mut() {
            Some(last) if last.picture.is_none() && same_style(last, &run) => last.text.push_str(text),
            _ => self.block.runs.push(Run { text: text.to_owned(), ..run }),
        }
    }

    fn line_break(&mut self) {
        let style = self.style();
        self.trim_end(' ');
        self.push("\n", &style);
    }

    /// The block takes its heading, list and quote from where its first words are.
    fn begin_block(&mut self, style: &Style) {
        if self.block.runs.is_empty() {
            self.block.heading = style.heading;
            self.block.indent = style.indent;
            self.block.quoted = style.quoted;
            self.block.pre = style.pre;
            self.block.marker = self.marker.take();
        }
    }

    /// Spaces (and `also`) at the end of the block so far, taken off: they'd draw nothing.
    fn trim_end(&mut self, also: char) {
        while let Some(last) = self.block.runs.last_mut().filter(|r| r.picture.is_none()) {
            let kept = last.text.trim_end_matches([' ', also]).len();
            last.text.truncate(kept);
            if !last.text.is_empty() {
                return;
            }
            self.block.runs.pop();
        }
    }

    fn finish_block(&mut self) {
        if !self.block.pre {
            self.trim_end('\n');
        }
        let block = std::mem::take(&mut self.block);
        let shows = block.runs.iter().any(|r| r.picture.is_some() || !r.text.trim().is_empty());
        if shows {
            self.document.blocks.push(block);
        } else if block.marker.is_some() {
            // An item whose words haven't come yet keeps its marker for them.
            self.marker = block.marker;
        }
    }

    fn picture(&mut self, attributes: &[(String, String)]) {
        let Some(source) = attribute(attributes, "src").map(str::trim) else { return };
        let found = if source.len() > 4 && source[..4].eq_ignore_ascii_case("cid:") {
            let id = source[4..].trim_matches(|c| c == '<' || c == '>');
            match self.taken.get(id) {
                Some(&index) => Some(index),
                None => self.inline.get(id).and_then(|(kind, data)| {
                    let index = self.keep_picture(kind, data)?;
                    self.taken.insert(id.to_owned(), index);
                    Some(index)
                }),
            }
        } else if source.len() > 5 && source[..5].eq_ignore_ascii_case("data:") {
            data_address(&source[5..]).and_then(|(kind, data)| self.keep_picture(&kind, &data))
        } else {
            // Anything else would be loaded from somewhere: never.
            None
        };
        let Some(index) = found else { return };
        let size = |name| attribute(attributes, name).and_then(|v| v.trim().trim_end_matches("px").parse::<u32>().ok()).filter(|&v| v > 0 && v <= 10_000);
        let style = self.style();
        self.begin_block(&style);
        self.block.runs.push(Run { picture: Some(index), width: size("width"), height: size("height"), link: style.link.clone(), ..Run::default() });
    }

    fn keep_picture(&mut self, kind: &str, data: &[u8]) -> Option<usize> {
        let kind = kind.trim().to_ascii_lowercase();
        if !PICTURE_KINDS.contains(&kind.as_str()) || data.is_empty() {
            return None;
        }
        if self.document.pictures.len() >= MOST_PICTURES || self.picture_bytes + data.len() > PICTURE_BYTES {
            return None;
        }
        self.picture_bytes += data.len();
        self.document.pictures.push(Picture { kind, data: base64::engine::general_purpose::STANDARD.encode(data) });
        Some(self.document.pictures.len() - 1)
    }
}

// MARK: Pieces

/// A tag from just after its "<" (or "</"): its name in lower case, its attributes, whether it closed itself ("/>"),
/// and where it ends.
fn tag(html: &str, from: usize) -> (String, Vec<(String, String)>, bool, usize) {
    let bytes = html.as_bytes();
    let mut i = from;
    while i < bytes.len() && !matches!(bytes[i], b' ' | b'\t' | b'\n' | b'\r' | b'\x0C' | b'/' | b'>') {
        i += 1;
    }
    let name = html[from..i].to_ascii_lowercase();
    let mut attributes = Vec::new();
    let mut closed = false;
    loop {
        while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\n' | b'\r' | b'\x0C') {
            i += 1;
        }
        if i >= bytes.len() {
            return (name, attributes, closed, bytes.len());
        }
        match bytes[i] {
            b'>' => return (name, attributes, closed, i + 1),
            b'/' => {
                closed = true;
                i += 1;
                continue;
            }
            _ => closed = false,
        }
        let start = i;
        while i < bytes.len() && !matches!(bytes[i], b' ' | b'\t' | b'\n' | b'\r' | b'\x0C' | b'/' | b'>' | b'=') || i == start && i < bytes.len() && bytes[i] == b'=' {
            i += 1;
        }
        let key = html[start..i].to_ascii_lowercase();
        while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\n' | b'\r' | b'\x0C') {
            i += 1;
        }
        let mut value = String::new();
        if i < bytes.len() && bytes[i] == b'=' {
            i += 1;
            while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\n' | b'\r' | b'\x0C') {
                i += 1;
            }
            if i < bytes.len() && (bytes[i] == b'"' || bytes[i] == b'\'') {
                let quote = bytes[i];
                let end = bytes[i + 1..].iter().position(|&b| b == quote).map_or(bytes.len(), |p| i + 1 + p);
                value = decode_entities(&html[i + 1..end]);
                i = (end + 1).min(bytes.len());
            } else {
                let start = i;
                while i < bytes.len() && !matches!(bytes[i], b' ' | b'\t' | b'\n' | b'\r' | b'\x0C' | b'>') {
                    i += 1;
                }
                value = decode_entities(&html[start..i]);
            }
        }
        // The first of a repeated attribute counts, as in a browser; a tag with hundreds of them keeps the first 64.
        if !key.is_empty() && attributes.len() < 64 && !attributes.iter().any(|(k, _)| *k == key) {
            attributes.push((key, value));
        }
    }
}

fn same_style(a: &Run, b: &Run) -> bool {
    (a.bold, a.italic, a.underline, a.strike, a.mono) == (b.bold, b.italic, b.underline, b.strike, b.mono) && a.link == b.link
}

fn attribute<'b>(attributes: &'b [(String, String)], name: &str) -> Option<&'b str> {
    attributes.iter().find(|(k, _)| k == name).map(|(_, v)| v.as_str())
}

/// Hidden by the sender: the `hidden` attribute, or a style that hides it (an email's "preheader", the line meant
/// only for the inbox's list).
fn is_hidden(attributes: &[(String, String)]) -> bool {
    if attribute(attributes, "hidden").is_some() {
        return true;
    }
    attribute(attributes, "style").is_some_and(|css| {
        let css = css.to_ascii_lowercase().replace([' ', '\t', '\n', '\r'], "");
        css.contains("display:none") || css.contains("visibility:hidden") || css.contains("mso-hide:all")
    })
}

fn find(bytes: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if from >= bytes.len() {
        return None;
    }
    bytes[from..].windows(needle.len()).position(|w| w == needle).map(|p| from + p)
}

/// `find`, ignoring ASCII case.
fn find_folded(bytes: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if from >= bytes.len() {
        return None;
    }
    bytes[from..].windows(needle.len()).position(|w| w.eq_ignore_ascii_case(needle)).map(|p| from + p)
}

/// "image/png;base64,iVBOR…" (after "data:") to its type and bytes.
fn data_address(address: &str) -> Option<(String, Vec<u8>)> {
    let (head, payload) = address.split_once(',')?;
    let mut pieces = head.split(';');
    let kind = pieces.next()?.trim().to_owned();
    let base64 = pieces.any(|p| p.trim().eq_ignore_ascii_case("base64"));
    let data = if base64 {
        let clean: String = payload.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '+' || *c == '/').collect();
        base64::engine::general_purpose::STANDARD_NO_PAD.decode(clean.trim_end_matches('=')).ok()?
    } else {
        percent_bytes(payload)
    };
    Some((kind, data))
}

fn percent_bytes(text: &str) -> Vec<u8> {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(high), Some(low)) = ((bytes[i + 1] as char).to_digit(16), (bytes[i + 2] as char).to_digit(16)) {
                out.push((high << 4 | low) as u8);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    out
}

/// "&amp;", "&eacute;", "&#233;" and "&#xE9;" to their characters; anything not a known reference stays as written.
pub fn decode_entities(text: &str) -> String {
    if !text.contains('&') {
        return text.to_owned();
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find('&') {
        out.push_str(&rest[..at]);
        rest = &rest[at..];
        match reference(rest) {
            Some((decoded, used)) => {
                out.push_str(&decoded);
                rest = &rest[used..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// One reference at the start of `text` ("&…"): what it stands for and how many bytes it used.
fn reference(text: &str) -> Option<(String, usize)> {
    let bytes = text.as_bytes();
    if bytes.get(1) == Some(&b'#') {
        let hex = matches!(bytes.get(2), Some(b'x' | b'X'));
        let start = if hex { 3 } else { 2 };
        let digits = bytes[start..].iter().take_while(|b| if hex { b.is_ascii_hexdigit() } else { b.is_ascii_digit() }).count();
        if digits == 0 {
            return None;
        }
        let value = u32::from_str_radix(&text[start..start + digits.min(8)], if hex { 16 } else { 10 }).unwrap_or(0xFFFD);
        let c = match value {
            0 => '\u{FFFD}',
            0x80..=0x9F => windows_1252(value),
            _ => char::from_u32(value).unwrap_or('\u{FFFD}'),
        };
        let mut used = start + digits;
        if bytes.get(used) == Some(&b';') {
            used += 1;
        }
        return Some((c.to_string(), used));
    }
    let name_length = bytes[1..].iter().take_while(|b| b.is_ascii_alphanumeric()).count();
    let name = &text[1..1 + name_length];
    let semicolon = bytes.get(1 + name_length) == Some(&b';');
    let c = named(name)?;
    if !semicolon && !matches!(name, "amp" | "lt" | "gt" | "quot" | "nbsp" | "copy" | "reg") {
        return None;
    }
    Some((c.to_owned(), 1 + name_length + usize::from(semicolon)))
}

/// Numeric references in 0x80–0x9F mean Windows-1252's characters there, as browsers read them.
fn windows_1252(value: u32) -> char {
    let byte = [value as u8];
    encoding_rs::WINDOWS_1252.decode_without_bom_handling(&byte).0.chars().next().unwrap_or('\u{FFFD}')
}

fn named(name: &str) -> Option<&'static str> {
    Some(match name {
        "amp" => "&",
        "lt" => "<",
        "gt" => ">",
        "quot" => "\"",
        "apos" => "'",
        "nbsp" => "\u{A0}",
        "ensp" => "\u{2002}",
        "emsp" => "\u{2003}",
        "thinsp" => "\u{2009}",
        "zwnj" => "\u{200C}",
        "zwj" => "\u{200D}",
        "shy" => "\u{AD}",
        "copy" => "©",
        "reg" => "®",
        "trade" => "™",
        "hellip" => "…",
        "mdash" => "—",
        "ndash" => "–",
        "lsquo" => "‘",
        "rsquo" => "’",
        "sbquo" => "‚",
        "ldquo" => "“",
        "rdquo" => "”",
        "bdquo" => "„",
        "laquo" => "«",
        "raquo" => "»",
        "lsaquo" => "‹",
        "rsaquo" => "›",
        "bull" => "•",
        "middot" => "·",
        "deg" => "°",
        "times" => "×",
        "divide" => "÷",
        "plusmn" => "±",
        "euro" => "€",
        "pound" => "£",
        "yen" => "¥",
        "cent" => "¢",
        "sect" => "§",
        "para" => "¶",
        "dagger" => "†",
        "Dagger" => "‡",
        "permil" => "‰",
        "prime" => "′",
        "larr" => "←",
        "rarr" => "→",
        "uarr" => "↑",
        "darr" => "↓",
        "hearts" => "♥",
        "check" => "✓",
        "frac12" => "½",
        "frac14" => "¼",
        "frac34" => "¾",
        "sup1" => "¹",
        "sup2" => "²",
        "sup3" => "³",
        "iexcl" => "¡",
        "iquest" => "¿",
        "szlig" => "ß",
        "agrave" => "à",
        "aacute" => "á",
        "acirc" => "â",
        "atilde" => "ã",
        "auml" => "ä",
        "aring" => "å",
        "aelig" => "æ",
        "ccedil" => "ç",
        "egrave" => "è",
        "eacute" => "é",
        "ecirc" => "ê",
        "euml" => "ë",
        "igrave" => "ì",
        "iacute" => "í",
        "icirc" => "î",
        "iuml" => "ï",
        "ntilde" => "ñ",
        "ograve" => "ò",
        "oacute" => "ó",
        "ocirc" => "ô",
        "otilde" => "õ",
        "ouml" => "ö",
        "oslash" => "ø",
        "ugrave" => "ù",
        "uacute" => "ú",
        "ucirc" => "û",
        "uuml" => "ü",
        "yacute" => "ý",
        "yuml" => "ÿ",
        "Agrave" => "À",
        "Aacute" => "Á",
        "Acirc" => "Â",
        "Atilde" => "Ã",
        "Auml" => "Ä",
        "Aring" => "Å",
        "AElig" => "Æ",
        "Ccedil" => "Ç",
        "Egrave" => "È",
        "Eacute" => "É",
        "Ecirc" => "Ê",
        "Euml" => "Ë",
        "Igrave" => "Ì",
        "Iacute" => "Í",
        "Icirc" => "Î",
        "Iuml" => "Ï",
        "Ntilde" => "Ñ",
        "Ograve" => "Ò",
        "Oacute" => "Ó",
        "Ocirc" => "Ô",
        "Otilde" => "Õ",
        "Ouml" => "Ö",
        "Oslash" => "Ø",
        "Ugrave" => "Ù",
        "Uacute" => "Ú",
        "Ucirc" => "Û",
        "Uuml" => "Ü",
        "Yacute" => "Ý",
        "scaron" => "š",
        "Scaron" => "Š",
        "zcaron" => "ž",
        "Zcaron" => "Ž",
        "ccaron" => "č",
        "Ccaron" => "Č",
        "oelig" => "œ",
        "OElig" => "Œ",
        _ => return None,
    })
}
