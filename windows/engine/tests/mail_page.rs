//! The email viewer's message, as the app draws it (`mail_page`): the Mac's `MailLockdownTests` guarantee at its
//! source. A hostile email, every way HTML and CSS can load something pointed at this PC, comes out with no address
//! left in it but a link's, which is only words. The app's own end-to-end check (a real window and a server counting
//! connections) is `Stillroom.exe --mail-lockdown` in a development build.

use std::time::{Duration, Instant};

use base64::Engine as _;
use serde_json::Value;
use stillroom_core::email::parse;
use stillroom_core::mail_page::{decode_entities, document, Document};

fn shown(html: &str) -> Document {
    let mail = format!("From: a@example.com\nSubject: Test\nContent-Type: text/html; charset=utf-8\n\n{html}");
    document(&parse(mail.as_bytes()).unwrap())
}

/// The blocks' words, one line per block.
fn words(document: &Document) -> String {
    document.blocks.iter().map(|b| b.runs.iter().map(|r| r.text.as_str()).collect::<String>()).collect::<Vec<_>>().join("\n")
}

/// Every way HTML and CSS can load something, at two names for this PC (the Mac test's list, and a link).
fn hostile(port: u16) -> String {
    let hosts = [format!("http://127.0.0.1:{port}"), format!("http://localhost:{port}")];
    let loads: String = hosts
        .iter()
        .map(|h| {
            format!(
                r#"<img src="{h}/img"><img srcset="{h}/srcset 2x"><picture><source srcset="{h}/picture"></picture>
                <link rel="stylesheet" href="{h}/css"><link rel="prefetch" href="{h}/prefetch">
                <link rel="preconnect" href="{h}"><link rel="dns-prefetch" href="{h}"><link rel="icon" href="{h}/icon">
                <style>@import url({h}/import); body {{ background: url({h}/background) }}
                @font-face {{ font-family: remote; src: url({h}/font) }} p {{ font-family: remote }}</style>
                <p style="background-image: url({h}/inline)">text</p>
                <iframe src="{h}/frame"></iframe><script src="{h}/script"></script>
                <video poster="{h}/poster" src="{h}/video" autoplay></video><audio src="{h}/audio" autoplay></audio>
                <object data="{h}/object"></object><embed src="{h}/embed">
                <form action="{h}/form"><input type="image" src="{h}/input"></form>
                <svg><image href="{h}/svg" width="10" height="10"/></svg>
                <table background="{h}/table"><tr><td background="{h}/cell">cell</td></tr></table>
                <img src="//{}/scheme-relative"><img src=" {h}/spaced "><img src="file:///C:/Windows/win.ini">
                <a href="{h}/link">a link</a>"#,
                h.trim_start_matches("http://")
            )
        })
        .collect();
    format!(
        r#"<html><head><title>lockdown</title><meta http-equiv="refresh" content="0;url={0}/refresh">
        <base href="{0}/base/"></head><body><img src="relative.png">{loads}</body></html>"#,
        hosts[0]
    )
}

/// Every place an address could hide in the document: nowhere but a link's words.
#[test]
fn a_hostile_email_keeps_no_address_but_a_links_words() {
    let document = shown(&hostile(8123));
    let mut json: Value = serde_json::to_value(&document).unwrap();
    let mut links = 0;
    for block in json["blocks"].as_array_mut().unwrap() {
        for run in block["runs"].as_array_mut().unwrap() {
            if let Some(link) = run.as_object_mut().unwrap().remove("link") {
                assert!(link.as_str().unwrap().ends_with("/link"), "only the <a> gives a link: {link}");
                links += 1;
            }
        }
    }
    assert_eq!(links, 2, "one link per host");
    let rest = json.to_string();
    for host in ["127.0.0.1", "localhost", "8123", "file:", "win.ini", "relative.png", "http"] {
        assert!(!rest.contains(host), "{host} in {rest}");
    }
    assert!(document.pictures.is_empty(), "no picture from outside the email");
    let words = words(&document);
    assert!(words.contains("text") && words.contains("cell") && words.contains("a link"));
    assert!(!words.contains("lockdown") && !words.contains("font-family"), "titles and styles aren't words: {words}");
}

/// Pictures come only from inside the email: its `cid:` parts and `data:` addresses, bitmaps only, each part once.
#[test]
fn pictures_come_only_from_inside_the_email() {
    let b64 = |b: &[u8]| base64::engine::general_purpose::STANDARD.encode(b);
    let png = b64(&[0x89, b'P', b'N', b'G', 1, 2, 3]);
    let svg = b64(b"<svg xmlns='http://www.w3.org/2000/svg'><image href='http://127.0.0.1/x'/></svg>");
    let html = b64(format!(
        r#"<p>Logo <img src="cid:logo@x" width="120" height="40px"> and again <img src="CID:logo@x"></p>
        <img src="data:image/png;base64,{png}"><img src="data:image/svg+xml;base64,{svg}"><img src="cid:missing">"#
    )
    .as_bytes());
    let mail = format!(
        "From: a@example.com\nSubject: Pictures\nContent-Type: multipart/related; boundary=rel\n\n\
         --rel\nContent-Type: text/html; charset=utf-8\nContent-Transfer-Encoding: base64\n\n{html}\n\
         --rel\nContent-Type: image/png\nContent-ID: <logo@x>\nContent-Transfer-Encoding: base64\n\n{png}\n--rel--"
    );
    let document = document(&parse(mail.as_bytes()).unwrap());
    assert_eq!(document.pictures.len(), 2, "the cid part once, the data: PNG; never the SVG");
    assert!(document.pictures.iter().all(|p| p.kind == "image/png" && p.data == png));
    let pictures: Vec<_> = document.blocks.iter().flat_map(|b| &b.runs).filter(|r| r.picture.is_some()).collect();
    assert_eq!(pictures.len(), 3);
    assert_eq!((pictures[0].picture, pictures[0].width, pictures[0].height), (Some(0), Some(120), Some(40)));
    assert_eq!(pictures[1].picture, Some(0));
    assert_eq!(words(&document).lines().next(), Some("Logo  and again "));
}

#[test]
fn structure_comes_through_as_blocks() {
    let document = shown(
        "<h1>Title</h1><p>One <b>bold</b> and <i>slanted</i>,\n   spread   out.<br>Next line</p>\
         <ul><li>first<li>second<ol start=3><li>three</li><li>four</ol></ul>\
         <blockquote>quoted <span style='font-weight: 700'>loud</span></blockquote><hr>\
         <pre>\n  kept   as is\n</pre><table><tr><td>a</td><td>b</td></tr></table>",
    );
    let blocks = &document.blocks;
    assert_eq!(blocks[0].heading, Some(1));
    assert_eq!(words(&document).lines().nth(1), Some("One bold and slanted, spread out."));
    assert_eq!(blocks[1].runs.iter().find(|r| r.text == "bold").map(|r| r.bold), Some(true));
    assert!(blocks[1].runs.iter().any(|r| r.italic && r.text == "slanted"));
    assert!(blocks[1].runs.last().unwrap().text.ends_with("out.\nNext line"));
    let items: Vec<_> = blocks.iter().filter(|b| b.marker.is_some()).map(|b| (b.marker.clone().unwrap(), b.indent)).collect();
    assert_eq!(items, [("•".into(), 1), ("•".into(), 1), ("3.".into(), 2), ("4.".into(), 2)]);
    let quote = blocks.iter().find(|b| b.quoted == 1).unwrap();
    assert!(quote.runs.iter().any(|r| r.bold && r.text == "loud"));
    assert!(blocks.iter().any(|b| b.rule));
    let pre = blocks.iter().find(|b| b.pre).unwrap();
    assert_eq!(pre.runs[0].text, "  kept   as is\n");
    assert!(pre.runs[0].mono);
    assert!(words(&document).ends_with("a\nb"));
}

/// What the sender hid stays hidden (the preheader meant only for the inbox's list), as do scripts and styles.
#[test]
fn hidden_things_stay_hidden() {
    let document = shown(
        "<div style='display:none;max-height:0'>preheader</div><span hidden>secret</span>\
         <p style='mso-hide: all'>outlook only</p><script>alert('x')</script><style>p{}</style>shown",
    );
    assert_eq!(words(&document), "shown");
}

#[test]
fn entities_are_read_as_a_browser_reads_them() {
    assert_eq!(decode_entities("Caf&eacute; &amp; b&#228;r &#x2713; &nbsp;&copy &bogus; &#150; & done"), "Café & bär ✓ \u{A0}© &bogus; – & done");
    assert_eq!(decode_entities("&#0; &#xD800; &#99999999999;"), "\u{FFFD} \u{FFFD} \u{FFFD}");
}

#[test]
fn plain_text_mail_is_shown_as_written() {
    let mail = "From: a@example.com\nSubject: Plain\n\nLine one\n  indented <b>not bold</b>\n\nAfter a gap";
    let document = document(&parse(mail.as_bytes()).unwrap());
    assert_eq!(document.blocks.len(), 1);
    assert!(document.blocks[0].pre);
    assert_eq!(document.blocks[0].runs[0].text, "Line one\n  indented <b>not bold</b>\n\nAfter a gap");
}

/// Messages built to be slow or deep take time in step with their length, and are cut past a million characters.
#[test]
fn hostile_shapes_stay_quick() {
    let shapes = [
        "<".repeat(2_000_000),
        "<div>".repeat(300_000),
        "<b>".repeat(300_000) + &"x".repeat(10),
        "<!--".to_owned() + &"x".repeat(2_000_000),
        "<style>".to_owned() + &"p{}".repeat(600_000),
        "<a href='".to_owned() + &"x".repeat(2_000_000),
        "&#".repeat(1_000_000),
        "a ".repeat(1_000_000),
        "<img src=cid:x>".repeat(200_000),
        "<li>".repeat(300_000),
        "</p>".repeat(500_000),
    ];
    for html in shapes {
        let started = Instant::now();
        let document = shown(&html);
        let took = started.elapsed();
        assert!(took < Duration::from_secs(10), "{took:?} for {}…", &html[..20]);
        let length: usize = document.blocks.iter().flat_map(|b| &b.runs).map(|r| r.text.len()).sum();
        assert!(length <= 1_000_000);
    }
    assert!(shown(&"word ".repeat(400_000)).cut);
}
