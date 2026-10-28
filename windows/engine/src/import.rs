//! Accounts from another password manager's export file (CSV), each becoming a Login secret
//! (`Models/PasswordImport.swift`): browsers (Edge, Chrome, Firefox), Bitwarden, 1Password, Apple Passwords. Read in
//! memory only; nothing is written to disk here.

use std::fmt;

use crate::list::{Secret, SecretField, Template};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Login {
    pub title: String,
    pub url: String,
    pub username: String,
    pub password: String,
    pub notes: String,
    pub otp: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NotAnExport;

impl fmt::Display for NotAnExport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("That file isn't a password export. Export your passwords as a CSV file from your browser or password manager, then pick that file.")
    }
}

impl std::error::Error for NotAnExport {}

impl Login {
    /// The name it's listed under: its title, else the site's host, else the username.
    pub fn name(&self) -> String {
        if !self.title.is_empty() {
            return self.title.clone();
        }
        if let Some(host) = host(&self.url).filter(|h| !h.is_empty()) {
            return host.strip_prefix("www.").unwrap_or(&host).to_owned();
        }
        if self.username.is_empty() { "Login".into() } else { self.username.clone() }
    }

    /// Two exports of the same account match on site and username, however the site was written.
    pub fn key(&self) -> String {
        format!("{}|{}", site(&self.url), self.username.to_lowercase())
    }

    pub fn secret(&self) -> Secret {
        let mut secret = Secret::new(Template::Login);
        secret.fields[0].value = self.url.clone();
        secret.fields[1].value = self.username.clone();
        secret.fields[2].value = self.password.clone();
        if !self.notes.is_empty() {
            let mut notes = SecretField::new("Notes", false);
            notes.value = self.notes.clone();
            secret.fields.push(notes);
        }
        if !self.otp.is_empty() {
            let mut otp = SecretField::new("Two-factor setup", true);
            otp.value = self.otp.clone();
            secret.fields.push(otp);
        }
        secret
    }
}

/// The column names each app uses, lowercased; the first one present wins.
const TITLES: &[&str] = &["title", "name"];
const URLS: &[&str] = &["url", "login_uri", "website", "web site", "login url"];
const USERNAMES: &[&str] = &["username", "login_username", "user name", "login", "email"];
const PASSWORDS: &[&str] = &["password", "login_password"];
const NOTES: &[&str] = &["notes", "note", "extra", "comments"];
const OTPS: &[&str] = &["otpauth", "login_totp", "totp", "otp", "one-time password"];

/// Every account in an export, in order. Rows that aren't logins (Bitwarden's cards and notes) and rows with neither a
/// password nor a username are left out.
pub fn logins(data: &[u8]) -> Result<Vec<Login>, NotAnExport> {
    let text = String::from_utf8(data.to_vec()).unwrap_or_else(|_| data.iter().map(|&b| b as char).collect());
    let mut rows = parse(&text);
    if rows.is_empty() {
        return Err(NotAnExport);
    }
    let header: Vec<String> = rows.remove(0).iter().map(|h| h.trim().to_lowercase()).collect();
    let column = |names: &[&str]| names.iter().find_map(|name| header.iter().position(|h| h == name));
    let password = column(PASSWORDS).ok_or(NotAnExport)?;
    let (title, url, username, notes, otp) = (column(TITLES), column(URLS), column(USERNAMES), column(NOTES), column(OTPS));
    let kind = header.iter().position(|h| h == "type");

    Ok(rows
        .iter()
        .filter_map(|row| {
            let value = |i: Option<usize>| i.and_then(|i| row.get(i)).map(|v| v.trim().to_owned()).unwrap_or_default();
            if kind.is_some() && !value(kind).is_empty() && value(kind).to_lowercase() != "login" {
                return None;
            }
            let login = Login {
                title: value(title),
                url: value(url),
                username: value(username),
                password: value(Some(password)),
                notes: value(notes),
                otp: value(otp),
            };
            (!(login.password.is_empty() && login.username.is_empty())).then_some(login)
        })
        .collect())
}

/// The site's host without "www.", lowercased, or the address as written when it has none.
pub fn site(url: &str) -> String {
    let host = host(url).or_else(|| host(&format!("https://{url}"))).unwrap_or_else(|| url.to_owned());
    host.strip_prefix("www.").unwrap_or(&host).to_lowercase()
}

/// The host of a "scheme://host/…" address, as `URL(string:)?.host()` gives it; None without a scheme.
fn host(url: &str) -> Option<String> {
    let (scheme, rest) = url.split_once("://")?;
    if scheme.is_empty() || !scheme.chars().all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c)) || url.contains(' ') {
        return None;
    }
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = authority.rsplit_once('@').map_or(authority, |(_, h)| h);
    let host = if host.starts_with('[') { host.split(']').next().map(|h| &h[1..]).unwrap_or("") } else { host.split(':').next().unwrap_or("") };
    (!host.is_empty()).then(|| host.to_owned())
}

/// CSV as RFC 4180 writes it: commas between fields, quotes round any field holding commas, quotes or line breaks, and
/// a quote inside one doubled.
pub fn parse(text: &str) -> Vec<Vec<String>> {
    // A byte-order mark at the start (Excel and some exports write one) isn't part of the first column's name.
    let text = text.strip_prefix('\u{FEFF}').unwrap_or(text);
    let mut rows = Vec::new();
    let mut row: Vec<String> = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if quoted {
            if c == '"' {
                if chars.peek() == Some(&'"') {
                    field.push('"');
                    chars.next();
                } else {
                    quoted = false;
                }
            } else {
                field.push(c);
            }
            continue;
        }
        match c {
            '"' => quoted = true,
            ',' => row.push(std::mem::take(&mut field)),
            '\r' => {}
            '\n' => {
                row.push(std::mem::take(&mut field));
                if !(row.len() == 1 && row[0].is_empty()) {
                    rows.push(std::mem::take(&mut row));
                }
                row.clear();
            }
            c => field.push(c),
        }
    }
    if !field.is_empty() || !row.is_empty() {
        row.push(field);
        rows.push(row);
    }
    rows
}
