//! The vault folder is readable by this account only (the Mac's 0700): one entry, this account's, full control, passed
//! down to everything inside, and nothing inherited from the folders above.

#![cfg(windows)]

mod common;

use std::process::Command;

fn permissions(path: &std::path::Path) -> Vec<String> {
    let listed = Command::new("icacls").arg(path).output().unwrap();
    let text = String::from_utf8_lossy(&listed.stdout).into_owned();
    // Every line but the last (a summary) names one entry; the first also carries the path.
    let path = path.to_string_lossy().into_owned();
    text.lines()
        .map(|l| l.replace(&path, "").trim().to_owned())
        .filter(|l| !l.is_empty() && !l.starts_with("Successfully processed"))
        .collect()
}

fn me() -> String {
    let who = Command::new("whoami").output().unwrap();
    String::from_utf8_lossy(&who.stdout).trim().to_lowercase()
}

#[test]
fn a_new_vault_is_readable_by_this_account_only() {
    let dir = tempfile::tempdir().unwrap();
    let store = common::store_in(dir.path());
    let (vault, _) = store.create("real password 123").unwrap();
    drop(vault);

    let entries = permissions(store.root());
    assert_eq!(entries.len(), 1, "{entries:?}");
    assert_eq!(entries[0].to_lowercase(), format!("{}:(oi)(ci)(f)", me()), "full control for this account only, set here");

    // What's inside has only that entry, passed down from the vault folder.
    let inside = permissions(&store.slot_file(stillroom_core::vault::Slot::A, "password.key"));
    assert_eq!(inside.len(), 1, "{inside:?}");
    assert_eq!(inside[0].to_lowercase(), format!("{}:(i)(f)", me()));
}

#[test]
fn a_restored_vault_is_readable_by_this_account_only() {
    let dir = tempfile::tempdir().unwrap();
    let store = common::store_in(dir.path());
    store.create("real password 123").unwrap().0.backup(&dir.path().join("b.stillroombackup")).unwrap();
    store.wipe().unwrap();
    stillroom_core::backup::restore(&store, &dir.path().join("b.stillroombackup")).unwrap();
    let entries = permissions(store.root());
    assert_eq!(entries.len(), 1, "{entries:?}");
    assert!(entries[0].to_lowercase().ends_with(":(oi)(ci)(f)"));
}
