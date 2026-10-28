//! The decoy (format 4), as the Mac's DecoyTests check it: two slots built alike, neither marked, each with every way
//! in, and a copy of the folder showing nothing of which is which or which is used. One test per tell in
//! docs/SECURITY.md rule 2.

mod common;

use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::Path;
use std::time::{Duration, SystemTime};

use common::{sample, store_in};
use stillroom_core::crypto::uses_argon;
use stillroom_core::intruder::Kind;
use stillroom_core::vault::{Covered, Slot, Store, Vault};
use stillroom_core::{fsx, Error, VaultError};
use tempfile::TempDir;

const REAL: &str = "real password 123";
const DECOY: &str = "decoy password 456";

fn made() -> (TempDir, Store, Vault, String) {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (vault, code) = store.create(REAL).unwrap();
    (dir, store, vault, code)
}

fn add(vault: &mut Vault, dir: &TempDir, name: &str, text: &str) -> uuid::Uuid {
    let added = vault.add(&[sample(dir.path(), name, text.as_bytes())], None);
    assert!(added.failed.is_empty());
    added.items[0]
}

/// Every file in the folder (but items and the intruder log) with its size and, for key files, its header.
fn shape(root: &Path) -> BTreeMap<String, Vec<u64>> {
    fn walk(root: &Path, folder: &Path, found: &mut BTreeMap<String, Vec<u64>>) {
        for entry in fs::read_dir(folder).unwrap() {
            let path = entry.unwrap().path();
            let relative = path.strip_prefix(root).unwrap().to_string_lossy().replace('\\', "/");
            if relative == "Files" || relative == "intruder" {
                continue;
            }
            if path.is_dir() {
                walk(root, &path, found);
                continue;
            }
            let data = fs::read(&path).unwrap();
            let mut shape = vec![data.len() as u64];
            if relative.ends_with(".key") && uses_argon(&data) {
                shape.extend(data[..16].iter().map(|&b| u64::from(b)));
            }
            found.insert(relative, shape);
        }
    }
    let mut found = BTreeMap::new();
    walk(root, root, &mut found);
    found
}

#[test]
fn each_password_opens_its_own_vault() {
    let (dir, store, mut vault, _) = made();
    let mine = vault.slot();
    let secret = add(&mut vault, &dir, "secret.txt", "the real thing");
    vault.set_other_slot(DECOY).unwrap();
    drop(vault);

    let mut decoy = store.unlock_with_password(DECOY).unwrap();
    assert_eq!(decoy.slot(), mine.other());
    assert!(decoy.files().is_empty());
    add(&mut decoy, &dir, "shopping.txt", "milk");
    drop(decoy);

    let vault = store.unlock_with_password(REAL).unwrap();
    assert_eq!(vault.slot(), mine);
    assert_eq!(*vault.read(&secret).unwrap(), b"the real thing");
    drop(vault);
    assert_eq!(store.unlock_with_password("neither of them").err(), Some(Error::Vault(VaultError::WrongPassword)));
}

/// Tell 5: a slot nobody set is shaped exactly like one set and left empty, file for file, size for size, key header
/// for key header; and so is it again once removed.
#[test]
fn an_unset_slot_looks_like_a_set_empty_one() {
    let (_dir, store, mut vault, _) = made();
    let unset = shape(store.root());
    vault.set_other_slot(DECOY).unwrap();
    assert_eq!(shape(store.root()), unset);
    vault.reset_other_slot().unwrap();
    assert_eq!(shape(store.root()), unset);
    // Opened, the set one's list has the same size inside as the other's.
    vault.set_other_slot(DECOY).unwrap();
    drop(vault);
    let decoy = store.unlock_with_password(DECOY).unwrap();
    let set = store.read_covered(Covered::List, decoy.slot(), decoy.cover()).unwrap();
    let own = store.read_covered(Covered::List, decoy.slot().other(), decoy.cover()).unwrap();
    assert_eq!(set.len(), own.len());
}

/// Tell 1: the letters say nothing. Yours lands in either, and no name says main, decoy or second.
#[test]
fn the_real_vault_is_in_either_letter() {
    let dir = tempfile::tempdir().unwrap();
    let mut seen = HashSet::new();
    for n in 0..32 {
        let store = store_in(&dir.path().join(n.to_string()));
        seen.insert(store.create(REAL).unwrap().0.slot());
        if seen.len() == 2 {
            break;
        }
    }
    assert_eq!(seen.len(), 2);
    let (_dir, store, _vault, _) = made();
    let names = shape(store.root()).keys().cloned().collect::<Vec<_>>().join(" ").to_lowercase();
    for word in ["main", "decoy", "-2", "manifest", "real", "fake"] {
        assert!(!names.contains(word), "{word} in {names}");
    }
}

/// Tell 2: the decoy has its own recovery key and kit, and each opens its own slot only.
#[test]
fn both_slots_have_every_way_in() {
    let (_dir, store, mut vault, real_code) = made();
    let mine = vault.slot();
    let decoy_code = vault.set_other_slot(DECOY).unwrap();
    drop(vault);
    let mut decoy = store.unlock_with_password(DECOY).unwrap();
    let pieces = decoy.make_kit(2, 3).unwrap();
    assert!(decoy.has_kit());
    drop(decoy);

    assert_eq!(store.unlock_with_recovery_key(&decoy_code).unwrap().slot(), mine.other());
    let vault = store.unlock_with_recovery_key(&real_code).unwrap();
    assert_eq!(vault.slot(), mine);
    assert!(!vault.has_kit());
    drop(vault);
    assert_eq!(store.unlock_with_kit(&[&pieces[0], &pieces[2]]).unwrap().slot(), mine.other());
}

/// Tell 4: a save in one slot rewrites both slots' lists, in covers of one size and one date, the other's contents
/// untouched inside. The indexes too, once searched.
#[test]
fn a_save_rewrites_both_covers() {
    let (dir, store, mut vault, _) = made();
    let (mine, other) = (vault.slot(), vault.slot().other());
    let list = |slot: Slot| store.slot_file(slot, "list");
    let before = (fs::read(list(mine)).unwrap(), fs::read(list(other)).unwrap());
    let theirs = store.read_covered(Covered::List, other, vault.cover());
    // Enough files that the list grows several steps past an empty one.
    let files: Vec<_> = (0..40).map(|n| sample(dir.path(), &format!("file {n}.txt"), format!("contents {n}").as_bytes())).collect();
    assert!(vault.add(&files, None).failed.is_empty());
    let after = (fs::read(list(mine)).unwrap(), fs::read(list(other)).unwrap());
    assert!(after.0 != before.0 && after.1 != before.1);
    assert!(after.0.len() == after.1.len() && after.0.len() > before.0.len());
    assert_eq!(store.read_covered(Covered::List, other, vault.cover()), theirs);
    let dates = |slot: Slot| {
        let meta = fs::metadata(list(slot)).unwrap();
        (meta.created().unwrap(), meta.modified().unwrap())
    };
    assert_eq!(dates(mine), dates(other));

    assert!(vault.refresh_search(None).unwrap());
    let search = |slot: Slot| fs::metadata(store.slot_file(slot, "search")).unwrap().len();
    assert_eq!(search(mine), search(other));
    assert_eq!(vault.search("contents 17").len(), 1);
}

/// Tell 5: a decoy set long after the vault was made leaves no key file newer than the rest.
#[test]
fn key_files_share_their_dates() {
    let (_dir, store, mut vault, _) = made();
    let old = SystemTime::now() - Duration::from_secs(400 * 24 * 3600);
    fsx::even_dates(&store.key_files(), old);
    vault.set_other_slot(DECOY).unwrap();
    let dates: HashSet<_> = store
        .key_files()
        .iter()
        .filter(|p| p.exists())
        .map(|p| {
            let meta = fs::metadata(p).unwrap();
            (meta.created().unwrap(), meta.modified().unwrap())
        })
        .collect();
    assert_eq!(dates.len(), 1, "{dates:?}");
}

/// Tell 1: one folder of items for both slots, named so only a slot can tell its own. Pruning never takes the other's;
/// replacing a slot takes all of its old ones and none of yours; a file no slot named goes.
#[test]
fn item_files_are_unattributable() {
    let (dir, store, mut vault, _) = made();
    let mine = vault.slot();
    let my_item = add(&mut vault, &dir, "mine.txt", "mine");
    let my_blob = vault.item(&my_item).unwrap().sealed_as.unwrap();
    assert_eq!(vault.names().owner(&my_blob), Some(mine));
    vault.set_other_slot(DECOY).unwrap();
    drop(vault);

    let mut decoy = store.unlock_with_password(DECOY).unwrap();
    let their_item = add(&mut decoy, &dir, "theirs.txt", "theirs");
    let their_blob = decoy.item(&their_item).unwrap().sealed_as.unwrap();
    assert_eq!(decoy.names().owner(&their_blob), Some(mine.other()));
    drop(decoy);
    let stray = store.blob(&uuid::Uuid::new_v4());
    fs::write(&stray, b"stray").unwrap();

    let mut vault = store.unlock_with_password(REAL).unwrap();
    assert!(store.blob(&their_blob).exists(), "the other slot's file isn't pruned");
    assert!(!stray.exists(), "a file no slot named goes");
    vault.set_other_slot("another decoy 789").unwrap();
    assert!(!store.blob(&their_blob).exists(), "replacing the slot takes its old files");
    assert_eq!(*vault.read(&my_item).unwrap(), b"mine");
}

/// Replacing a slot is staged and swapped in one step: a half-made one left by a crash changes nothing and goes.
#[test]
fn a_half_made_slot_is_left_behind() {
    let (_dir, store, vault, _) = made();
    let other = vault.slot().other();
    drop(vault);
    fs::create_dir_all(store.staging(other)).unwrap();
    fs::write(store.staging(other).join("password.key"), b"half").unwrap();
    store.unlock_with_password(REAL).unwrap();
    assert!(!store.staging(other).exists());
}

/// A wrong try at the lock screen goes to both slots.
#[test]
fn intruder_entries_reach_both_slots() {
    let (_dir, store, mut vault, _) = made();
    vault.set_other_slot(DECOY).unwrap();
    drop(vault);
    store.record_intruder(Kind::WrongPassword, None).unwrap();
    let decoy = store.unlock_with_password(DECOY).unwrap();
    assert_eq!(decoy.intruder_entries().len(), 1);
    assert!(!decoy.intruder_was_reset());
    drop(decoy);
    let vault = store.unlock_with_password(REAL).unwrap();
    assert_eq!(vault.intruder_entries().len(), 1);
    assert!(!vault.intruder_was_reset());
}

/// A new password is checked against the other slot from either side alike.
#[test]
fn password_checks_are_symmetric() {
    let (_dir, store, mut vault, _) = made();
    assert_eq!(vault.set_other_slot(REAL).err(), Some(Error::Vault(VaultError::SameAsOther)));
    vault.set_other_slot(DECOY).unwrap();
    assert_eq!(vault.change_password(REAL, DECOY).err(), Some(Error::Vault(VaultError::SameAsOther)));
    drop(vault);
    let mut decoy = store.unlock_with_password(DECOY).unwrap();
    assert_eq!(decoy.change_password(DECOY, REAL).err(), Some(Error::Vault(VaultError::SameAsOther)));
}

/// A folder from before format 4 is reported, and nothing claims it's a vault.
#[test]
fn an_old_folder_is_left_alone() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    fs::create_dir_all(store.root()).unwrap();
    fs::write(store.root().join("password.key"), b"old").unwrap();
    assert!(store.is_old_format() && !store.exists());
}
