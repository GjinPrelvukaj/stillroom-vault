//! Two-factor codes, password strength, password import, email and search words, as the Mac's OneTimeCodeTests,
//! PasswordStrengthTests, PasswordImportTests and EmailTests check them.

use base64::Engine as _;
use stillroom_core::email::{self, parse};
use stillroom_core::import::{logins, NotAnExport};
use stillroom_core::kinds::{look, uti_for_name, Look};
use stillroom_core::list::{Entry, Item, Secret, SecretField, Template};
use stillroom_core::otp::{in_field, Algorithm, OneTimeCode};
use stillroom_core::{search, strength};

// MARK: Kinds

/// Each kind gets the Mac's symbol and shelf (`VaultFile.symbol`, `Shelf.of`): an SVG is a picture though it's text, a
/// font isn't a document, an archive goes on Other.
#[test]
fn kinds_look_and_shelve_as_on_the_mac() {
    for (name, expected, shelf) in [
        ("photo.jpg", Look::Picture, "images"),
        ("drawing.svg", Look::Picture, "images"),
        ("song.mp3", Look::Audio, "media"),
        ("voice.m4a", Look::Audio, "media"),
        ("clip.mov", Look::Video, "media"),
        ("w2.pdf", Look::Pdf, "documents"),
        ("notes.md", Look::Text, "documents"),
        ("table.csv", Look::Text, "documents"),
        ("letter.rtf", Look::Text, "documents"),
        ("report.docx", Look::Document, "documents"),
        ("budget.xlsx", Look::Document, "documents"),
        ("backup.zip", Look::Archive, "other"),
        ("old.tar", Look::Archive, "other"),
        ("setup.exe", Look::Other, "other"),
    ] {
        let found = look(uti_for_name(name));
        assert_eq!(found, expected, "{name}");
        assert_eq!(found.shelf(), shelf, "{name}");
    }
    assert_eq!(look("public.truetype-ttf-font"), Look::Other);
}

// MARK: Two-factor codes

/// RFC 6238 appendix B: the same 8-digit codes every authenticator gives.
#[test]
fn rfc_6238_vectors() {
    let seed = |n: usize| "1234567890".repeat(7).as_bytes()[..n].to_vec();
    for (time, sha1, sha256, sha512) in [
        (59.0, "94287082", "46119246", "90693936"),
        (1_111_111_109.0, "07081804", "68084774", "25091201"),
        (1_234_567_890.0, "89005924", "91819424", "93441116"),
        (20_000_000_000.0, "65353130", "77737706", "47863826"),
    ] {
        assert_eq!(OneTimeCode::new(seed(20), 8, 30, Algorithm::Sha1).code(time), sha1);
        assert_eq!(OneTimeCode::new(seed(32), 8, 30, Algorithm::Sha256).code(time), sha256);
        assert_eq!(OneTimeCode::new(seed(64), 8, 30, Algorithm::Sha512).code(time), sha512);
    }
}

#[test]
fn reads_links_and_keys() {
    // "12345678901234567890" in base32.
    let key = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
    let link = OneTimeCode::parse(&format!("otpauth://totp/Site:me@x.com?secret={key}&issuer=Site&digits=8&period=30&algorithm=SHA1")).unwrap();
    assert_eq!(link.code(59.0), "94287082");
    let pasted = OneTimeCode::parse("gezd gnbv gy3t qojq gezd gnbv gy3t qojq").unwrap();
    assert_eq!((pasted.key.clone(), pasted.digits), (link.key.clone(), 6));
    assert_eq!(pasted.code(59.0), "287082");
    assert!(OneTimeCode::parse(&format!("otpauth://hotp/Site?secret={key}&counter=1")).is_none());
    assert!(OneTimeCode::parse(&format!("otpauth://totp/Site?secret={key}&digits=12")).is_none());
    assert!(OneTimeCode::parse("not a key at all").is_none());
    assert!(OneTimeCode::parse("ABC").is_none());
    assert_eq!(link.seconds_left(59.0), 1);
    // An escaped secret in a link reads as the plain one.
    let escaped = OneTimeCode::parse(&format!("otpauth://totp/x%20y?secret={}%3D%3D", &key[..30])).unwrap();
    assert_eq!(escaped.key, OneTimeCode::parse(&key[..30]).unwrap().key);
}

#[test]
fn fields_with_a_setup_show_codes() {
    let key = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
    assert!(in_field("Two-factor setup", key).is_some());
    assert!(in_field("Anything", &format!("otpauth://totp/x?secret={key}")).is_some());
    // A password that happens to be valid base32 isn't mistaken for a setup.
    assert!(in_field("Password", key).is_none());
}

// MARK: Password strength

/// Guessable passwords are refused even when long enough; random ones and a few random words pass.
#[test]
fn guessable_passwords_are_refused() {
    for password in ["Password12345", "P@ssw0rd2024!", "qwertyuiop12", "aaaaaaaaaaaa", "ilovemycat123", "MyDogMax2019!",
                     "letmein123456", "Summer2026!!!", "abcdefghijkl", "123456789012", "Kosovo2008!!!"] {
        assert!(!strength::is_enough(password), "{password}: {} bits", strength::bits(password));
    }
}

#[test]
fn strong_passwords_pass() {
    for password in ["k8#Pq2!xVz9m", "correct horse battery staple", "purple elephant dancing slowly", "tVq9-Lm3x-Rr8w",
                     "my blue bicycle rusts in rain"] {
        assert!(strength::is_enough(password), "{password}: {} bits", strength::bits(password));
    }
}

// MARK: Password import

#[test]
fn reads_an_apple_passwords_export() {
    let csv = "\u{FEFF}Title,URL,Username,Password,Notes,OTPAuth\n\
               github.com (gjin),https://github.com/,gjin,\"pa,ss\"\"word\",,otpauth://totp/GitHub:gjin?secret=ABC\n\
               Bank,https://www.mybank.com/login,me@example.com,hunter2,\"line one\nline two\",\n\
               ,https://example.org,,,,\n\n";
    let found = logins(csv.as_bytes()).unwrap();
    assert_eq!(found.len(), 2);
    assert_eq!(found[0].password, "pa,ss\"word");
    assert!(found[0].otp.starts_with("otpauth://"));
    assert_eq!(found[1].notes, "line one\nline two");
    assert_eq!(found[1].key(), "mybank.com|me@example.com");
    let secret = found[1].secret();
    assert_eq!(secret.template, Template::Login);
    assert_eq!(secret.fields.iter().map(|f| f.label.as_str()).collect::<Vec<_>>(), ["Website", "Username", "Password", "Notes"]);
    assert!(secret.fields[2].concealed);
    // The two-factor setup goes in concealed.
    let otp = found[0].secret();
    assert_eq!((otp.fields[3].label.as_str(), otp.fields[3].concealed), ("Two-factor setup", true));
}

#[test]
fn reads_bitwarden_chrome_and_edge_exports() {
    let bitwarden = "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n\
                     ,,login,Mail,,,0,https://mail.example.com,me,secret1,\n\
                     ,,card,Visa,,,0,,,,\n";
    let chrome = "name,url,username,password,note\nexample.com,https://example.com/,bob,pw,\n";
    assert_eq!(logins(bitwarden.as_bytes()).unwrap().iter().map(|l| l.name()).collect::<Vec<_>>(), ["Mail"]);
    assert_eq!(logins(chrome.as_bytes()).unwrap()[0].username, "bob");
    // Named from the site when the export has no title.
    let untitled = logins(b"url,username,password\nhttps://www.shop.com/a,me,pw\n").unwrap();
    assert_eq!(untitled[0].name(), "shop.com");
    assert_eq!(logins(b"hello,world\n1,2\n"), Err(NotAnExport));
    // Windows line endings, as Excel and Edge write them.
    assert_eq!(logins(b"name,url,username,password\r\nA,https://a.com,me,pw\r\n").unwrap()[0].password, "pw");
}

// MARK: Email

fn eml(text: &str) -> Vec<u8> {
    text.replace('\n', "\r\n").into_bytes()
}

#[test]
fn a_plain_message_with_encoded_headers() {
    let email = parse(&eml(
        "From: =?UTF-8?B?R2rDq24=?= <g@example.com>\n\
         To: someone@example.com\n\
         Subject: =?iso-8859-1?Q?Caf=E9_bill?= and\n =?UTF-8?Q?more_=E2=9C=93?=\n\
         Date: Thu, 23 Oct 2026 10:15:00 +0200\n\
         Content-Type: text/plain; charset=utf-8\n\
         Content-Transfer-Encoding: quoted-printable\n\
         \n\
         Hello =C3=A9t=C3=A9, this line is soft=\n wrapped.",
    ))
    .unwrap();
    assert_eq!(email.from, "Gjën <g@example.com>");
    assert_eq!(email.subject, "Café bill and more ✓");
    // 23 Oct 2026 08:15 UTC, as seconds since 2001.
    assert_eq!(email.date, Some((1_792_743_300 - 978_307_200) as f64));
    assert!(email.text.as_deref().unwrap().contains("Hello été, this line is soft wrapped."));
    assert!(email.html.is_none());
    assert!(email.page().contains("<pre"));
}

#[test]
fn multipart_picks_html_and_keeps_attachments_and_inline_pictures() {
    let b64 = |b: &[u8]| base64::engine::general_purpose::STANDARD.encode(b);
    let pdf = b64(b"%PDF-1.4 fake");
    let png = b64(&[0x89, 0x50, 0x4E, 0x47]);
    let html = b64(b"<p>Hi <img src=\"cid:logo@x\"></p>");
    let email = parse(&eml(&format!(
        "From: a@example.com\nSubject: Report\nMIME-Version: 1.0\nContent-Type: multipart/mixed; boundary=\"outer\"\n\n\
         --outer\nContent-Type: multipart/related; boundary=rel\n\n\
         --rel\nContent-Type: multipart/alternative; boundary=\"alt\"\n\n\
         --alt\nContent-Type: text/plain; charset=us-ascii\n\nPlain body\n\
         --alt\nContent-Type: text/html; charset=utf-8\nContent-Transfer-Encoding: base64\n\n{html}\n--alt--\n\
         --rel\nContent-Type: image/png\nContent-ID: <logo@x>\nContent-Transfer-Encoding: base64\n\n{png}\n--rel--\n\
         --outer\nContent-Type: application/pdf; name=\"report.pdf\"\n\
         Content-Disposition: attachment; filename*=UTF-8''r%C3%A9port%20final.pdf\nContent-Transfer-Encoding: base64\n\n{pdf}\n--outer--"
    )))
    .unwrap();
    assert_eq!(email.text.as_deref(), Some("Plain body"));
    assert!(email.html.as_deref().unwrap().contains("<p>Hi"));
    assert_eq!(email.attachments.len(), 1);
    assert_eq!(email.attachments[0].name, "réport final.pdf");
    assert_eq!(email.attachments[0].data, b"%PDF-1.4 fake");
    assert!(email.page().contains(&format!("data:image/png;base64,{png}")));
    assert!(!email.page().contains("cid:"));
    assert!(email.words().contains("Report") && email.words().contains("Plain body"));
}

#[test]
fn apple_mail_emlx() {
    let message = "From: b@example.com\nSubject: Saved by Mail\n\nBody here\n";
    let emlx = format!("{}\n{message}<?xml version=\"1.0\"?><plist><dict/></plist>", message.len());
    let email = parse(emlx.as_bytes()).unwrap();
    assert_eq!(email.subject, "Saved by Mail");
    assert_eq!(email.text.as_deref().map(str::trim), Some("Body here"));
}

#[test]
fn not_an_email() {
    assert!(parse(&[0x00, 0xFF, 0x10]).is_none());
}

#[test]
fn hostile_inputs_dont_crash() {
    // An .emlx byte count far past the end of the file (and past any integer's range when added).
    let _ = parse(b"9223372036854775807\nFrom: a@b\n\nhi");
    // Multiparts nested far deeper than any real message.
    let mut message = "Content-Type: text/plain\n\ninnermost".to_string();
    for i in 0..2000 {
        message = format!("Content-Type: multipart/mixed; boundary=b{i}\n\n--b{i}\n{message}\n--b{i}--");
    }
    let _ = parse(format!("From: a@b\n{message}").as_bytes());
    // A long run of "<" with no closing.
    let _ = email::strip_tags(&"<".repeat(100_000));
}

#[test]
fn html_words_leave_tags_styles_and_scripts_out() {
    assert_eq!(email::strip_tags("<style>p{}</style><p>Hello&nbsp;<b>there</b></p><script>x()</script>"), "Hello there");
}

// MARK: Search words

/// Concealed values and two-factor setups stay out of the index: a search box mustn't become a way to read them.
#[test]
fn a_secrets_hidden_values_never_reach_the_index() {
    let mut secret = Secret::new(Template::Login);
    secret.fields[0].value = "bank.example".into();
    secret.fields[2].value = "hunter2".into();
    let mut setup = SecretField::new("Two-factor setup", false);
    setup.value = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ".into();
    secret.fields.push(setup);
    let data = serde_json::to_vec(&secret).unwrap();
    let mut item = Item::new("Bank", "public.json", data.len() as u64, 0.0);
    item.entry = Some(Entry::Secret);
    let words = search::words(&item, &data, None).unwrap();
    assert!(words.contains("Website bank.example"));
    assert!(words.contains("Password") && !words.contains("hunter2"));
    assert!(words.contains("Two-factor setup") && !words.contains("GEZD"));
}

#[test]
fn snippets_show_the_words_around_a_hit() {
    let text = format!("{}needle in here{}", "a".repeat(40), "b".repeat(60));
    let snippet = search::snippet(&text, "NEEDLE").unwrap();
    assert!(snippet.starts_with('…') && snippet.ends_with('…') && snippet.contains("needle in here"));
    assert!(search::snippet("nothing", "needle").is_none());
}
