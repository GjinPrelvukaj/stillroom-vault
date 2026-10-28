//! Backups and restores, as the Mac's BackupTests check them, plus what's Windows' own: a restore swapped in three
//! renames, cut short after each, still leaves a whole vault (docs/SECURITY.md rule 7), and a doctored backup naming a
//! device or climbing out of the folder is turned away before anything is written.

mod common;

use std::fs;
use std::path::{Path, PathBuf};

use common::{sample, store_in};
use stillroom_core::backup::{self, suggested_name, FILE_EXTENSION};
use stillroom_core::vault::{Store, Vault};
use stillroom_core::{fsx, Error};
use tempfile::TempDir;

fn vault_with(dir: &TempDir, contents: &[u8], password: &str) -> (Store, Vault) {
    let store = store_in(dir.path());
    let (mut vault, _) = store.create(password).unwrap();
    let added = vault.add(&[sample(dir.path(), "photo.bin", contents)], None);
    assert_eq!(added.items.len(), 1);
    (store, vault)
}

fn only_file(vault: &Vault) -> Vec<u8> {
    vault.read(&vault.files()[0].id).unwrap().to_vec()
}

#[test]
fn a_backup_brings_the_vault_back_byte_for_byte() {
    let dir = tempfile::tempdir().unwrap();
    let bytes: Vec<u8> = (0..70_000u32).map(|i| i.wrapping_mul(2_654_435_761).to_be_bytes()[0]).collect();
    let (store, vault) = vault_with(&dir, &bytes, "backup password 1");
    drop(vault);

    let file = dir.path().join(suggested_name("2026-10-26"));
    backup::make(&store, &file).unwrap();
    backup::check(&file).unwrap();
    store.wipe().unwrap();
    assert!(!store.exists());
    assert_eq!(backup::restore(&store, &file).unwrap(), None);
    let vault = store.unlock_with_password("backup password 1").unwrap();
    assert_eq!(only_file(&vault), bytes);
}

#[test]
fn restoring_over_a_vault_moves_the_old_one_aside() {
    let dir = tempfile::tempdir().unwrap();
    let (store, first) = vault_with(&dir, b"first", "first password 1");
    drop(first);
    let file = dir.path().join(format!("one.{FILE_EXTENSION}"));
    backup::make(&store, &file).unwrap();
    store.wipe().unwrap();
    let (store, second) = vault_with(&dir, b"second", "second password 2");
    drop(second);

    let aside = backup::restore(&store, &file).unwrap().unwrap();
    assert!(aside.file_name().unwrap().to_string_lossy().starts_with("Store-before-restore-"));
    assert!(aside.join("a").join("password.key").exists());
    assert_eq!(only_file(&store.unlock_with_password("first password 1").unwrap()), b"first");
    // The one set aside is whole: it opens too.
    assert_eq!(only_file(&Store::at(&aside).with_cost(common::QUICK).unlock_with_password("second password 2").unwrap()), b"second");
}

/// A restore cut short at any step leaves a whole vault in place: before the swap, the old one, untouched; partway
/// through it, the next open puts the old one back or finishes; after it, the restored one with the old one beside it.
#[test]
fn a_restore_cut_short_leaves_a_whole_vault() {
    let dir = tempfile::tempdir().unwrap();
    let (store, first) = vault_with(&dir, b"first", "first password 1");
    drop(first);
    let file = dir.path().join(format!("one.{FILE_EXTENSION}"));
    backup::make(&store, &file).unwrap();
    store.wipe().unwrap();
    let (store, second) = vault_with(&dir, b"second", "second password 2");
    drop(second);
    let root = store.root().to_path_buf();
    let opens = |password: &str| only_file(&store.unlock_with_password(password).unwrap());

    // Stopped after staging: the live vault is as it was, and the staged copy is the whole backup.
    let staged = backup::stage(&store, &file).unwrap();
    assert_eq!(staged.parent(), root.parent());
    assert_eq!(opens("second password 2"), b"second");

    // Stopped after the swap's first rename: no vault under its name. Opening puts the old one back.
    fs::rename(&root, fsx::swapping(&root)).unwrap();
    assert!(!store.exists());
    assert_eq!(opens("second password 2"), b"second");
    assert!(!fsx::swapping(&root).exists());

    // Stopped after the second: the restored vault is in, the old one under the swapping name. Opening keeps the old
    // one beside it, as a finished restore does.
    fs::rename(&root, fsx::swapping(&root)).unwrap();
    fs::rename(&staged, &root).unwrap();
    assert_eq!(opens("first password 1"), b"first");
    let asides = befores(root.parent().unwrap());
    assert_eq!(asides.len(), 1);
    assert_eq!(only_file(&Store::at(&asides[0]).with_cost(common::QUICK).unlock_with_password("second password 2").unwrap()), b"second");
}

fn befores(parent: &Path) -> Vec<PathBuf> {
    fs::read_dir(parent)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("Store-before-restore-"))
        .collect()
}

#[test]
fn check_rejects_what_isnt_a_backup() {
    let dir = tempfile::tempdir().unwrap();
    let junk = sample(dir.path(), "junk.stillroombackup", &(0..4096u32).map(|i| (i * 7) as u8).collect::<Vec<_>>());
    assert_eq!(backup::check(&junk).err(), Some(Error::NotABackup));
    let zip = sample(dir.path(), "holiday.zip", b"PK\x03\x04 a zip, not a backup");
    assert_eq!(backup::check(&zip).err(), Some(Error::NotABackup));
    let store = store_in(dir.path());
    assert_eq!(backup::restore(&store, &zip).err(), Some(Error::NotABackup));
    // In the format, but of a folder that isn't a vault.
    let notes = crafted(dir.path(), &[("notes.txt", b"hi")]);
    assert_eq!(backup::check(&notes).err(), Some(Error::NotABackup));
    // Nothing left behind by any of it.
    assert!(!store.root().exists());
}

/// A backup written by hand to escape the folder, name a device, or give a path twice is turned away whole.
#[test]
fn a_doctored_backup_is_turned_away() {
    let dir = tempfile::tempdir().unwrap();
    let keys: [(&str, &[u8]); 2] = [("a/password.key", b"x"), ("b/password.key", b"x")];
    let fine = crafted(dir.path(), &keys);
    backup::check(&fine).unwrap();
    for bad in ["../escape", "a/../../escape", "/rooted", "a\\b", "CON", "a/nul.txt", "Files/lpt1", "trailing.", "a/./b", "x:y", "a/b/c/d"] {
        let file = crafted(dir.path(), &[keys[0], keys[1], (bad, b"evil")]);
        assert_eq!(backup::check(&file).err(), Some(Error::NotABackup), "{bad}");
    }
    let twice = crafted(dir.path(), &[keys[0], keys[1], ("a/list", b"one"), ("a/list", b"two")]);
    assert_eq!(backup::check(&twice).err(), Some(Error::NotABackup));
    // A size past the end of the file.
    let mut cut = fs::read(&fine).unwrap();
    cut.truncate(cut.len() - 4);
    let cut_path = sample(dir.path(), "cut.stillroombackup", &cut);
    assert_eq!(backup::check(&cut_path).err(), Some(Error::NotABackup));
}

/// A backup file written the way `pack` writes one, with whatever paths are given.
fn crafted(dir: &Path, files: &[(&str, &[u8])]) -> PathBuf {
    let mut data = b"STILLBK1".to_vec();
    for (path, contents) in files {
        data.extend_from_slice(&(path.len() as u16).to_be_bytes());
        data.extend_from_slice(path.as_bytes());
        data.extend_from_slice(&(contents.len() as u64).to_be_bytes());
        data.extend_from_slice(contents);
    }
    data.extend_from_slice(&0u16.to_be_bytes());
    sample(dir, "crafted.stillroombackup", &data)
}

#[test]
fn a_failed_backup_leaves_nothing_behind() {
    let dir = tempfile::tempdir().unwrap();
    let (store, vault) = vault_with(&dir, b"x", "some password 1");
    drop(vault);
    let missing = dir.path().join("Unplugged").join("Disk");
    let target = missing.join(suggested_name("2026-10-26"));
    assert!(backup::make(&store, &target).is_err());
    assert!(!target.exists() && !missing.exists());
}

#[test]
fn the_suggested_name_carries_the_day() {
    assert_eq!(suggested_name("2026-10-23"), "Stillroom Backup 2026-10-23.stillroombackup");
}

/// A backup of the vault the Mac wrote restores here and opens: backups go between the two.
#[test]
fn a_backup_of_the_mac_vault_restores_here() {
    let dir = tempfile::tempdir().unwrap();
    let fixture = Store::at(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vault")).read_only();
    let file = dir.path().join("mac.stillroombackup");
    backup::make(&fixture, &file).unwrap();
    let store = Store::at(dir.path().join("Store"));
    backup::restore(&store, &file).unwrap();
    let vault = store.unlock_with_password("fixture password one").unwrap();
    assert_eq!(vault.files().len(), 5);
}
