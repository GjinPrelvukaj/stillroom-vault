//! A bought licence (`Security/License.swift`): one pasteable line, `SR1.<payload>.<signature>`, both parts base64url
//! without padding. The payload is compact JSON and the signature is Ed25519 over the bytes of `SR1.<payload>`, made by
//! the website's signer (website/server/licence.ts). Checked here offline against the public key built in: no network,
//! no clock, no expiry. One key works on the Mac and on Windows alike (windows/PORT.md, "Decided").
//!
//! It lives in one file beside the store, in neither slot (`Store::licence_file`), so it lifts the free tier in either
//! vault alike and says nothing about which is which (docs/SECURITY.md rule 2), and isn't in backups.

use std::fmt;
use std::fs;
use std::path::Path;

use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use ed25519_dalek::{Signature, VerifyingKey};
use serde::{Deserialize, Serialize};

/// Without a licence a vault holds at most this many items (files, notes and secrets; not folders or versions).
pub const FREE_ITEMS: usize = 25;

/// Stillroom's public signing key (32 bytes, base64), the Mac's `License.publicKey`. Its private half is only in the
/// website's signer and Gjin's own safekeeping.
pub const PUBLIC_KEY: &str = "rVwu2FUZZBSLtMc+bIT0YN6HRTBrkqlyRfEQu/HKvsE=";

/// Licence ids turned off because the key was posted publicly, as the Mac's `License.blocked`: nothing offline can
/// revoke a key, so each release refuses them. Keep it the same as the Mac's.
pub const BLOCKED: &[&str] = &[];

/// The built-in signer.
pub fn built_in() -> Option<VerifyingKey> {
    let bytes: [u8; 32] = STANDARD.decode(PUBLIC_KEY).ok()?.try_into().ok()?;
    VerifyingKey::from_bytes(&bytes).ok()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Edition {
    Personal,
    Family,
    Teams,
}

impl Edition {
    /// As Settings shows it.
    pub fn name(self) -> &'static str {
        match self {
            Edition::Personal => "Stillroom Vault",
            Edition::Family => "Family",
            Edition::Teams => "Teams",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Licence {
    pub id: String,
    pub edition: Edition,
    pub seats: u32,
    pub name: String,
    pub email: String,
    /// The day it was issued, as written ("2026-10-28"); shown, never compared with the clock.
    pub issued: String,
}

/// Why a key doesn't check out, in the Mac's words.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Problem {
    Malformed,
    NotSigned,
    NewerVersion,
    Blocked,
}

impl fmt::Display for Problem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Problem::Malformed => "This key doesn't check out: part of it is missing or mistyped. Paste the whole key from the email.",
            Problem::NotSigned => "This key doesn't check out: it wasn't signed by Stillroom.",
            Problem::NewerVersion => "This key doesn't check out: it's for a newer Stillroom. Update Stillroom, then add it again.",
            Problem::Blocked => {
                "This key was turned off because it was posted publicly. If it's yours, write to support@stillroomvault.com for a new one."
            }
        })
    }
}

impl std::error::Error for Problem {}

#[derive(Deserialize)]
struct Payload {
    v: i64,
    id: String,
    edition: Edition,
    seats: i64,
    name: String,
    email: String,
    issued: String,
}

/// The key as pasted, with any spaces or line breaks a mail app put in taken out.
pub fn tidy(typed: &str) -> String {
    typed.chars().filter(|c| !c.is_whitespace()).collect()
}

/// Checks a pasted key: its shape, then the signature, then what it says. Pure: reads nothing but `typed`.
pub fn check(typed: &str, signer: Option<&VerifyingKey>, blocked: &[&str]) -> Result<Licence, Problem> {
    let key = tidy(typed);
    if key.len() > 4096 {
        return Err(Problem::Malformed);
    }
    let parts: Vec<&str> = key.split('.').collect();
    let [version, payload, signature] = parts[..] else { return Err(Problem::Malformed) };
    if version != "SR1" {
        // "SR2" and on: a later format, which this version can't read.
        let later = version.strip_prefix("SR").and_then(|n| n.parse::<u32>().ok()).is_some_and(|n| n > 1);
        return Err(if later { Problem::NewerVersion } else { Problem::Malformed });
    }
    let (Some(json), Some(signature)) = (base64url(payload), base64url(signature)) else { return Err(Problem::Malformed) };
    let Ok(signature) = <[u8; 64]>::try_from(signature) else { return Err(Problem::Malformed) };
    let signed = format!("SR1.{payload}");
    let good = signer.is_some_and(|s| s.verify_strict(signed.as_bytes(), &Signature::from_bytes(&signature)).is_ok());
    if !good {
        return Err(Problem::NotSigned);
    }
    // Signed by Stillroom, so what follows was written by the signer; still checked, never trusted to be sane.
    let p: Payload = serde_json::from_slice(&json).map_err(|_| Problem::Malformed)?;
    if p.v != 1 {
        return Err(if p.v > 1 { Problem::NewerVersion } else { Problem::Malformed });
    }
    if p.seats < 1 || p.seats > u32::MAX as i64 || p.id.is_empty() {
        return Err(Problem::Malformed);
    }
    if blocked.contains(&p.id.as_str()) {
        return Err(Problem::Blocked);
    }
    Ok(Licence { id: p.id, edition: p.edition, seats: p.seats as u32, name: p.name, email: p.email, issued: p.issued })
}

/// Strict base64url without padding: anything else is a mistyped key.
fn base64url(text: &str) -> Option<Vec<u8>> {
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_') {
        return None;
    }
    URL_SAFE_NO_PAD.decode(text).ok()
}

// MARK: Kept beside the store

/// The saved licence at `file`, if there is one and it still checks out.
pub fn load(file: &Path, signer: Option<&VerifyingKey>) -> Option<Licence> {
    check(&read(file)?, signer, BLOCKED).ok()
}

/// Why a saved key no longer checks out (blocked by a later release, say), or None when there's none or it's fine.
pub fn saved_problem(file: &Path, signer: Option<&VerifyingKey>) -> Option<Problem> {
    check(&read(file)?, signer, BLOCKED).err()
}

fn read(file: &Path) -> Option<String> {
    let data = fs::read(file).ok().filter(|d| d.len() <= 8192)?;
    Some(String::from_utf8_lossy(&data).into_owned())
}

/// Checks `typed` and, if it's good, keeps it at `file`. A signed key isn't secret, so it's a plain file.
pub fn save(file: &Path, typed: &str, signer: Option<&VerifyingKey>) -> Result<Licence, crate::Error> {
    let licence = check(typed, signer, BLOCKED)?;
    if let Some(parent) = file.parent() {
        fs::create_dir_all(parent)?;
    }
    crate::fsx::write_atomic(file, tidy(typed).as_bytes())?;
    Ok(licence)
}

pub fn remove(file: &Path) -> std::io::Result<()> {
    match fs::remove_file(file) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        other => other,
    }
}

/// Said when adding stops at the free tier's limit, the same words in either vault (the Mac's `fullMessage`).
pub fn full_message(left: usize) -> String {
    let what = if left == 1 { "1 item didn't go in".to_owned() } else { format!("{left} items didn't go in") };
    format!(
        "{what}: without a licence a vault holds {FREE_ITEMS} items. Everything already in it keeps working. Add a licence in Settings › Licence to lift the limit."
    )
}
