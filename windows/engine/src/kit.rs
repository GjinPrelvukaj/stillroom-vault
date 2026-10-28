//! The emergency kit: the port of `Crypto/EmergencyKit.swift`. A secret that opens a slot, split into printed pieces
//! so that any `threshold` of them together rebuild it and fewer show nothing at all (Shamir's secret sharing over
//! GF(256)). The secret, as 32 lowercase hex characters, seals the slot key in kit.key the way the recovery key does
//! in recovery.key.
//!
//! A piece, before it's written out: version (1), threshold, index (1...255), the share's 16 bytes, then the first two
//! bytes of SHA-256 over all of that, to catch a mistyped piece. 21 bytes, written as 34 Crockford base32 characters
//! in groups of four, prefixed "VK".

use sha2::{Digest, Sha256};
use std::fmt;

use zeroize::{Zeroize, Zeroizing};

use crate::crypto::fill_random;

pub const SECRET_LENGTH: usize = 16;
const VERSION: u8 = 1;
const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";

#[derive(Clone, PartialEq, Eq)]
pub struct Piece {
    pub threshold: u8,
    pub index: u8,
    pub share: [u8; SECRET_LENGTH],
}

/// A share is part of a secret: wiped when dropped, and never printed.
impl Drop for Piece {
    fn drop(&mut self) {
        self.share.zeroize();
    }
}

impl fmt::Debug for Piece {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Piece").field("threshold", &self.threshold).field("index", &self.index).finish_non_exhaustive()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KitProblem {
    Mistyped,
    Mixed,
    NotEnough(u8),
}

impl fmt::Display for KitProblem {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            KitProblem::Mistyped => {
                f.write_str("One of those pieces doesn't read right. Check it letter by letter against the paper.")
            }
            KitProblem::Mixed => f.write_str("Those pieces come from different kits."),
            KitProblem::NotEnough(n) => write!(f, "This kit needs {n} different pieces."),
        }
    }
}

impl std::error::Error for KitProblem {}

// MARK: Splitting and joining

/// `count` pieces, any `threshold` of which give back `secret`.
pub fn split(secret: &[u8; SECRET_LENGTH], threshold: u8, count: u8) -> Vec<Piece> {
    assert!((2..=count).contains(&threshold));
    // One random polynomial per byte, its constant term the byte itself.
    let polynomials: Vec<Zeroizing<Vec<u8>>> = secret
        .iter()
        .map(|&byte| {
            let mut coefficients = Zeroizing::new(vec![0u8; usize::from(threshold)]);
            fill_random(&mut coefficients[1..]);
            coefficients[0] = byte;
            coefficients
        })
        .collect();
    (1..=count)
        .map(|x| {
            let mut share = [0u8; SECRET_LENGTH];
            for (b, polynomial) in polynomials.iter().enumerate() {
                share[b] = evaluate(polynomial, x);
            }
            Piece { threshold, index: x, share }
        })
        .collect()
}

/// The secret from enough pieces of one kit, wiped when dropped.
pub fn join(pieces: &[Piece]) -> Result<Zeroizing<[u8; SECRET_LENGTH]>, KitProblem> {
    let first = pieces.first().ok_or(KitProblem::NotEnough(2))?;
    if pieces.iter().any(|p| p.threshold != first.threshold) {
        return Err(KitProblem::Mixed);
    }
    // The first of each index, lowest indexes first, as many as the kit needs.
    let mut distinct: Vec<&Piece> = Vec::new();
    for piece in pieces {
        if !distinct.iter().any(|p| p.index == piece.index) {
            distinct.push(piece);
        }
    }
    distinct.sort_by_key(|p| p.index);
    if distinct.len() < usize::from(first.threshold) {
        return Err(KitProblem::NotEnough(first.threshold));
    }
    let used = &distinct[..usize::from(first.threshold)];
    // Lagrange interpolation at x = 0, byte by byte.
    let mut secret = Zeroizing::new([0u8; SECRET_LENGTH]);
    for (b, byte) in secret.iter_mut().enumerate() {
        for (i, piece) in used.iter().enumerate() {
            let mut weight = 1u8;
            for (j, other) in used.iter().enumerate() {
                if j != i {
                    weight = multiply(weight, divide(other.index, other.index ^ piece.index));
                }
            }
            *byte ^= multiply(piece.share[b], weight);
        }
    }
    Ok(secret)
}

// MARK: Writing pieces down

/// A piece as it's printed: "VK-" and groups of four.
pub fn code(piece: &Piece) -> String {
    let mut bytes = Zeroizing::new(Vec::with_capacity(3 + SECRET_LENGTH + 2));
    bytes.extend_from_slice(&[VERSION, piece.threshold, piece.index]);
    bytes.extend_from_slice(&piece.share);
    let check = Sha256::digest(bytes.as_slice());
    bytes.extend_from_slice(&check[..2]);
    let (mut bits, mut value) = (0u32, 0u32);
    let mut chars = Vec::new();
    for &byte in bytes.iter() {
        value = value << 8 | u32::from(byte);
        bits += 8;
        while bits >= 5 {
            chars.push(ALPHABET[((value >> (bits - 5)) & 31) as usize]);
            bits -= 5;
        }
        value &= (1 << bits) - 1;
    }
    if bits > 0 {
        chars.push(ALPHABET[((value << (5 - bits)) & 31) as usize]);
    }
    let groups: Vec<&str> = chars.chunks(4).map(|g| std::str::from_utf8(g).unwrap()).collect();
    format!("VK-{}", groups.join("-"))
}

/// A piece as typed from paper: any case, dashes or spaces anywhere, O for 0 and I or L for 1 all fine.
pub fn piece(typed: &str) -> Result<Piece, KitProblem> {
    let upper = Zeroizing::new(typed.to_uppercase());
    let mut text = Zeroizing::new(String::with_capacity(upper.len()));
    text.extend(upper.chars().filter(|c| !c.is_whitespace() && *c != '-'));
    let text = text.strip_prefix("VK").unwrap_or(&text);
    let (mut value, mut bits) = (0u32, 0u32);
    // Room for a whole piece and more up front, so the buffer seldom grows and leaves a copy behind.
    let mut bytes = Zeroizing::new(Vec::with_capacity(64));
    for c in text.chars() {
        let c = match c {
            'O' => '0',
            'I' | 'L' => '1',
            c => c,
        };
        let digit = ALPHABET.iter().position(|&a| char::from(a) == c).ok_or(KitProblem::Mistyped)?;
        value = value << 5 | digit as u32;
        bits += 5;
        if bits >= 8 {
            bytes.push(((value >> (bits - 8)) & 0xFF) as u8);
            bits -= 8;
        }
        value &= (1 << bits) - 1;
    }
    let length = 3 + SECRET_LENGTH + 2;
    if bytes.len() != length || bytes[0] != VERSION {
        return Err(KitProblem::Mistyped);
    }
    let body = &bytes[..length - 2];
    if Sha256::digest(body)[..2] != bytes[length - 2..] || !(2..=10).contains(&bytes[1]) || bytes[2] < 1 {
        return Err(KitProblem::Mistyped);
    }
    Ok(Piece { threshold: bytes[1], index: bytes[2], share: body[3..].try_into().unwrap() })
}

/// The secret as the "password" that seals the slot key in kit.key: 32 lowercase hex characters, wiped when dropped.
pub fn password(secret: &[u8; SECRET_LENGTH]) -> Zeroizing<String> {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut text = Zeroizing::new(String::with_capacity(2 * SECRET_LENGTH));
    for b in secret {
        text.push(char::from(HEX[usize::from(b >> 4)]));
        text.push(char::from(HEX[usize::from(b & 15)]));
    }
    text
}

// MARK: GF(256), the AES field (x^8 + x^4 + x^3 + x + 1)

fn multiply(mut a: u8, mut b: u8) -> u8 {
    let mut product = 0;
    while b != 0 {
        if b & 1 != 0 {
            product ^= a;
        }
        a = (a << 1) ^ if a & 0x80 != 0 { 0x1B } else { 0 };
        b >>= 1;
    }
    product
}

/// a / b, as a times b to the 254th (b's inverse, since b^255 = 1).
fn divide(a: u8, b: u8) -> u8 {
    let mut inverse = 1;
    for _ in 0..254 {
        inverse = multiply(inverse, b);
    }
    multiply(a, inverse)
}

fn evaluate(coefficients: &[u8], x: u8) -> u8 {
    coefficients.iter().rev().fold(0, |sum, &c| multiply(sum, x) ^ c)
}
