//! Two-factor codes (RFC 6238, `Crypto/OneTimeCode.swift`): the secret a website shows as a QR code or a "setup key",
//! turned into the rolling code it asks for. Takes an `otpauth://totp/…` link or a bare base32 key.

use hmac::{Hmac, Mac};
use sha1::Sha1;
use sha2::{Sha256, Sha512};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Algorithm {
    Sha1,
    Sha256,
    Sha512,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OneTimeCode {
    pub key: Vec<u8>,
    pub digits: u32,
    pub period: u64,
    pub algorithm: Algorithm,
}

impl OneTimeCode {
    pub fn new(key: Vec<u8>, digits: u32, period: u64, algorithm: Algorithm) -> OneTimeCode {
        OneTimeCode { key, digits, period, algorithm }
    }

    /// None when the text is neither a usable link nor a base32 key. Counter-based (HOTP) links aren't taken.
    pub fn parse(text: &str) -> Option<OneTimeCode> {
        let text = text.trim();
        if !text.to_lowercase().starts_with("otpauth://") {
            return Some(OneTimeCode::new(base32(text)?, 6, 30, Algorithm::Sha1));
        }
        let rest = &text["otpauth://".len()..];
        let (host, after) = rest.split_once('/').unwrap_or((rest, ""));
        if !host.eq_ignore_ascii_case("totp") {
            return None;
        }
        let query = after.split_once('?').map(|(_, q)| q).unwrap_or("");
        let item = |name: &str| {
            query.split('&').filter_map(|pair| pair.split_once('=')).find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| percent_decode(v))
        };
        let mut code = OneTimeCode::new(base32(&item("secret")?)?, 6, 30, Algorithm::Sha1);
        if let Some(digits) = item("digits") {
            code.digits = digits.parse().ok().filter(|n| (6..=8).contains(n))?;
        }
        if let Some(period) = item("period") {
            code.period = period.parse().ok().filter(|n| (1..=300).contains(n))?;
        }
        if let Some(name) = item("algorithm") {
            code.algorithm = match name.to_uppercase().as_str() {
                "SHA1" => Algorithm::Sha1,
                "SHA256" => Algorithm::Sha256,
                "SHA512" => Algorithm::Sha512,
                _ => return None,
            };
        }
        Some(code)
    }

    /// The code for a moment (seconds since 1970), as digits, leading zeros kept.
    pub fn code(&self, unix_seconds: f64) -> String {
        let counter = (unix_seconds.max(0.0) / self.period as f64) as u64;
        let message = counter.to_be_bytes();
        let mac: Vec<u8> = match self.algorithm {
            Algorithm::Sha1 => mac::<Hmac<Sha1>>(&self.key, &message),
            Algorithm::Sha256 => mac::<Hmac<Sha256>>(&self.key, &message),
            Algorithm::Sha512 => mac::<Hmac<Sha512>>(&self.key, &message),
        };
        let at = usize::from(mac[mac.len() - 1] & 0x0f);
        let number = u32::from(mac[at] & 0x7f) << 24 | u32::from(mac[at + 1]) << 16 | u32::from(mac[at + 2]) << 8 | u32::from(mac[at + 3]);
        format!("{:0width$}", number % 10u32.pow(self.digits), width = self.digits as usize)
    }

    /// Seconds until the code changes.
    pub fn seconds_left(&self, unix_seconds: f64) -> u64 {
        self.period - (unix_seconds.max(0.0) as u64) % self.period
    }
}

fn mac<M: Mac + hmac::digest::KeyInit>(key: &[u8], message: &[u8]) -> Vec<u8> {
    let mut mac = <M as hmac::digest::KeyInit>::new_from_slice(key).expect("any key length works");
    mac.update(message);
    mac.finalize().into_bytes().to_vec()
}

/// RFC 4648 base32, forgiving how people paste it: any case, spaces, dashes, missing padding. Under 80 bits isn't a
/// real setup key (and rules out short words typed into the field).
pub fn base32(text: &str) -> Option<Vec<u8>> {
    const ALPHABET: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let clean: Vec<char> = text.to_uppercase().chars().filter(|c| !" -\t\n=".contains(*c)).collect();
    if clean.len() < 16 {
        return None;
    }
    let (mut bytes, mut buffer, mut bits) = (Vec::new(), 0u32, 0u32);
    for c in clean {
        let value = ALPHABET.iter().position(|&a| char::from(a) == c)? as u32;
        buffer = (buffer << 5 | value) & 0xffff;
        bits += 5;
        if bits >= 8 {
            bytes.push((buffer >> (bits - 8) & 0xff) as u8);
            bits -= 8;
        }
    }
    Some(bytes)
}

/// A query value with its %XX escapes turned back into bytes, as `URLComponents.queryItems` gives them.
fn percent_decode(text: &str) -> String {
    fn hex(b: u8) -> Option<u8> {
        (b as char).to_digit(16).map(|d| d as u8)
    }
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(high), Some(low)) = (hex(bytes[i + 1]), hex(bytes[i + 2])) {
                out.push(high << 4 | low);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Whether a secret's field holds a two-factor setup: a link always counts; a bare key only under a label that says so.
pub fn in_field(label: &str, value: &str) -> Option<OneTimeCode> {
    let value = value.trim();
    if value.to_lowercase().starts_with("otpauth://") {
        return OneTimeCode::parse(value);
    }
    let label = label.to_lowercase();
    if !["two-factor", "2fa", "totp", "one-time", "authenticator"].iter().any(|w| label.contains(w)) {
        return None;
    }
    OneTimeCode::parse(value)
}
