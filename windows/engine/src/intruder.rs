//! Who tried to get in (`Security/IntruderLog.swift`): each wrong password or recovery key at the lock screen. A wrong
//! try happens while locked, when nothing says which vault it was aimed at, so it belongs to both: each entry is sealed
//! with HPKE (X25519, HKDF-SHA256, ChaCha20-Poly1305, info "Vault intruder log") to both slots' public keys, which sit
//! in the open. Each slot's private half rides in its own sealed list, so either slot, unlocked, reads the same log.
//! What was typed is never kept.
//!
//! ```text
//! intruder.pub     both public keys, raw: a's (32 bytes), then b's
//! intruder/        one file per entry: for a, then b, u32 length | encapsulated key (32) | sealed JSON
//! ```

use std::fs;
use std::path::PathBuf;

use base64::Engine as _;
use hpke::aead::ChaCha20Poly1305;
use hpke::kdf::HkdfSha256;
use hpke::kem::X25519HkdfSha256;
use hpke::{Deserializable, Kem as _, OpModeR, OpModeS, Serializable};
use rand_core::OsRng;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::fsx;
use crate::vault::{Slot, Store};

type Kem = X25519HkdfSha256;
const INFO: &[u8] = b"Vault intruder log";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Kind {
    WrongPassword,
    WrongRecoveryKey,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub id: Uuid,
    /// Seconds since 2001, as every date in a vault.
    pub date: f64,
    pub kind: Kind,
    /// A JPEG of whoever was at the computer, when the camera allowed one.
    pub photo: Option<Vec<u8>>,
}

/// An entry as JSON, as the Mac writes it: the photo base64, left out when there's none.
#[derive(Serialize, Deserialize)]
struct Written {
    id: Uuid,
    date: f64,
    kind: Kind,
    #[serde(skip_serializing_if = "Option::is_none")]
    photo: Option<String>,
}

fn offset(slot: Slot) -> usize {
    if slot == Slot::A { 0 } else { 32 }
}

pub fn public_key_path(store: &Store) -> PathBuf {
    store.root().join("intruder.pub")
}

pub fn folder(store: &Store) -> PathBuf {
    store.root().join("intruder")
}

fn public_keys(store: &Store) -> Option<Vec<u8>> {
    fs::read(public_key_path(store)).ok().filter(|both| both.len() == 64)
}

/// Puts a slot's public key in its half of intruder.pub, the other half kept.
pub fn set_public_key(store: &Store, raw: &[u8; 32], slot: Slot) -> std::io::Result<()> {
    let mut both = public_keys(store).unwrap_or_else(|| vec![0; 64]);
    both[offset(slot)..offset(slot) + 32].copy_from_slice(raw);
    store.write_key(&public_key_path(store), &both)
}

/// A new key pair: the private half base64 (for the slot's list) and the public half.
pub fn new_key() -> (Zeroizing<String>, [u8; 32]) {
    let (private, public) = Kem::gen_keypair(&mut OsRng);
    let raw = Zeroizing::new(private.to_bytes().to_vec());
    (Zeroizing::new(base64::engine::general_purpose::STANDARD.encode(&*raw)), public.to_bytes().into())
}

fn private_key(stored: &str) -> Option<<Kem as hpke::Kem>::PrivateKey> {
    let raw = Zeroizing::new(base64::engine::general_purpose::STANDARD.decode(stored).ok()?);
    <Kem as hpke::Kem>::PrivateKey::from_bytes(&raw).ok()
}

/// The slot's private key from its list, checked against its half of intruder.pub: someone able to write the folder
/// could otherwise swap in a key of their own and see the photos. On a mismatch (or none) a new pair is made and
/// returned, to be kept in the list; `swapped` is then true.
pub fn check(store: &Store, stored: &str, slot: Slot) -> std::io::Result<(Zeroizing<String>, bool)> {
    if let (Some(key), Some(both)) = (private_key(stored), public_keys(store)) {
        if Kem::sk_to_pk(&key).to_bytes().as_slice() == &both[offset(slot)..offset(slot) + 32] {
            return Ok((Zeroizing::new(stored.to_owned()), false));
        }
    }
    let (private, public) = new_key();
    set_public_key(store, &public, slot)?;
    Ok((private, true))
}

/// Records one event using only the public keys (works while locked). Does nothing if there are none yet.
pub fn record(store: &Store, kind: Kind, photo: Option<&[u8]>, now: f64) -> std::io::Result<()> {
    let Some(both) = public_keys(store) else { return Ok(()) };
    let entry = Written {
        id: Uuid::new_v4(),
        date: now,
        kind,
        photo: photo.map(|p| base64::engine::general_purpose::STANDARD.encode(p)),
    };
    let json = serde_json::to_vec(&entry).map_err(std::io::Error::other)?;
    let mut file = Vec::new();
    for slot in Slot::ALL {
        let recipient = <Kem as hpke::Kem>::PublicKey::from_bytes(&both[offset(slot)..offset(slot) + 32])
            .map_err(|_| std::io::Error::other("a public key that isn't one"))?;
        let (encapsulated, mut sender) =
            hpke::setup_sender::<ChaCha20Poly1305, HkdfSha256, Kem, _>(&OpModeS::Base, &recipient, INFO, &mut OsRng)
                .map_err(|_| std::io::Error::other("couldn't seal"))?;
        let sealed = sender.seal(&json, b"").map_err(|_| std::io::Error::other("couldn't seal"))?;
        let part = [encapsulated.to_bytes().as_slice(), &sealed].concat();
        file.extend_from_slice(&(part.len() as u32).to_be_bytes());
        file.extend_from_slice(&part);
    }
    fsx::write_atomic(&entry_path(store, &entry.id), &file)
}

/// The slot's sealing inside an entry file.
fn part(data: &[u8], slot: Slot) -> Option<&[u8]> {
    let mut at = 0;
    for each in Slot::ALL {
        let length = u32::from_be_bytes(data.get(at..at + 4)?.try_into().ok()?) as usize;
        at += 4;
        let piece = data.get(at..at + length)?;
        if each == slot {
            return Some(piece);
        }
        at += length;
    }
    None
}

/// Every entry this slot can read, newest first. A file that won't open (cut short, put there by someone else, or
/// sealed to a slot since replaced) is skipped.
pub fn entries(store: &Store, stored: &str, slot: Slot) -> Vec<Entry> {
    let Some(key) = private_key(stored) else { return Vec::new() };
    let mut found: Vec<Entry> = files(store)
        .iter()
        .filter_map(|path| {
            let data = fs::read(path).ok()?;
            let part = part(&data, slot).filter(|p| p.len() > 32)?;
            let encapsulated = <Kem as hpke::Kem>::EncappedKey::from_bytes(&part[..32]).ok()?;
            let mut recipient =
                hpke::setup_receiver::<ChaCha20Poly1305, HkdfSha256, Kem>(&OpModeR::Base, &key, &encapsulated, INFO).ok()?;
            let json = recipient.open(&part[32..], b"").ok()?;
            let written: Written = serde_json::from_slice(&json).ok()?;
            let photo = match written.photo {
                Some(text) => Some(base64::engine::general_purpose::STANDARD.decode(text).ok()?),
                None => None,
            };
            Some(Entry { id: written.id, date: written.date, kind: written.kind, photo })
        })
        .collect();
    found.sort_by(|a, b| b.date.total_cmp(&a.date));
    found
}

/// Gone for both slots.
pub fn delete(store: &Store, id: &Uuid) -> std::io::Result<()> {
    fs::remove_file(entry_path(store, id))
}

/// Every entry gone; the keys stay, so logging goes on.
pub fn clear(store: &Store) -> std::io::Result<()> {
    for path in files(store) {
        fs::remove_file(path)?;
    }
    Ok(())
}

fn entry_path(store: &Store, id: &Uuid) -> PathBuf {
    let name = id.hyphenated().encode_upper(&mut Uuid::encode_buffer()).to_owned();
    folder(store).join(name + ".intruder")
}

fn files(store: &Store) -> Vec<PathBuf> {
    let Ok(read) = fs::read_dir(folder(store)) else { return Vec::new() };
    read.filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e == "intruder"))
        .collect()
}
