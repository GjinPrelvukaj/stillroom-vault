//! A vault Stillroom 1.0.0 wrote on the Mac (macos/Tests/Fixtures/vault-1.0.0, the Mac's `OneZeroFixtureTests`),
//! opened every way in on Windows. Every later version must pass this: a buyer's 1.0 vault has to keep opening here
//! too. The fixture is never written to (tests that change it change a copy), and never regenerated or deleted.

use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;
use stillroom_core::list::{Entry, Secret};
use stillroom_core::vault::{Store, Vault};

fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../macos/Tests/Fixtures/vault-1.0.0")
}

fn answers() -> Value {
    serde_json::from_slice(&fs::read(fixture().join("answers.json")).unwrap()).unwrap()
}

fn source(name: &str) -> Vec<u8> {
    fs::read(fixture().join("source").join(name)).unwrap()
}

/// A copy of the fixture's vault, so opening it (which may tidy) never touches the committed one.
fn copy() -> (tempfile::TempDir, Store) {
    let dir = tempfile::tempdir().unwrap();
    copy_tree(&fixture().join("vault"), &dir.path().join("Store"));
    let store = Store::at(dir.path().join("Store"));
    (dir, store)
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

fn named(open: &Vault, name: &str) -> stillroom_core::list::Item {
    open.files().iter().find(|i| i.name == name).cloned().unwrap_or_else(|| panic!("{name} is missing"))
}

#[test]
fn a_vault_stillroom_1_wrote_still_opens_every_way_in() {
    let a = answers();
    let text = |key: &str| a[key].as_str().unwrap().to_owned();
    let (_dir, store) = copy();

    let mut open = store.unlock_with_password(&text("password")).unwrap();
    assert_eq!(open.files().len(), 5);
    let w2 = named(&open, "w2.txt");
    assert_eq!(*open.read(&w2.id).unwrap(), source("Taxes/2025/w2.txt"));
    assert_eq!(w2.folder.as_deref(), Some("Taxes/2025"));
    let photo = named(&open, "photo.bin");
    assert_eq!(*open.read(&photo.id).unwrap(), source("photo.bin"));
    let shown = photo.content_modified.or(photo.created).unwrap_or(photo.added_at);
    assert!((shown + stillroom_core::APPLE_EPOCH - 1_560_000_000.0).abs() < 1.0, "photo.bin lost its date");
    let big = named(&open, "big.bin");
    assert!(big.is_chunked());
    assert!(*open.read(&big.id).unwrap() == source("big.bin"));
    let shopping = named(&open, "Shopping");
    assert_eq!(shopping.entry, Some(Entry::Note));
    assert_eq!(*open.read(&shopping.id).unwrap(), b"milk\neggs\n");
    let bank = named(&open, "Bank");
    let secret: Secret = serde_json::from_slice(&open.read(&bank.id).unwrap()).unwrap();
    let lines: Vec<String> = secret.fields.iter().map(|f| format!("{}: {}", f.label, f.value)).collect();
    let expected: Vec<String> = a["secretLines"].as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_owned()).collect();
    assert_eq!(lines, expected);
    // Its sealed search index opens and finds the note by a word in it.
    open.refresh_search(None).unwrap();
    assert_eq!(open.search("eggs"), [shopping.id]);
    assert!(open.check(|_, _| {}).is_empty());
    let slot = open.slot();
    drop(open);

    assert_eq!(store.unlock_with_recovery_key(&text("recovery")).unwrap().files().len(), 5);
    let pieces: Vec<String> = a["pieces"].as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_owned()).collect();
    let by_kit = store.unlock_with_kit(&[&pieces[1], &pieces[2]]).unwrap();
    assert_eq!((by_kit.files().len(), by_kit.slot()), (5, slot));
    drop(by_kit);

    let decoy = store.unlock_with_password(&text("decoy")).unwrap();
    assert_ne!(decoy.slot(), slot);
    let names: Vec<&str> = decoy.files().iter().map(|i| i.name.as_str()).collect();
    assert_eq!(names, ["Groceries"]);
    assert_eq!(*decoy.read(&decoy.files()[0].id).unwrap(), b"bread\n");
}
