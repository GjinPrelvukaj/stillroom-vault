//! Lock to this PC, against this PC's real TPM (skipped where there's none): the Windows counterpart of the Mac's
//! `lockingToThisMacSealsTheKeyAgain`. "Another PC" is this one with the vault's TPM key deleted: to the vault it's the
//! same, the key isn't here. Every TPM key a test makes is deleted when it ends, failed or not.

#![cfg(windows)]

mod common;

use std::fs;

use common::store_in;
use stillroom_core::crypto::open_with_password;
use stillroom_core::tpm::{self, PcKey};
use stillroom_core::vault::{Slot, Store};
use stillroom_core::{Error, VaultError};

const REAL: &str = "real password 123";
const DECOY: &str = "decoy password 456";

/// Deletes the TPM keys a test made, however it ends.
struct Cleanup(Store, Vec<String>);

impl Drop for Cleanup {
    fn drop(&mut self) {
        if let Ok(file) = pc_key(&self.0) {
            tpm::delete(&file);
        }
        for name in &self.1 {
            tpm::delete(&PcKey { key: name.clone(), wrapped: String::new() });
        }
    }
}

fn pc_key(store: &Store) -> Result<PcKey, ()> {
    serde_json::from_slice(&fs::read(store.pc_key()).map_err(|_| ())?).map_err(|_| ())
}

fn password_keys(store: &Store) -> [Vec<u8>; 2] {
    Slot::ALL.map(|slot| fs::read(store.slot_file(slot, "password.key")).unwrap())
}

#[test]
fn locking_to_this_pc_seals_the_password_keys_again() {
    if !tpm::available() {
        return;
    }
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let _cleanup = Cleanup(store.clone(), Vec::new());
    let (mut vault, _) = store.create(REAL).unwrap();
    let mine = vault.slot();
    vault.set_other_slot(DECOY).unwrap();
    let plain = password_keys(&store);

    let code = vault.lock_to_this_pc().unwrap().expect("a new recovery key, to show once");
    assert!(vault.lock_to_this_pc().unwrap().is_none(), "already on");
    assert!(vault.is_locked_to_a_pc() && store.is_locked_to_a_pc());
    let locked = password_keys(&store);
    for (before, after) in plain.iter().zip(&locked) {
        assert_ne!(before, after);
        assert_eq!(after.len(), before.len() + 28, "sealed once more");
        // Without this PC's TPM, the password alone can't open it.
        assert!(open_with_password(after, REAL).is_err() && open_with_password(after, DECOY).is_err());
    }
    assert_eq!(locked[0].len(), locked[1].len(), "both slots alike");
    drop(vault);

    // On this PC the password still opens it, both vaults, and the new recovery key too.
    assert_eq!(store.unlock_with_password(REAL).unwrap().slot(), mine);
    assert_eq!(store.unlock_with_password(DECOY).unwrap().slot(), mine.other());
    assert_eq!(store.unlock_with_password("neither").err(), Some(Error::Vault(VaultError::WrongPassword)));
    store.unlock_with_recovery_key(&code).unwrap();

    // Changing the password and replacing the decoy keep the lock on what they write.
    let mut vault = store.unlock_with_password(REAL).unwrap();
    vault.change_password(REAL, "a changed password").unwrap();
    vault.set_other_slot("another decoy 789").unwrap();
    drop(vault);
    for key in password_keys(&store) {
        assert!(open_with_password(&key, "a changed password").is_err() && open_with_password(&key, "another decoy 789").is_err());
    }
    store.unlock_with_password("a changed password").unwrap();
    let mut vault = store.unlock_with_password("another decoy 789").unwrap();

    // Off: both keys plain again, the lock file gone and its TPM key deleted.
    let file = pc_key(&store).unwrap();
    vault.unlock_from_this_pc().unwrap();
    assert!(!store.is_locked_to_a_pc());
    assert_eq!(tpm::unwrap(&file).err(), Some(VaultError::NotThisComputer), "TPM key deleted");
    let unlocked = password_keys(&store);
    assert!(open_with_password(&unlocked[mine as usize], "a changed password").is_ok());
    assert_eq!(unlocked[0].len(), plain[0].len());
}

/// Copied to another PC (here: the vault's TPM key gone), the password opens neither vault; the recovery key does, and
/// the new password set after it moves the lock to this PC. The other vault's password stays sealed to the old PC until
/// its own recovery key is used, as on the Mac.
#[test]
fn on_another_pc_only_the_recovery_key_opens_it_and_the_lock_moves() {
    if !tpm::available() {
        return;
    }
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let mut cleanup = Cleanup(store.clone(), Vec::new());
    let (mut vault, _) = store.create(REAL).unwrap();
    let decoy_code = vault.set_other_slot(DECOY).unwrap();
    let code = vault.lock_to_this_pc().unwrap().unwrap();
    drop(vault);

    let old = pc_key(&store).unwrap();
    tpm::delete(&old);
    assert_eq!(store.unlock_with_password(REAL).err(), Some(Error::Vault(VaultError::NotThisComputer)));
    assert_eq!(store.unlock_with_password(DECOY).err(), Some(Error::Vault(VaultError::NotThisComputer)));

    let mut vault = store.unlock_with_recovery_key(&code).unwrap();
    assert_eq!(vault.change_password(REAL, "x").err(), Some(Error::Vault(VaultError::NotThisComputer)));
    vault.set_password_after_recovery("a password on this pc").unwrap();
    drop(vault);
    let moved = pc_key(&store).unwrap();
    cleanup.1.push(moved.key.clone());
    assert_ne!(moved.key, old.key, "a new TPM key here");
    store.unlock_with_password("a password on this pc").unwrap();
    // The decoy's password key is still sealed to the old PC: only its recovery key opens it now.
    assert_eq!(store.unlock_with_password(DECOY).err(), Some(Error::Vault(VaultError::WrongPassword)));
    store.unlock_with_recovery_key(&decoy_code).unwrap();

    // Wiping deletes the TPM key with the vault.
    store.unlock_with_password("a password on this pc").unwrap().wipe().unwrap();
    assert_eq!(tpm::unwrap(&moved).err(), Some(VaultError::NotThisComputer));
}

/// One computer holds the lock at a time: a vault locked to a Mac isn't also locked to a PC.
#[test]
fn a_vault_locked_to_a_mac_isnt_locked_to_a_pc_too() {
    if !tpm::available() {
        return;
    }
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let _cleanup = Cleanup(store.clone(), Vec::new());
    let (mut vault, _) = store.create(REAL).unwrap();
    fs::write(store.mac_key(), b"{}").unwrap();
    assert_eq!(vault.lock_to_this_pc().err(), Some(Error::LockedElsewhere));
    assert!(!store.is_locked_to_a_pc());
}

/// The lock files are key files: one date with the rest, so locking later leaves nothing newer.
#[test]
fn the_lock_file_shares_the_key_files_dates() {
    if !tpm::available() {
        return;
    }
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let _cleanup = Cleanup(store.clone(), Vec::new());
    let (mut vault, _) = store.create(REAL).unwrap();
    vault.lock_to_this_pc().unwrap();
    let dates: std::collections::HashSet<_> =
        store.key_files().iter().filter(|p| p.exists()).map(|p| fs::metadata(p).unwrap().modified().unwrap()).collect();
    assert_eq!(dates.len(), 1);
}
