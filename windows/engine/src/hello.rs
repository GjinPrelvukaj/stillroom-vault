//! Windows Hello's way in to one slot (the Windows counterpart of `Crypto/TouchIDKey.swift`): a face, a finger or the
//! Windows Hello PIN opens the slot that last turned it on.
//!
//! Windows Hello holds an RSA key in the TPM and signs with it once the person is checked. The app (which talks to
//! Windows Hello) asks it to sign a fixed 32-byte challenge; RSA PKCS#1 v1.5 signatures are deterministic, so the same
//! credential always gives the same signature, and HKDF-SHA256 of it (info "Vault Windows Hello") is the key that seals
//! the slot key. The engine never sees the Hello key, only the signature, which the app wipes.
//!
//! ```text
//! hello.key   {"challenge": base64 (32), "publicKey": base64 (the credential's), "vaultKey": base64 (sealed slot key)}
//! list        "hello": base64 SHA-256 of that public key, or 32 zero bytes: Hello is this slot's when they match
//! ```
//!
//! Off by default (like Touch ID); turning it on should say plainly that the Windows Hello PIN opens the vault too.

use base64::Engine as _;
use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

use crate::crypto::{fill_random, Key};
use crate::VaultError;

const LABEL: &[u8] = b"Vault Windows Hello";

#[derive(Serialize, Deserialize)]
pub struct HelloKey {
    pub challenge: String,
    #[serde(rename = "publicKey")]
    pub public_key: String,
    #[serde(rename = "vaultKey")]
    pub vault_key: String,
}

/// 32 random bytes for Windows Hello to sign when it's turned on.
pub fn new_challenge() -> [u8; 32] {
    let mut challenge = [0u8; 32];
    fill_random(&mut challenge);
    challenge
}

/// The key that seals the slot key, from Windows Hello's signature of the challenge.
pub fn wrapping_key(signature: &[u8]) -> Result<Key, VaultError> {
    if signature.is_empty() {
        return Err(VaultError::HelloChanged);
    }
    let mut key = Zeroizing::new([0u8; 32]);
    Hkdf::<Sha256>::new(None, signature).expand(LABEL, key.as_mut()).expect("32 bytes is a valid length");
    Key::from_slice(key.as_ref())
}

/// What the list keeps of a credential's public key: its SHA-256, base64.
pub fn fingerprint(public_key: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(Sha256::digest(public_key))
}

/// 32 zero bytes, base64: no Windows Hello.
pub fn none() -> String {
    base64::engine::general_purpose::STANDARD.encode([0u8; 32])
}

pub fn decode(text: &str) -> Result<Vec<u8>, VaultError> {
    base64::engine::general_purpose::STANDARD.decode(text).map_err(|_| VaultError::Damaged)
}

pub fn encode(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}
