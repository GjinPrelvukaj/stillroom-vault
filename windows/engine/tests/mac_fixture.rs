//! The read path against a vault the Mac app wrote (tests/fixtures, from the Mac's `writesFormatFixture`): the checks
//! tools/test-stillroom-open.sh makes of stillroom-open.py, on the Windows engine. Nothing here writes into the
//! fixture; tests that change a vault change a copy. Don't regenerate it unless the format changes.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use serde_json::Value;
use stillroom_core::blob::{self, ChunkedReader};
use stillroom_core::export::{take_out, ItemFailure, Report};
use stillroom_core::names::Names;
use stillroom_core::vault::{Covered, Store, Vault};
use stillroom_core::{Error, VaultError};

fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

fn store() -> Store {
    Store::at(fixtures().join("vault")).read_only()
}

fn source(name: &str) -> Vec<u8> {
    fs::read(fixtures().join("source").join(name)).unwrap()
}

struct Answers {
    password: String,
    recovery: String,
    pieces: Vec<String>,
    decoy: String,
    secret_lines: Vec<String>,
}

fn answers() -> Answers {
    let json: Value = serde_json::from_slice(&fs::read(fixtures().join("answers.json")).unwrap()).unwrap();
    let text = |key: &str| json[key].as_str().unwrap().to_owned();
    let list = |key: &str| json[key].as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_owned()).collect();
    Answers {
        password: text("password"),
        recovery: text("recovery"),
        pieces: list("pieces"),
        decoy: text("decoy"),
        secret_lines: list("secretLines"),
    }
}

fn export(open: &Vault) -> (tempfile::TempDir, Report) {
    let out = tempfile::tempdir().unwrap();
    let report = take_out(open, out.path(), |_| {}).unwrap();
    (out, report)
}

/// What tools/test-stillroom-open.sh checks: every file byte for byte, photo.bin's date, the note and the secret.
fn check(out: &Path, report: &Report) {
    assert!(report.failed.is_empty(), "{:?}", report.failed);
    assert_eq!(fs::read(out.join("Taxes/2025/w2.txt")).unwrap(), source("Taxes/2025/w2.txt"));
    for name in ["photo.bin", "big.bin"] {
        assert!(fs::read(out.join(name)).unwrap() == source(name), "{name} differs");
    }
    let modified = fs::metadata(out.join("photo.bin")).unwrap().modified().unwrap();
    let off = modified.duration_since(UNIX_EPOCH).unwrap().as_secs_f64() - 1_560_000_000.0;
    assert!(off.abs() < 1.0, "photo.bin lost its date (off by {off} s)");
    assert_eq!(fs::read_to_string(out.join("Shopping.md")).unwrap(), "milk\neggs\n");
    let secret = fs::read_to_string(out.join("Bank.txt")).unwrap();
    assert_eq!(secret.lines().collect::<Vec<_>>(), answers().secret_lines);
}

#[test]
fn the_password_opens_the_mac_vault_and_everything_comes_out() {
    let open = store().unlock_with_password(&answers().password).unwrap();
    let (out, report) = export(&open);
    check(out.path(), &report);
}

#[test]
fn the_recovery_key_opens_the_mac_vault_however_its_typed() {
    let typed = answers().recovery.to_lowercase();
    let open = store().unlock_with_recovery_key(&typed).unwrap();
    let (out, report) = export(&open);
    check(out.path(), &report);
}

#[test]
fn any_two_of_the_mac_kits_pieces_open_it() {
    let a = answers();
    let password_slot = store().unlock_with_password(&a.password).unwrap().slot();
    // The order the harness types them in first, then every other pair.
    for pair in [[2, 0], [0, 1], [1, 2]] {
        let open = store().unlock_with_kit(&[&a.pieces[pair[0]], &a.pieces[pair[1]]]).unwrap();
        assert_eq!(open.slot(), password_slot, "pieces {pair:?}");
    }
    let open = store().unlock_with_kit(&[&a.pieces[2], &a.pieces[0]]).unwrap();
    let (out, report) = export(&open);
    check(out.path(), &report);
}

#[test]
fn the_decoy_password_opens_the_mac_decoy_and_nothing_else() {
    let a = answers();
    let open = store().unlock_with_password(&a.decoy).unwrap();
    assert_ne!(open.slot(), store().unlock_with_password(&a.password).unwrap().slot());
    let (out, report) = export(&open);
    assert_eq!((report.taken, report.failed.len()), (1, 0));
    let names: Vec<String> = fs::read_dir(out.path()).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into()).collect();
    assert_eq!(names, ["Groceries.md"]);
    assert_eq!(fs::read_to_string(out.path().join("Groceries.md")).unwrap(), "bread\n");
}

#[test]
fn a_wrong_password_doesnt_open_the_mac_vault() {
    assert_eq!(store().unlock_with_password("not the password").err(), Some(Error::Vault(VaultError::WrongPassword)));
    assert_eq!(store().unlock_with_recovery_key("AAAAA-BBBBB-CCCCC-DDDDD-EEEEE").err(), Some(Error::Vault(VaultError::WrongRecoveryKey)));
}

#[test]
fn the_mac_vault_is_shaped_as_the_format_says() {
    let a = answers();
    let open = store().unlock_with_password(&a.password).unwrap();
    let decoy = store().unlock_with_password(&a.decoy).unwrap();
    let root = store().root().to_path_buf();
    // Both slots' lists and indexes are in covers of one size, so a copy can't tell which changed.
    for name in ["list", "search"] {
        assert_eq!(fs::metadata(root.join("a").join(name)).unwrap().len(), fs::metadata(root.join("b").join(name)).unwrap().len(), "{name}");
    }
    // One cover key, opened from either slot; both slots' search indexes open with it.
    assert_eq!(open.cover().as_bytes(), decoy.cover().as_bytes());
    for slot in [open.slot(), decoy.slot()] {
        assert!(store().read_covered(Covered::Search, slot, open.cover()).is_some());
    }
    // Every item and version has its own key, and its blob is in Files/ under its sealedAs.
    for item in &open.list().files {
        let sealed_as = item.sealed_as.unwrap();
        assert!(open.item_key(&sealed_as).is_some() && store().blob(&sealed_as).is_file(), "{}", item.name);
    }
    // big.bin is 9 MiB, sealed in nine 1 MiB chunks.
    let big = open.list().files.iter().find(|i| i.name == "big.bin").unwrap();
    assert!(big.is_chunked());
    assert_eq!(fs::metadata(store().blob(&big.sealed_as.unwrap())).unwrap().len(), 8 + big.size + 9 * 28);
}

#[test]
fn any_range_of_the_mac_big_file_reads_back() {
    let open = store().unlock_with_password(&answers().password).unwrap();
    let big = open.list().files.iter().find(|i| i.name == "big.bin").unwrap();
    let sealed_as = big.sealed_as.unwrap();
    let reader = ChunkedReader::open(&store().blob(&sealed_as), open.item_key(&sealed_as).unwrap(), &sealed_as, big.size).unwrap();
    assert_eq!((reader.chunk_size(), reader.count()), (1 << 20, 9));
    let original = source("big.bin");
    let mib = 1u64 << 20;
    for range in [0..10, mib - 5..mib + 5, 4 * mib + 123..7 * mib + 456, big.size - 100..big.size] {
        assert!(*reader.read(range.clone()).unwrap() == original[range.start as usize..range.end as usize], "{range:?}");
    }
}

#[test]
fn a_changed_byte_in_a_mac_blob_is_caught_and_the_rest_come_out() {
    let copy = tempfile::tempdir().unwrap();
    copy_tree(store().root(), copy.path());
    let store = Store::at(copy.path());
    let open = store.unlock_with_password(&answers().password).unwrap();
    let big = open.list().files.iter().find(|i| i.name == "big.bin").unwrap();
    let path = store.blob(&big.sealed_as.unwrap());
    let mut sealed = fs::read(&path).unwrap();
    // Inside the fifth chunk.
    let at = 8 + 4 * ((1 << 20) + 28) + 1000;
    sealed[at] ^= 0x40;
    fs::write(&path, sealed).unwrap();
    assert_eq!(blob::read(&path, &big.sealed_as.unwrap(), open.item_key(&big.sealed_as.unwrap()).unwrap(), big.size, true).err(),
               Some(VaultError::Damaged));
    let (out, report) = export(&open);
    assert_eq!(report.taken, open.list().files.len() - 1);
    assert!(matches!(report.failed.as_slice(), [(path, ItemFailure::Damaged(VaultError::Damaged))] if path == Path::new("big.bin")));
    assert_eq!(fs::read(out.path().join("photo.bin")).unwrap(), source("photo.bin"));
}

/// The Mac named every item file with its slot's tag (HKDF and HMAC of the cover key): the port's `Names` must read
/// each as the slot whose list holds it. Were it wrong, opening (which prunes files no slot's list names) would delete
/// the Mac's files; opened here on a copy, from both slots, every one stays.
#[test]
fn the_mac_names_read_as_the_mac_wrote_them_and_opening_keeps_every_file() {
    let a = answers();
    let mine = store().unlock_with_password(&a.password).unwrap();
    let decoy = store().unlock_with_password(&a.decoy).unwrap();
    let names = Names::new(mine.cover());
    for (open, slot) in [(&mine, mine.slot()), (&decoy, decoy.slot())] {
        for blob in open.files().iter().flat_map(|i| i.blobs()) {
            assert_eq!(names.owner(&blob), Some(slot), "{blob}");
        }
    }

    let copy = tempfile::tempdir().unwrap();
    copy_tree(store().root(), copy.path());
    let before = file_names(copy.path());
    let intruder_pub = fs::read(copy.path().join("intruder.pub")).unwrap();
    for password in [&a.password, &a.decoy] {
        let open = Store::at(copy.path()).unlock_with_password(password).unwrap();
        // The Mac's intruder keys check out: nothing reset.
        assert!(!open.intruder_was_reset());
    }
    assert_eq!(file_names(copy.path()), before);
    assert_eq!(fs::read(copy.path().join("intruder.pub")).unwrap(), intruder_pub);
}

fn file_names(root: &Path) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(root.join("Files")).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into()).collect();
    names.sort();
    names
}

fn copy_tree(from: &Path, to: &Path) {
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
