//! A vault written by the Windows engine, laid out like the Mac's `writesFormatFixture` (vault/, source/, answers.json),
//! for the other readers to check: tools/stillroom-open.py through tools/test-stillroom-open.sh's checks, and the Mac app
//! from the copy committed in tests/fixtures-windows/. Don't regenerate the committed copy unless the format changes:
//! each run makes new random keys and files.
//!
//! STILLROOM_WINDOWS_FIXTURE_DIR=<empty folder> cargo test --test windows_fixture writes_windows_fixture

mod common;

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, UNIX_EPOCH};

use serde_json::{json, Value};
use stillroom_core::export::take_out;
use stillroom_core::fsx;
use stillroom_core::list::{Entry, Secret, Template};
use stillroom_core::vault::Store;

const PASSWORD: &str = "windows fixture password one";
const DECOY: &str = "windows fixture decoy two";

#[test]
fn writes_windows_fixture() {
    let Some(dir) = std::env::var_os("STILLROOM_WINDOWS_FIXTURE_DIR") else { return };
    let dir = PathBuf::from(dir);
    let source = dir.join("source");
    fs::create_dir_all(source.join("Taxes").join("2025")).unwrap();
    fs::write(source.join("Taxes/2025/w2.txt"), b"W-2 wages 52,000\n").unwrap();
    let photo: Vec<u8> = (0..20_000u32).map(|i| (i.wrapping_mul(2_654_435_761) >> 24) as u8).collect();
    fs::write(source.join("photo.bin"), &photo).unwrap();
    let old = UNIX_EPOCH + Duration::from_secs(1_560_000_000);
    fsx::set_dates(&source.join("photo.bin"), Some(old), old).unwrap();
    // 9 MiB: over the 8 MiB line, so it goes in chunks.
    let big: Vec<u8> = (0..9u32 << 20).map(|i| (i.wrapping_mul(31) >> 3) as u8).collect();
    fs::write(source.join("big.bin"), &big).unwrap();

    let store = Store::at(dir.join("vault")).with_cost(common::QUICK);
    let (mut vault, recovery) = store.create(PASSWORD).unwrap();
    let added = vault.add(&[source.join("Taxes"), source.join("photo.bin"), source.join("big.bin")], None);
    assert!(added.failed.is_empty() && added.items.len() == 3, "{:?}", added.failed);
    vault.new_entry(Entry::Note, "Shopping", b"milk\neggs\n", None).unwrap();
    let mut secret = Secret::new(Template::Login);
    secret.fields[0].value = "me@example.com".into();
    secret.fields[1].value = "hunter2-correct".into();
    vault.new_entry(Entry::Secret, "Bank", &serde_json::to_vec(&secret).unwrap(), None).unwrap();
    let pieces = vault.make_kit(2, 3).unwrap();
    vault.refresh_search(None).unwrap();
    vault.set_other_slot(DECOY).unwrap();
    drop(vault);
    let mut decoy = store.unlock_with_password(DECOY).unwrap();
    decoy.new_entry(Entry::Note, "Groceries", b"bread\n", None).unwrap();
    decoy.refresh_search(None).unwrap();
    drop(decoy);

    let answers = json!({
        "password": PASSWORD, "recovery": recovery, "pieces": pieces, "decoy": DECOY,
        "secretLines": ["Website: me@example.com", "Username: hunter2-correct", "Password: "],
    });
    fs::write(dir.join("answers.json"), serde_json::to_vec(&answers).unwrap()).unwrap();
}

fn committed() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures-windows")
}

/// The committed Windows-written vault still opens here, read only, every file as it went in: what the Mac is asked to
/// open is what this engine reads.
#[test]
fn the_committed_windows_vault_opens_here() {
    let root = committed();
    if !root.exists() {
        return;
    }
    let answers: Value = serde_json::from_slice(&fs::read(root.join("answers.json")).unwrap()).unwrap();
    let store = Store::at(root.join("vault")).read_only();
    let vault = store.unlock_with_password(answers["password"].as_str().unwrap()).unwrap();
    let out = tempfile::tempdir().unwrap();
    let report = take_out(&vault, out.path(), |_| {}).unwrap();
    assert_eq!((report.taken, report.failed.len()), (5, 0));
    for name in ["Taxes/2025/w2.txt", "photo.bin", "big.bin"] {
        assert!(fs::read(out.path().join(name)).unwrap() == fs::read(root.join("source").join(name)).unwrap(), "{name}");
    }
    let lines: Vec<String> = fs::read_to_string(out.path().join("Bank.txt")).unwrap().lines().map(Into::into).collect();
    assert_eq!(lines, answers["secretLines"].as_array().unwrap().iter().map(|l| l.as_str().unwrap().to_owned()).collect::<Vec<_>>());
    let decoy = store.unlock_with_password(answers["decoy"].as_str().unwrap()).unwrap();
    assert_eq!(decoy.files().iter().map(|i| i.name.as_str()).collect::<Vec<_>>(), ["Groceries"]);
}
