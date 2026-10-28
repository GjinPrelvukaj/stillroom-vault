//! Sealing, password keys, padding and recovery codes: the port of `Crypto/CryptoEngine.swift`. Every byte this writes
//! must match what the Mac app writes (docs/FORMAT.md), so vaults open on either.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use zeroize::Zeroizing;

use crate::argon2::argon2id;
use crate::VaultError;

/// How hard a password is stretched with Argon2id: memory, passes and lanes. Written into each sealed key, so it can
/// rise later without existing keys failing to open. Tests pass a lower one so they stay quick.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PasswordCost {
    pub memory_kib: u32,
    pub passes: u32,
    pub lanes: u32,
}

impl PasswordCost {
    /// Today's cost, the same as the Mac app's `PasswordCost.current`.
    pub const CURRENT: PasswordCost = PasswordCost { memory_kib: 512 * 1024, passes: 3, lanes: 4 };
}

/// A 32-byte symmetric key (a slot key, cover key, item key or one stretched from a password), wiped when dropped.
/// The bytes live in a slot of their own in locked memory (`secure.rs`), kept out of the page file, so moving a `Key`
/// (into a map that then grows, say) moves only a pointer and never leaves an unwiped copy of the key behind.
pub struct Key(crate::secure::Slot);

impl Key {
    pub fn random() -> Key {
        let mut slot = crate::secure::Slot::new();
        fill_random(slot.bytes_mut());
        Key(slot)
    }

    pub fn from_slice(bytes: &[u8]) -> Result<Key, VaultError> {
        if bytes.len() != 32 {
            return Err(VaultError::Damaged);
        }
        let mut slot = crate::secure::Slot::new();
        slot.bytes_mut().copy_from_slice(bytes);
        Ok(Key(slot))
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        self.0.bytes()
    }
}

/// Never prints the key, so one can't reach a log or a panic message.
impl std::fmt::Debug for Key {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Key(…)")
    }
}

/// Fills `buffer` from the operating system's random source (BCryptGenRandom on Windows).
pub fn fill_random(buffer: &mut [u8]) {
    getrandom::getrandom(buffer).expect("the system random source failed");
}

/// The start of every key sealed with a password (Argon2id, mark version 1).
const ARGON_MARK: [u8; 4] = [b'V', b'A', b'2', 1];

const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;

/// AES-256-GCM: nonce, ciphertext and tag in one piece, as CryptoKit's `SealedBox.combined`. Any change to the piece
/// makes `unseal` fail. `binding` is authenticated data naming what the piece is: it isn't stored, so the piece only
/// opens where it's expected. No binding seals with empty authenticated data, as CryptoKit does.
pub fn seal(data: &[u8], key: &Key, binding: Option<&[u8]>) -> Result<Vec<u8>, VaultError> {
    let cipher = Aes256Gcm::new_from_slice(key.as_bytes()).map_err(|_| VaultError::Damaged)?;
    let mut nonce = [0u8; NONCE_LEN];
    fill_random(&mut nonce);
    let sealed = cipher
        .encrypt(Nonce::from_slice(&nonce), Payload { msg: data, aad: binding.unwrap_or(&[]) })
        .map_err(|_| VaultError::Damaged)?;
    let mut combined = Vec::with_capacity(NONCE_LEN + sealed.len());
    combined.extend_from_slice(&nonce);
    combined.extend_from_slice(&sealed);
    Ok(combined)
}

/// Opens a piece from `seal`. Fails with `Damaged` when the key, the binding or any byte of the piece is wrong.
pub fn unseal(data: &[u8], key: &Key, binding: Option<&[u8]>) -> Result<Zeroizing<Vec<u8>>, VaultError> {
    if data.len() < NONCE_LEN + TAG_LEN {
        return Err(VaultError::Damaged);
    }
    let cipher = Aes256Gcm::new_from_slice(key.as_bytes()).map_err(|_| VaultError::Damaged)?;
    let (nonce, body) = data.split_at(NONCE_LEN);
    cipher
        .decrypt(Nonce::from_slice(nonce), Payload { msg: body, aad: binding.unwrap_or(&[]) })
        .map(Zeroizing::new)
        .map_err(|_| VaultError::Damaged)
}

/// What each kind of seal is bound to. These labels (and the HKDF ones for Lock to this Mac, Touch ID and the
/// intruder log) are part of the format and keep the app's first name, "Vault": changing one makes every existing
/// vault unreadable.
pub mod bound {
    pub const LIST: &[u8] = b"Vault list 3";
    pub const SEARCH: &[u8] = b"Vault search 3";

    /// A slot's list or index inside its cover (format 4): bound to what it is and whose, so neither swaps.
    pub fn cover(kind: &str, slot: &str) -> Vec<u8> {
        [b"Vault cover 4".as_slice(), kind.as_bytes(), slot.as_bytes()].concat()
    }

    /// The cover key sealed with a slot key, in that slot's cover.key.
    pub fn cover_key(slot: &str) -> Vec<u8> {
        [b"Vault cover key 4".as_slice(), slot.as_bytes()].concat()
    }

    /// An item, bound to the UUID it was sealed as (its 16 raw bytes).
    pub fn item(sealed_as: &[u8; 16]) -> Vec<u8> {
        [b"Vault item 3".as_slice(), sealed_as.as_slice()].concat()
    }
}

/// A key made from a password and a salt with Argon2id at the given cost.
pub fn stretch_argon(password: &str, salt: &[u8], cost: PasswordCost) -> Result<Key, VaultError> {
    // Not logged: how many times this runs per unlock would say whether a decoy is set.
    let stretched = argon2id(password.as_bytes(), salt, cost.memory_kib, cost.passes, cost.lanes, 32, &[], &[])?;
    Key::from_slice(&stretched)
}

/// The vault key sealed with a password: the mark, the Argon2id cost and the salt, then the sealed key. The salt and
/// cost are the ones the password was stretched with, so the same password stretches to the same key again.
pub fn seal_with_password(vault_key: &Key, password: &str, cost: PasswordCost) -> Result<Vec<u8>, VaultError> {
    let mut salt = [0u8; 16];
    fill_random(&mut salt);
    let mut sealed = ARGON_MARK.to_vec();
    for value in [cost.memory_kib, cost.passes, cost.lanes] {
        sealed.extend_from_slice(&value.to_be_bytes());
    }
    sealed.extend_from_slice(&salt);
    let sealing = stretch_argon(password, &salt, cost)?;
    sealed.extend(seal(vault_key.as_bytes(), &sealing, None)?);
    Ok(sealed)
}

pub fn open_with_password(sealed: &[u8], password: &str) -> Result<Key, VaultError> {
    if !uses_argon(sealed) || sealed.len() <= 32 {
        return Err(VaultError::Damaged);
    }
    let number = |i: usize| u32::from_be_bytes(sealed[i..i + 4].try_into().unwrap());
    let cost = PasswordCost { memory_kib: number(4), passes: number(8), lanes: number(12) };
    // A cost no real key would carry (a damaged or doctored file) mustn't hang or crash the app. Up to 2 GiB and
    // 10 passes leaves room to raise today's cost.
    let sane = (1..=16).contains(&cost.lanes)
        && (1..=10).contains(&cost.passes)
        && cost.memory_kib >= 8 * cost.lanes
        && cost.memory_kib <= 2 * 1024 * 1024;
    if !sane {
        return Err(VaultError::Damaged);
    }
    let key = stretch_argon(password, &sealed[16..32], cost)?;
    // A wrong password stretches to a key the seal rejects: that is the only way to tell.
    let opened = unseal(&sealed[32..], &key, None).map_err(|_| VaultError::WrongPassword)?;
    Key::from_slice(&opened)
}

/// Whether a file starts like a key sealed with a password.
pub fn uses_argon(sealed: &[u8]) -> bool {
    sealed.starts_with(&ARGON_MARK)
}

/// Padmé: the length a file is padded to before sealing, so its sealed size tells at most about 12% of its real one.
/// Lengths round up to fewer significant bits the larger they are. Worked in u64 on every platform, so a size from
/// the list is never cut down on a 32-bit build; None for a length too large to pad (no real file is).
pub fn padded_length(n: u64) -> Option<u64> {
    if n <= 1 {
        return Some(n);
    }
    let e = u64::BITS - 1 - n.leading_zeros();
    let s = u32::BITS - e.leading_zeros();
    let mask = 1u64.checked_shl(e - s)?.checked_sub(1)?;
    Some(n.checked_add(mask)? & !mask)
}

/// `padded_length` for bytes about to be sealed: the padded length as a buffer size, or `Damaged` for one too large to
/// pad or to hold in memory.
pub fn padded_size(n: usize) -> Result<usize, VaultError> {
    padded_length(n as u64).and_then(|p| usize::try_from(p).ok()).ok_or(VaultError::Damaged)
}

/// A recovery key: 25 characters from an alphabet with no look-alikes (no 0/O, 1/I/L), in groups of five. About
/// 124 random bits.
pub fn make_recovery_code() -> String {
    const ALPHABET: &[u8; 31] = b"ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    let mut chars = Vec::with_capacity(25);
    while chars.len() < 25 {
        let mut byte = [0u8; 1];
        fill_random(&mut byte);
        // Uniform over the alphabet: bytes past the largest multiple of 31 are thrown away.
        if byte[0] < 248 {
            chars.push(ALPHABET[usize::from(byte[0] % 31)] as char);
        }
    }
    chars.chunks(5).map(|group| group.iter().collect::<String>()).collect::<Vec<_>>().join("-")
}

/// A typed recovery key as it is stretched: capitals, no dashes or spaces, so however it's written it matches.
/// The upper-cased copy made on the way is wiped too.
pub fn normalized_recovery_code(typed: &str) -> Zeroizing<String> {
    let upper = Zeroizing::new(typed.to_uppercase());
    let mut normalized = Zeroizing::new(String::with_capacity(upper.len()));
    normalized.extend(upper.chars().filter(|c| c.is_alphanumeric()));
    normalized
}
