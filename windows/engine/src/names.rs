//! How a slot names its item files (`Names` in Storage/VaultStore.swift): 8 random bytes, then the first 8 bytes of
//! HMAC-SHA256 over them, keyed with HKDF-SHA256 of the cover key (no salt, info "Vault names 4" and the slot's letter).
//! A slot, or anyone holding the cover key, can tell its own files from the other's in the shared Files/; a copy of
//! the folder can't.

use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::crypto::{fill_random, Key};
use crate::vault::Slot;

pub struct Names {
    keys: [Zeroizing<[u8; 32]>; 2],
}

/// One sealing of an item: its own fresh id (which names its blob and is what its seals are bound to) and its own key.
pub struct ItemSeal {
    pub blob: Uuid,
    pub key: Key,
}

impl Names {
    pub fn new(cover: &Key) -> Names {
        let derive = |slot: Slot| {
            let mut key = Zeroizing::new([0u8; 32]);
            let info = [b"Vault names 4".as_slice(), slot.letter().as_bytes()].concat();
            Hkdf::<Sha256>::new(None, cover.as_bytes()).expand(&info, key.as_mut()).expect("32 bytes is a valid length");
            key
        };
        Names { keys: [derive(Slot::A), derive(Slot::B)] }
    }

    fn tag(&self, random: &[u8], slot: Slot) -> [u8; 8] {
        let key = &self.keys[if slot == Slot::A { 0 } else { 1 }];
        let mut mac = Hmac::<Sha256>::new_from_slice(key.as_ref()).expect("any key length works");
        mac.update(random);
        mac.finalize().into_bytes()[..8].try_into().unwrap()
    }

    /// A new sealing for a slot: a fresh tagged id and a fresh 256-bit key of its own.
    pub fn fresh(&self, slot: Slot) -> ItemSeal {
        let mut bytes = [0u8; 16];
        fill_random(&mut bytes[..8]);
        let tag = self.tag(&bytes[..8], slot);
        bytes[8..].copy_from_slice(&tag);
        ItemSeal { blob: Uuid::from_bytes(bytes), key: Key::random() }
    }

    /// Which slot made this id, or None when neither did.
    pub fn owner(&self, id: &Uuid) -> Option<Slot> {
        let bytes = id.as_bytes();
        Slot::ALL.into_iter().find(|&slot| self.tag(&bytes[..8], slot) == bytes[8..])
    }
}
