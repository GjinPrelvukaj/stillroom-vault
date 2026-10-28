//! The vault's flows end to end, as the Mac's VaultFlowTests, ItemKeyTests, ChunkBindingTests, CheckTests, FolderTests,
//! OriginalsTests, ExportKitTests and PasswordImportTests check them. Every test makes a vault of its own in a temp
//! folder; the real vault is never touched.

mod common;

use std::fs;
use std::time::{Duration, UNIX_EPOCH};

use common::{sample, store_in};
use serde_json::Value;
use stillroom_core::crypto::{bound, padded_size, seal, unseal, Key};
use stillroom_core::export::export_all;
use stillroom_core::import;
use stillroom_core::kit::KitProblem;
use stillroom_core::list::{Entry, Secret, VaultList};
use stillroom_core::session::Contents;
use stillroom_core::vault::{Covered, Store, Vault};
use stillroom_core::{fsx, Error, VaultError};
use tempfile::TempDir;
use uuid::Uuid;

const PASSWORD: &str = "real password 123";

fn made() -> (TempDir, Store, Vault, String) {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (vault, code) = store.create(PASSWORD).unwrap();
    (dir, store, vault, code)
}

fn added(vault: &mut Vault, dir: &TempDir, name: &str, contents: &[u8], into: Option<&str>) -> Uuid {
    let report = vault.add(&[sample(dir.path(), name, contents)], into);
    assert!(report.failed.is_empty(), "{:?}", report.failed);
    report.items[0]
}

fn blob_names(store: &Store) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(store.files()).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into()).collect();
    names.sort();
    names
}

/// Padding never shrinks a file and adds at most about 12%, so the sealed size gives little away.
#[test]
fn padding_is_bounded_and_never_shrinks() {
    for n in [0usize, 1, 2, 3, 100, 1000, 4097, 65_537, 1_000_000, 7_654_321] {
        let p = padded_size(n).unwrap();
        assert!(p >= n && p as f64 <= n as f64 * 1.13 + 2.0, "{n} -> {p}");
    }
}

#[test]
fn a_changed_password_replaces_the_old() {
    let (_dir, store, mut vault, _) = made();
    assert_eq!(vault.change_password("not it at all", "new password 456").err(), Some(Error::Vault(VaultError::WrongPassword)));
    vault.change_password(PASSWORD, "new password 456").unwrap();
    drop(vault);
    assert!(store.unlock_with_password(PASSWORD).is_err());
    store.unlock_with_password("new password 456").unwrap();
}

#[test]
fn the_recovery_key_opens_and_asks_for_a_new_password() {
    let (_dir, store, mut vault, _) = made();
    let code = vault.new_recovery_key().unwrap();
    drop(vault);
    assert!(store.unlock_with_recovery_key("AAAAA-BBBBB-CCCCC-DDDDD-EEEEE").is_err());
    // Typed in small letters without dashes, it still opens.
    let mut vault = store.unlock_with_recovery_key(&code.to_lowercase().replace('-', " ")).unwrap();
    assert!(vault.must_set_password());
    vault.set_password_after_recovery("brand new password").unwrap();
    assert!(!vault.must_set_password());
    drop(vault);
    store.unlock_with_password("brand new password").unwrap();
}

#[test]
fn a_new_vault_comes_with_a_working_recovery_key() {
    let (_dir, store, vault, code) = made();
    drop(vault);
    assert!(store.unlock_with_recovery_key(&code.to_lowercase()).is_ok());
}

#[test]
fn padded_files_come_back_exactly() {
    let (dir, store, mut vault, _) = made();
    let text = "x".repeat(4097);
    let id = added(&mut vault, &dir, "odd.txt", text.as_bytes(), None);
    let item = vault.item(&id).unwrap();
    let sealed = fs::metadata(store.blob(&item.sealed_as.unwrap())).unwrap().len();
    assert_eq!(sealed as usize, padded_size(4097).unwrap() + 28);
    assert_eq!(*vault.read(&id).unwrap(), text.as_bytes());
    assert_eq!(item.uti, "public.plain-text");
}

/// Windows can't hold a Mac's lock: a vault locked to a Mac opens here only with its recovery key, and the new password
/// set after it frees the vault (mac.key goes). The other slot's password key is left exactly as it was.
#[test]
fn a_vault_locked_to_a_mac_is_freed_here_by_its_recovery_key() {
    let (_dir, store, vault, code) = made();
    let slot = vault.slot();
    drop(vault);
    fs::write(store.mac_key(), b"{\"enclaveKey\":\"\",\"publicKey\":\"\"}").unwrap();
    let theirs = fs::read(store.slot_file(slot.other(), "password.key")).unwrap();
    assert_eq!(store.unlock_with_password(PASSWORD).err(), Some(Error::Vault(VaultError::NotThisComputer)));

    let mut vault = store.unlock_with_recovery_key(&code).unwrap();
    assert_eq!(vault.change_password(PASSWORD, "x").err(), Some(Error::Vault(VaultError::NotThisComputer)));
    vault.set_password_after_recovery("a new password here").unwrap();
    drop(vault);
    assert!(!store.mac_key().exists());
    assert_eq!(store.unlock_with_password("a new password here").unwrap().slot(), slot);
    assert_eq!(fs::read(store.slot_file(slot.other(), "password.key")).unwrap(), theirs);
}

/// A sealed file no list names is deleted when its vault opens; the listed ones stay.
#[test]
fn unlisted_files_are_cleared_on_open() {
    let (dir, store, mut vault, _) = made();
    let id = added(&mut vault, &dir, "keep.txt", b"keep", None);
    let stray = store.blob(&Uuid::new_v4());
    fs::write(&stray, b"stray").unwrap();
    drop(vault);
    let vault = store.unlock_with_password(PASSWORD).unwrap();
    assert!(!stray.exists());
    assert_eq!(*vault.read(&id).unwrap(), b"keep");
}

/// A note keeps its earlier text as a version once it's been left alone a while, and can be put back.
#[test]
fn notes_keep_versions_and_put_them_back() {
    let (_dir, store, mut vault, _) = made();
    let note = vault.new_entry(Entry::Note, "Plans", b"first", None).unwrap();
    // Typing straight after: no version.
    vault.update(&note, Contents::Bytes(b"second"), None).unwrap();
    assert!(vault.item(&note).unwrap().versions.is_none());
    // As after a break: last changed an hour ago.
    vault.backdate_for_tests(&note, 3600.0).unwrap();
    vault.update(&note, Contents::Bytes(b"third"), None).unwrap();
    let versions = vault.item(&note).unwrap().versions.clone().unwrap();
    assert_eq!(versions.len(), 1);
    assert_eq!(*vault.read_version(&note, &versions[0].id).unwrap(), b"second");
    vault.restore_version(&note, &versions[0].id).unwrap();
    assert_eq!(*vault.read(&note).unwrap(), b"second");
    assert_eq!(vault.item(&note).unwrap().versions.as_ref().unwrap().len(), 1);
    drop(vault);
    let vault = store.unlock_with_password(PASSWORD).unwrap();
    assert_eq!(*vault.read(&note).unwrap(), b"second");
}

/// At most 20 versions are kept, oldest going first, and their sealed files go with them.
#[test]
fn versions_stop_at_twenty_and_their_files_go() {
    let (_dir, store, mut vault, _) = made();
    let note = vault.new_entry(Entry::Note, "Diary", b"v0", None).unwrap();
    for n in 1..=23 {
        vault.backdate_for_tests(&note, 3600.0).unwrap();
        vault.update(&note, Contents::Bytes(format!("v{n}").as_bytes()), None).unwrap();
    }
    let versions = vault.item(&note).unwrap().versions.clone().unwrap();
    assert_eq!(versions.len(), 20);
    assert_eq!(*vault.read_version(&note, &versions[0].id).unwrap(), b"v3");
    // One blob for the current contents and one for each version: nothing older left behind.
    assert_eq!(blob_names(&store).len(), 21);
}

/// Folders carry what's in them when renamed, tags filter, and everything survives a lock.
#[test]
fn folders_and_tags_stick() {
    let (dir, store, mut vault, _) = made();
    vault.make_folder("Taxes", None).unwrap();
    vault.make_folder("2025", Some("Taxes")).unwrap();
    let id = added(&mut vault, &dir, "w2.txt", b"w2", Some("Taxes/2025"));
    assert_eq!(vault.item(&id).unwrap().folder.as_deref(), Some("Taxes/2025"));
    vault.set_tags(&id, &["money".into()]).unwrap();
    assert_eq!(vault.rename_folder("Taxes", "Paperwork").unwrap().as_deref(), Some("Paperwork"));
    drop(vault);
    let mut vault = store.unlock_with_password(PASSWORD).unwrap();
    assert_eq!(vault.item(&id).unwrap().folder.as_deref(), Some("Paperwork/2025"));
    assert_eq!(vault.folders(), ["Paperwork", "Paperwork/2025"]);
    assert_eq!(vault.tags(), ["money"]);
    vault.delete_folder("Paperwork").unwrap();
    assert!(vault.files().is_empty());
    assert!(blob_names(&store).is_empty());
}

/// Folders move into folders with everything inside them; never into themselves; a "/" typed in a name stays.
#[test]
fn folders_move_into_folders() {
    let (dir, _store, mut vault, _) = made();
    vault.make_folder("26/10/26", None).unwrap();
    assert!(vault.folders().contains(&"26\u{2215}10\u{2215}26".to_string()));
    vault.make_folder("Taxes", None).unwrap();
    vault.make_folder("2025", Some("Taxes")).unwrap();
    let id = added(&mut vault, &dir, "w2.txt", b"w2", Some("Taxes/2025"));
    vault.make_folder("Archive", None).unwrap();

    vault.move_folder("Taxes", Some("Archive")).unwrap();
    assert_eq!(vault.item(&id).unwrap().folder.as_deref(), Some("Archive/Taxes/2025"));
    assert!(vault.folders().contains(&"Archive/Taxes/2025".to_string()) && !vault.folders().contains(&"Taxes".to_string()));

    assert_eq!(vault.move_folder("Archive", Some("Archive/Taxes")).err(), Some(Error::FolderIntoItself));
    assert_eq!(vault.item(&id).unwrap().folder.as_deref(), Some("Archive/Taxes/2025"));
    vault.make_folder("Taxes", None).unwrap();
    assert_eq!(vault.move_folder("Taxes", Some("Archive")).err(), Some(Error::FolderExists("Taxes".into())));
}

/// A dropped folder goes in as every file inside it, each remembering where it was; hidden files are left out.
#[test]
fn a_folder_becomes_the_files_inside_it() {
    let dir = tempfile::tempdir().unwrap();
    let taxes = dir.path().join("Taxes");
    fs::create_dir_all(taxes.join("2025")).unwrap();
    fs::write(taxes.join("notes.txt"), b"a").unwrap();
    fs::write(taxes.join("2025/w2.pdf"), b"b").unwrap();
    fs::write(taxes.join(".DS_Store"), b"c").unwrap();
    let marked = taxes.join("hidden by Windows.txt");
    fs::write(&marked, b"e").unwrap();
    std::process::Command::new("attrib").arg("+h").arg(&marked).status().unwrap();
    let alone = dir.path().join("alone.txt");
    fs::write(&alone, b"d").unwrap();

    let (items, skipped) = Store::expand(&[taxes.clone(), alone.clone()]);
    let found: Vec<(String, Option<String>)> =
        items.iter().map(|(p, f)| (p.file_name().unwrap().to_string_lossy().into(), f.clone())).collect();
    assert_eq!(found, [("w2.pdf".into(), Some("Taxes/2025".into())), ("notes.txt".into(), Some("Taxes".into())), ("alone.txt".into(), None)]);
    assert_eq!(skipped, 0);
}

// MARK: Item keys and bound seals

#[test]
fn sealed_files_cant_stand_in_for_each_other() {
    let (dir, store, mut vault, _) = made();
    let one = added(&mut vault, &dir, "one.txt", b"first secret", None);
    let two = added(&mut vault, &dir, "two.txt", b"second secret", None);
    let one_as = vault.item(&one).unwrap().sealed_as.unwrap();
    let two_as = vault.item(&two).unwrap().sealed_as.unwrap();
    fs::copy(store.blob(&one_as), store.blob(&two_as)).unwrap();
    assert_eq!(vault.read(&two).err(), Some(Error::Vault(VaultError::Damaged)));

    // Each item's own key opens only its own seal, even given the other's binding, and the vault key opens none.
    let sealed = fs::read(store.blob(&one_as)).unwrap();
    let own = vault.item_key(&one_as).unwrap();
    assert!(unseal(&sealed, own, Some(&bound::item(one_as.as_bytes()))).is_ok());
    assert!(unseal(&sealed, own, Some(&bound::item(two_as.as_bytes()))).is_err());
    assert!(unseal(&sealed, vault.key(), Some(&bound::item(one_as.as_bytes()))).is_err());

    // The search index copied over the list doesn't open as the list, nor the other slot's list as this one's.
    let slot = vault.slot();
    drop(vault);
    let list = store.slot_file(slot, "list");
    let saved = fs::read(&list).unwrap();
    for impostor in [store.slot_file(slot, "search"), store.slot_file(slot.other(), "list")] {
        fs::copy(&impostor, &list).unwrap();
        assert_eq!(store.unlock_with_password(PASSWORD).err(), Some(Error::Vault(VaultError::Damaged)));
    }
    fs::write(&list, saved).unwrap();
    store.unlock_with_password(PASSWORD).unwrap();
}

/// An empty list is unwrapped and padded, so every empty list is one size; one holding files is wrapped as
/// `{"format": 4, …}`. No item key is left on an item in memory.
#[test]
fn an_empty_list_keeps_its_shape_and_a_full_one_is_wrapped() {
    let (dir, store, mut vault, _) = made();
    let inner = |vault: &Vault| store.read_covered(Covered::List, vault.slot(), vault.cover()).unwrap();
    let empty = serde_json::to_vec(&VaultList::new(common::b64(&[0; 32]))).unwrap();
    assert_eq!(inner(&vault).len(), padded_size(empty.len()).unwrap() + 28);
    let json = unseal(&inner(&vault), vault.key(), Some(bound::LIST)).unwrap();
    assert!(serde_json::from_slice::<VaultList>(&json).unwrap().files.is_empty());

    added(&mut vault, &dir, "one.txt", b"first", None);
    let json = unseal(&inner(&vault), vault.key(), Some(bound::LIST)).unwrap();
    assert!(String::from_utf8_lossy(&json).contains("\"format\":4"));
    assert!(serde_json::from_slice::<VaultList>(&json).is_err());
    for item in vault.files() {
        assert_eq!(serde_json::to_value(item).unwrap().get("key"), None);
    }
}

/// A list sealed without its binding doesn't open, empty or not, and unlocking with it deletes nothing. Nor does a
/// list naming an item without its key, nor the list put back bare, without its cover.
#[test]
fn only_a_bound_list_with_every_key_opens() {
    let (dir, store, mut vault, _) = made();
    added(&mut vault, &dir, "one.txt", b"first", None);
    let (key, cover, slot) = (Key::from_slice(vault.key().as_bytes()).unwrap(), Key::from_slice(vault.cover().as_bytes()).unwrap(), vault.slot());
    let blobs = blob_names(&store);
    drop(vault);
    let bound_json = unseal(&store.read_covered(Covered::List, slot, &cover).unwrap(), &key, Some(bound::LIST)).unwrap();
    let empty = serde_json::to_vec(&VaultList::new(common::b64(&[0; 32]))).unwrap();
    for json in [bound_json.to_vec(), empty] {
        store.write_covered(&seal(&json, &key, None).unwrap(), Covered::List, slot, &cover).unwrap();
        assert_eq!(store.unlock_with_password(PASSWORD).err(), Some(Error::Vault(VaultError::Damaged)));
    }
    assert_eq!(blob_names(&store), blobs);

    let keyless = String::from_utf8_lossy(&bound_json).replace("\"key\":\"", "\"kee\":\"");
    store.write_covered(&seal(keyless.as_bytes(), &key, Some(bound::LIST)).unwrap(), Covered::List, slot, &cover).unwrap();
    assert_eq!(store.unlock_with_password(PASSWORD).err(), Some(Error::Vault(VaultError::Damaged)));

    fs::write(store.slot_file(slot, "list"), seal(&bound_json, &key, Some(bound::LIST)).unwrap()).unwrap();
    assert_eq!(store.unlock_with_password(PASSWORD).err(), Some(Error::Vault(VaultError::Damaged)));
}

/// An older version's chunks, or the whole older version, copied over the current streamed file: refused, because
/// every sealing ties its chunks to an id of its own.
#[test]
fn older_versions_cant_be_passed_off_as_the_current_one() {
    let (dir, store, mut vault, _) = made();
    let chunk = 1usize << 20;
    let first: Vec<u8> = (0..3 * chunk + 5).map(|i| (i as u32).wrapping_mul(7) as u8).collect();
    let id = added(&mut vault, &dir, "clip.mp3", &first, None);
    assert!(vault.item(&id).unwrap().is_chunked(), "audio goes in chunks");
    vault.backdate_for_tests(&id, 3600.0).unwrap();

    let second: Vec<u8> = (0..3 * chunk + 1000).map(|i| (i as u32).wrapping_mul(13) as u8).collect();
    vault.update(&id, Contents::File(&sample(dir.path(), "clip.mp3", &second)), None).unwrap();
    let item = vault.item(&id).unwrap().clone();
    let version = item.versions.as_ref().unwrap().last().unwrap().clone();
    assert!(item.is_chunked());
    assert_eq!(*vault.read(&id).unwrap(), second);
    assert_eq!(*vault.read_version(&id, &version.id).unwrap(), first);

    let current = store.blob(&item.sealed_as.unwrap());
    let older = fs::read(store.blob(&version.sealed_as.unwrap())).unwrap();
    let (header, sealed_chunk) = (8, chunk + 28);
    let mut mixed = fs::read(&current).unwrap();
    mixed[header + sealed_chunk..header + 2 * sealed_chunk].copy_from_slice(&older[header + sealed_chunk..header + 2 * sealed_chunk]);
    fs::write(&current, &mixed).unwrap();
    assert!(vault.read(&id).is_err());
    fs::write(&current, &older).unwrap();
    assert!(vault.read(&id).is_err());
    assert!(vault.check(|_, _| {}).iter().any(|d| d.item == id));
}

// MARK: Checking

/// Check finds damage a disk fault would leave, and its fixes put things right.
#[test]
fn check_finds_and_fixes_damage() {
    let (dir, store, mut vault, _) = made();
    added(&mut vault, &dir, "fine.txt", b"fine", None);
    let notes = added(&mut vault, &dir, "notes.txt", b"first", None);
    vault.backdate_for_tests(&notes, 3600.0).unwrap();
    vault.update(&notes, Contents::Bytes(b"second"), None).unwrap();
    let earlier = vault.item(&notes).unwrap().versions.as_ref().unwrap()[0].id;
    assert!(vault.check(|_, _| {}).is_empty());

    // The current contents break: it falls back to the earlier version, which still opens.
    let blob = store.blob(&vault.item(&notes).unwrap().sealed_as.unwrap());
    let mut data = fs::read(&blob).unwrap();
    let middle = data.len() / 2;
    data[middle] ^= 0xFF;
    fs::write(&blob, data).unwrap();
    let mut progress = Vec::new();
    let found = vault.check(|done, total| progress.push((done, total)));
    assert_eq!(progress.last(), Some(&(3, 3)));
    assert_eq!(found.len(), 1);
    assert_eq!((found[0].item, found[0].version, found[0].fallback), (notes, None, Some(earlier)));
    vault.fall_back(&notes, &earlier).unwrap();
    assert_eq!(*vault.read(&notes).unwrap(), b"first");
    assert!(vault.check(|_, _| {}).is_empty());
    assert!(!blob.exists());
}

/// The screen sharing switch is kept sealed in the vault: remembered across a lock.
#[test]
fn show_in_capture_is_remembered_with_the_vault() {
    let (_dir, store, mut vault, _) = made();
    assert!(!vault.show_in_capture());
    vault.set_show_in_capture(true).unwrap();
    drop(vault);
    let mut vault = store.unlock_with_password(PASSWORD).unwrap();
    assert!(vault.show_in_capture());
    vault.set_show_in_capture(false).unwrap();
}

// MARK: Originals

fn originals_folder(dir: &TempDir, files: &[(&str, &str)]) -> std::path::PathBuf {
    let top = dir.path().join(format!("Originals-{}", Uuid::new_v4().simple())).join("Taxes");
    for (path, text) in files {
        let path = top.join(path);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }
    top
}

#[test]
fn a_folder_with_everything_in_goes_whole() {
    let (dir, _store, mut vault, _) = made();
    let top = originals_folder(&dir, &[("w2.txt", "w2"), ("2025/receipt.txt", "receipt"), (".DS_Store", "finder")]);
    let added = vault.add(std::slice::from_ref(&top), None);
    assert_eq!(added.originals.files.len(), 2);
    let removals: Vec<String> = added.originals.removals().iter().map(|p| p.file_name().unwrap().to_string_lossy().into()).collect();
    assert_eq!(removals, ["Taxes"]);
    assert!(added.originals.delete().is_empty());
    assert!(!top.exists());
    assert_eq!(vault.files().len(), 2);
}

#[test]
fn hidden_files_keep_their_folder() {
    let (dir, _store, mut vault, _) = made();
    let top = originals_folder(&dir, &[("w2.txt", "w2"), (".env", "never went in")]);
    let added = vault.add(std::slice::from_ref(&top), None);
    let removals: Vec<String> = added.originals.removals().iter().map(|p| p.file_name().unwrap().to_string_lossy().into()).collect();
    assert_eq!(removals, ["w2.txt"]);
    assert!(added.originals.delete().is_empty());
    assert!(!top.join("w2.txt").exists());
    assert!(top.join(".env").exists());
}

/// Adding the folder the vault lives in (a whole user folder, say) leaves the vault's own files out, and what's
/// beside it: so deleting the originals afterwards can't take the vault's keys with them.
#[test]
fn the_vault_never_goes_into_itself() {
    let (dir, store, mut vault, _) = made();
    fs::write(dir.path().join("notes.txt"), "mine").unwrap();
    fs::write(dir.path().join("tries.json"), "{}").unwrap();
    let added = vault.add(&[dir.path().to_path_buf()], None);
    let names: Vec<&str> = vault.files().iter().map(|i| i.name.as_str()).collect();
    assert_eq!(names, ["notes.txt"], "only what isn't the vault went in");
    assert!(added.skipped > 0);
    assert!(added.originals.delete().is_empty());
    assert!(!dir.path().join("notes.txt").exists());
    assert!(dir.path().join("tries.json").exists(), "the wrong-try count stays");
    drop(vault);
    let reopened = store.unlock_with_password(PASSWORD).unwrap();
    assert_eq!(reopened.files().len(), 1, "the vault still opens, whole");
}

#[test]
fn copies_are_checked_against_their_originals() {
    let (dir, store, mut vault, _) = made();
    // Small (one piece) and big (in chunks).
    let small = sample(dir.path(), "note.txt", b"hello");
    let big = sample(dir.path(), "big.bin", &(0..9u32 << 20).map(|i| i.wrapping_mul(31) as u8).collect::<Vec<_>>());
    let added = vault.add(&[small.clone(), big.clone()], None);
    assert_eq!(added.originals.files.len(), 2);
    let big_item = vault.files().iter().find(|i| i.name == "big.bin").unwrap().clone();
    assert!(big_item.is_chunked());
    let key = vault.item_key(&big_item.sealed_as.unwrap()).unwrap();
    assert!(stillroom_core::originals::Originals::matches(&store, &big_item, &big, key));

    // The original changes after sealing: it no longer matches, so it would never be offered for deletion.
    fs::write(&small, b"hellO").unwrap();
    let small_item = vault.files().iter().find(|i| i.name == "note.txt").unwrap().clone();
    let key = vault.item_key(&small_item.sealed_as.unwrap()).unwrap();
    assert!(!stillroom_core::originals::Originals::matches(&store, &small_item, &small, key));
}

// MARK: Exporting and the kit

#[test]
fn export_all_takes_everything_out_with_dates() {
    let (dir, _store, mut vault, _) = made();
    let photo = sample(dir.path(), "photo.jpg", b"pixels");
    let old = UNIX_EPOCH + Duration::from_secs(1_560_000_000);
    fsx::set_dates(&photo, Some(old), old).unwrap();
    added_path(&mut vault, &photo, Some("Trips/2019"));
    vault.new_entry(Entry::Note, "../../escape", b"not out", None).unwrap();
    vault.make_folder("Empty", None).unwrap();

    let out = dir.path().join("Export");
    fs::create_dir_all(&out).unwrap();
    let (top, report) = export_all(&vault, &out, |_| {}).unwrap();
    assert!(report.failed.is_empty());
    assert!(top.file_name().unwrap().to_string_lossy().starts_with("Stillroom Export "));
    let copied = top.join("Trips").join("2019").join("photo.jpg");
    assert_eq!(fs::read(&copied).unwrap(), b"pixels");
    let meta = fs::metadata(&copied).unwrap();
    assert_eq!(meta.modified().unwrap(), old);
    assert_eq!(meta.created().unwrap(), old, "the date it was made comes back too");
    // A name trying to climb out stays inside the export folder.
    assert!(top.join("..-..-escape.md").exists());
    assert!(top.join("Empty").is_dir());
    // A second export goes beside the first, not over it.
    let (again, _) = export_all(&vault, &out, |_| {}).unwrap();
    assert_ne!(again, top);
}

fn added_path(vault: &mut Vault, path: &std::path::Path, into: Option<&str>) -> Uuid {
    let report = vault.add(&[path.to_path_buf()], into);
    assert!(report.failed.is_empty(), "{:?}", report.failed);
    report.items[0]
}

#[test]
fn kit_pieces_open_the_vault_and_old_kits_stop_working() {
    let (_dir, store, mut vault, _) = made();
    assert!(!vault.has_kit());
    let old = vault.make_kit(2, 3).unwrap();
    let pieces = vault.make_kit(3, 5).unwrap();
    assert!(vault.has_kit());
    assert_eq!(vault.make_kit(1, 3).err(), Some(Error::Kit(KitProblem::NotEnough(2))));
    drop(vault);

    assert_eq!(store.unlock_with_kit(&[&pieces[0], &pieces[4]]).err(), Some(Error::Kit(KitProblem::NotEnough(3))));
    assert_eq!(store.unlock_with_kit(&[&old[0], &old[1]]).err(), Some(Error::Vault(VaultError::WrongKit)));
    let mut vault = store.unlock_with_kit(&[&pieces[4], &pieces[1], &pieces[2]]).unwrap();
    assert!(vault.must_set_password());
    vault.remove_kit().unwrap();
    assert!(!vault.has_kit());
    drop(vault);
    assert_eq!(store.unlock_with_kit(&[&pieces[0], &pieces[1], &pieces[2]]).err(), Some(Error::Vault(VaultError::WrongKit)));
}

/// The kit is brought up once a year, not straight after it's made.
#[test]
fn a_new_kit_isnt_brought_up_yet() {
    let (_dir, _store, mut vault, _) = made();
    vault.make_kit(2, 2).unwrap();
    assert!(!vault.kit_reminder_due().unwrap());
}

// MARK: Importing passwords

#[test]
fn importing_twice_adds_nothing_twice() {
    let (_dir, _store, mut vault, _) = made();
    let logins = import::logins(b"Title,URL,Username,Password\nA,https://a.com,me,1\nB,https://b.com,me,2\n").unwrap();
    assert_eq!(vault.import_logins(&logins).unwrap(), (2, 0));
    assert!(vault.files().iter().all(|i| i.entry == Some(Entry::Secret) && i.folder.as_deref() == Some("Imported")));
    assert_eq!(vault.import_logins(&logins).unwrap(), (0, 2));
    let first = vault.files()[0].id;
    let stored: Secret = serde_json::from_slice(&vault.read(&first).unwrap()).unwrap();
    assert!(stored.fields[2].value == "1" || stored.fields[2].value == "2");
    // Written as the Mac writes a Secret: template and fields with their ids.
    let json: Value = serde_json::from_slice(&vault.read(&first).unwrap()).unwrap();
    assert_eq!(json["template"], "login");
    assert!(json["fields"][0]["id"].as_str().unwrap().chars().all(|c| !c.is_ascii_lowercase()));
}

// MARK: Windows: a slot swapped halfway

/// The Mac swaps a slot in one step; Windows takes three renames. A crash after any of them leaves a whole slot that
/// opens, and the next unlock puts the folder right.
#[test]
fn a_slot_swap_cut_short_leaves_a_whole_slot() {
    let (_dir, store, vault, _) = made();
    let mine = vault.slot();
    drop(vault);
    let live = store.slot_folder(mine);
    let staged = store.staging(mine);
    let copy = |from: &std::path::Path, to: &std::path::Path| {
        fs::create_dir_all(to).unwrap();
        for entry in fs::read_dir(from).unwrap() {
            let entry = entry.unwrap();
            fs::copy(entry.path(), to.join(entry.file_name())).unwrap();
        }
    };

    // Stopped after step 1: the live slot is under its swapping name, nothing in its place.
    copy(&live, &staged);
    fs::rename(&live, fsx::swapping(&live)).unwrap();
    store.unlock_with_password(PASSWORD).unwrap();
    assert!(live.exists() && !fsx::swapping(&live).exists() && !staged.exists());

    // Stopped after step 2: the new slot is in, the old one under the swapping name.
    copy(&live, &staged);
    fs::rename(&live, fsx::swapping(&live)).unwrap();
    fs::rename(&staged, &live).unwrap();
    store.unlock_with_password(PASSWORD).unwrap();
    assert!(live.exists() && !fsx::swapping(&live).exists() && !staged.exists());
}

#[test]
fn an_attachment_goes_in_with_its_kind() {
    let (_dir, _store, mut vault, _) = made();
    let id = vault.add_data(b"%PDF-1.4", "invoice.pdf", Some("Mail")).unwrap();
    let item = vault.item(&id).unwrap();
    assert_eq!((item.uti.as_str(), item.folder.as_deref()), ("com.adobe.pdf", Some("Mail")));
    let movie = vault.add_data(b"not really a movie", "clip.mov", None).unwrap();
    assert!(vault.item(&movie).unwrap().is_chunked(), "video always goes in chunks");
    assert_eq!(*vault.read(&movie).unwrap(), b"not really a movie");
}

#[test]
fn deleting_an_item_deletes_its_versions_too() {
    let (dir, store, mut vault, _) = made();
    let id = added(&mut vault, &dir, "a.txt", b"one", None);
    vault.backdate_for_tests(&id, 3600.0).unwrap();
    vault.update(&id, Contents::Bytes(b"two"), Some("b.txt")).unwrap();
    assert_eq!(vault.item(&id).unwrap().name, "b.txt");
    assert_eq!(blob_names(&store).len(), 2);
    vault.delete(&id).unwrap();
    assert!(blob_names(&store).is_empty());
    assert_eq!(vault.read(&id).err(), Some(Error::NotFound));
}

#[test]
fn a_vault_can_be_wiped() {
    let (dir, store, vault, _) = made();
    vault.wipe().unwrap();
    assert!(!store.exists() && !dir.path().join("Store").exists());
}
