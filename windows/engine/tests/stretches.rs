//! Every try costs the same, whichever slots can answer: both slots are stretched for, and a slot whose key file is
//! missing, unreadable or refused before stretching costs a stretch anyway (docs/SECURITY.md rule 2). Counted, not
//! timed. One test alone in its own file, as the count is the whole process's.

mod common;

use std::fs;
use std::sync::atomic::Ordering;

use common::store_in;
use stillroom_core::argon2::STRETCHES;

fn stretches(during: impl FnOnce()) -> u64 {
    let before = STRETCHES.load(Ordering::SeqCst);
    during();
    STRETCHES.load(Ordering::SeqCst) - before
}

#[test]
fn every_try_costs_two_stretches() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (vault, code) = store.create("real password 123").unwrap();
    let theirs = vault.slot().other();
    drop(vault);

    let attempts: [(&str, &dyn Fn() -> bool); 5] = [
        ("right password", &|| store.unlock_with_password("real password 123").is_ok()),
        ("wrong password", &|| store.unlock_with_password("wrong").is_ok()),
        ("recovery key", &|| store.unlock_with_recovery_key(&code).is_ok()),
        ("wrong recovery key", &|| store.unlock_with_recovery_key("AAAAA-BBBBB").is_ok()),
        ("kit, none made", &|| store.unlock_with_kit(&["VK-0000"]).is_ok()),
    ];
    for (what, attempt) in attempts.iter().take(4) {
        assert_eq!(stretches(|| { attempt(); }), 2, "{what}");
    }

    // The other slot's password key missing, then damaged (refused before stretching): still two.
    let file = store.slot_file(theirs, "password.key");
    let saved = fs::read(&file).unwrap();
    fs::remove_file(&file).unwrap();
    assert_eq!(stretches(|| { store.unlock_with_password("real password 123").unwrap(); }), 2, "missing");
    assert_eq!(stretches(|| { assert!(store.unlock_with_password("wrong").is_err()); }), 2, "missing, wrong");
    fs::write(&file, b"not a key file at all, not at all, not at all").unwrap();
    assert_eq!(stretches(|| { store.unlock_with_password("real password 123").unwrap(); }), 2, "damaged");
    fs::write(&file, saved).unwrap();
    // A piece that doesn't read is refused before anything is stretched.
    assert_eq!(stretches(|| { attempts[4].1(); }), 0, "a mistyped kit piece");
}
