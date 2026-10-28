//! The intruder log, as the Mac's IntruderLogTests check it: written while locked, sealed to both slots, read only with
//! a slot's own key.

use std::fs;

use stillroom_core::intruder::{self, Kind};
use stillroom_core::vault::{Slot, Store};

fn store() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::at(dir.path().join("Store"));
    fs::create_dir_all(store.root()).unwrap();
    (dir, store)
}

/// Both slots' keys in place, as making a vault leaves them.
fn keys(store: &Store) -> (String, String) {
    let a = intruder::check(store, "", Slot::A).unwrap().0.to_string();
    let b = intruder::check(store, "", Slot::B).unwrap().0.to_string();
    (a, b)
}

#[test]
fn nothing_is_written_before_the_keys_exist() {
    let (_dir, store) = store();
    intruder::record(&store, Kind::WrongPassword, None, 0.0).unwrap();
    assert!(!intruder::folder(&store).exists());
}

/// Every entry is sealed to both slots: either one, open, reads the same log; a stranger's key reads nothing.
#[test]
fn entries_reach_both_slots() {
    let (_dir, store) = store();
    let (a, b) = keys(&store);
    let photo: Vec<u8> = (0..500u32).map(|i| (i % 256) as u8).collect();
    intruder::record(&store, Kind::WrongPassword, None, 100.0).unwrap();
    intruder::record(&store, Kind::WrongRecoveryKey, Some(&photo), 200.0).unwrap();
    let from_a = intruder::entries(&store, &a, Slot::A);
    let from_b = intruder::entries(&store, &b, Slot::B);
    assert_eq!(from_a.len(), 2);
    assert_eq!(from_a.iter().map(|e| e.id).collect::<Vec<_>>(), from_b.iter().map(|e| e.id).collect::<Vec<_>>());
    // Newest first.
    assert_eq!((from_b[0].kind, from_b[0].photo.as_deref()), (Kind::WrongRecoveryKey, Some(&photo[..])));
    assert!(intruder::entries(&store, &a, Slot::B).is_empty());
    let (stranger, _) = intruder::new_key();
    assert!(intruder::entries(&store, &stranger, Slot::A).is_empty());
    // Deleted in one, gone for both.
    intruder::delete(&store, &from_a[0].id).unwrap();
    assert_eq!(intruder::entries(&store, &b, Slot::B).len(), 1);
    intruder::clear(&store).unwrap();
    assert!(intruder::entries(&store, &a, Slot::A).is_empty());
}

/// A public half swapped by someone who can write the folder is noticed and reset, that half only.
#[test]
fn a_swapped_half_is_reset() {
    let (_dir, store) = store();
    let (a, b) = keys(&store);
    let (checked, swapped) = intruder::check(&store, &a, Slot::A).unwrap();
    assert_eq!((checked.as_str(), swapped), (a.as_str(), false));
    let mut both = fs::read(intruder::public_key_path(&store)).unwrap();
    let (_, someone_elses) = intruder::new_key();
    both[..32].copy_from_slice(&someone_elses);
    fs::write(intruder::public_key_path(&store), both).unwrap();
    let (checked, swapped) = intruder::check(&store, &a, Slot::A).unwrap();
    assert!(swapped && *checked != a);
    let (checked, swapped) = intruder::check(&store, &b, Slot::B).unwrap();
    assert_eq!((checked.as_str(), swapped), (b.as_str(), false));
}

/// The Mac's vault was made with intruder keys; entries written here open there's way (each slot's key from its list).
#[test]
fn an_entry_recorded_here_reads_with_the_mac_vaults_keys() {
    let dir = tempfile::tempdir().unwrap();
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vault");
    let copy = dir.path().join("Store");
    copy_tree(&fixture, &copy);
    let store = Store::at(&copy);
    store.record_intruder(Kind::WrongPassword, None).unwrap();
    for password in ["fixture password one", "fixture decoy two"] {
        assert_eq!(store.unlock_with_password(password).unwrap().intruder_entries().len(), 1);
    }
}

fn copy_tree(from: &std::path::Path, to: &std::path::Path) {
    fs::create_dir_all(to).unwrap();
    for entry in fs::read_dir(from).unwrap() {
        let entry = entry.unwrap();
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&entry.path(), &to.join(entry.file_name()));
        } else {
            fs::copy(entry.path(), to.join(entry.file_name())).unwrap();
        }
    }
}
