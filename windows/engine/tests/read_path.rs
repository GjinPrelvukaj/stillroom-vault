//! The read path end to end, against a vault written from docs/FORMAT.md: the checks tools/test-stillroom-open.sh
//! makes of stillroom-open.py, then the ways a vault can be damaged or doctored.

mod common;

use std::fs;
use std::time::{Duration, UNIX_EPOCH};

use common::*;
use serde_json::json;
use stillroom_core::blob::{self, ChunkedReader};
use stillroom_core::crypto::Key;
use stillroom_core::export::{safe, take_out, ItemFailure, Report};
use stillroom_core::kit::{self, KitProblem};
use stillroom_core::vault::{Covered, Slot, Store, Vault};
use stillroom_core::Error;
use stillroom_core::VaultError;

fn export(open: &Vault, out: &std::path::Path) -> Report {
    take_out(open, out, |_| {}).unwrap()
}

/// What tools/test-stillroom-open.sh checks: every file byte for byte, with its date, the note and the secret.
fn check_everything_came_out(f: &Fixture, out: &std::path::Path) {
    assert_eq!(fs::read(out.join("Taxes/2025/w2.txt")).unwrap(), f.w2);
    assert_eq!(fs::read(out.join("photo.bin")).unwrap(), f.photo);
    assert_eq!(fs::read(out.join("big.bin")).unwrap(), f.big);
    let modified = fs::metadata(out.join("photo.bin")).unwrap().modified().unwrap();
    assert_eq!(modified, UNIX_EPOCH + Duration::from_secs(1_560_000_000), "photo.bin lost its date");
    assert_eq!(fs::read_to_string(out.join("Shopping.md")).unwrap(), "milk\neggs\n");
    assert_eq!(fs::read_to_string(out.join("Bank.txt")).unwrap(), "Bank: First Savings\nPassword: hunter2: with a colon\n");
    assert!(out.join("Empty").is_dir(), "an empty folder in the list comes out too");
    assert!(!fs::read_dir(out).unwrap().any(|e| e.unwrap().file_name().to_string_lossy().ends_with(".partial")));
}

#[test]
fn the_password_opens_its_slot_and_everything_comes_out() {
    let f = Fixture::new();
    let open = f.store.unlock_with_password(&f.password).unwrap();
    assert_eq!(open.slot(), f.yours);
    assert_eq!(open.list().files.len(), 5);
    let out = f.out("out-password");
    let report = export(&open, &out);
    assert_eq!((report.taken, report.failed.len()), (5, 0));
    check_everything_came_out(&f, &out);
}

#[test]
fn the_recovery_key_opens_it_however_its_typed() {
    let f = Fixture::new();
    let typed = f.recovery.to_lowercase().replace('-', " ");
    let open = f.store.unlock_with_recovery_key(&typed).unwrap();
    assert_eq!(open.slot(), f.yours);
    check_everything_came_out(&f, &{
        let out = f.out("out-recovery");
        export(&open, &out);
        out
    });
}

#[test]
fn any_two_kit_pieces_open_it_as_typed_from_paper() {
    let f = Fixture::new();
    // Out of order, lowercase, without dashes, with O for 0 and l for 1.
    let sloppy = |p: &str| p.to_lowercase().replace('-', "").replace('0', "O").replace('1', "l");
    let typed = [sloppy(&f.pieces[2]), f.pieces[0].clone()];
    let open = f.store.unlock_with_kit(&[&typed[0], &typed[1]]).unwrap();
    assert_eq!(open.slot(), f.yours);
    for pair in [[0, 1], [1, 2], [0, 2]] {
        let typed: Vec<&str> = pair.iter().map(|&i| f.pieces[i].as_str()).collect();
        assert!(f.store.unlock_with_kit(&typed).is_ok());
    }
}

#[test]
fn the_decoy_password_opens_the_decoy_and_nothing_else() {
    let f = Fixture::new();
    let open = f.store.unlock_with_password(&f.decoy).unwrap();
    assert_eq!(open.slot(), other(f.yours));
    let out = f.out("out-decoy");
    export(&open, &out);
    let names: Vec<String> = fs::read_dir(&out).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into()).collect();
    assert_eq!(names, ["Groceries.md"]);
    assert_eq!(fs::read_to_string(out.join("Groceries.md")).unwrap(), "bread\n");
}

#[test]
fn wrong_ways_in_say_which_way_was_wrong() {
    let f = Fixture::new();
    assert_eq!(f.store.unlock_with_password("not the password").err(), Some(Error::Vault(VaultError::WrongPassword)));
    assert_eq!(f.store.unlock_with_recovery_key("AAAAA-BBBBB-CCCCC-DDDDD-EEEEE").err(), Some(Error::Vault(VaultError::WrongRecoveryKey)));

    let other_kit: Vec<String> = kit::split(&[1; 16], 2, 3).iter().map(kit::code).collect();
    assert_eq!(f.store.unlock_with_kit(&[&other_kit[0], &other_kit[1]]).err(), Some(Error::Vault(VaultError::WrongKit)));
    let three: Vec<String> = kit::split(&[1; 16], 3, 3).iter().map(kit::code).collect();
    assert_eq!(f.store.unlock_with_kit(&[&f.pieces[0], &three[1]]).err(), Some(Error::Kit(KitProblem::Mixed)));
    assert_eq!(f.store.unlock_with_kit(&[&f.pieces[0]]).err(), Some(Error::Kit(KitProblem::NotEnough(2))));
    assert_eq!(f.store.unlock_with_kit(&[&f.pieces[0], &f.pieces[0]]).err(), Some(Error::Kit(KitProblem::NotEnough(2))));
    // One letter changed: the check bytes catch it.
    let mut mistyped = f.pieces[1].clone().into_bytes();
    let at = mistyped.len() - 2;
    mistyped[at] = if mistyped[at] == b'A' { b'B' } else { b'A' };
    let mistyped = String::from_utf8(mistyped).unwrap();
    assert_eq!(f.store.unlock_with_kit(&[&f.pieces[0], &mistyped]).err(), Some(Error::Kit(KitProblem::Mistyped)));
}

#[test]
fn a_damaged_key_file_in_one_slot_doesnt_stop_the_other_opening() {
    let f = Fixture::new();
    let theirs = f.root().join(other(f.yours).letter()).join("password.key");
    fs::write(&theirs, b"VA2\x01 not a key file at all, not at all").unwrap();
    assert_eq!(f.store.unlock_with_password(&f.password).unwrap().slot(), f.yours);
}

#[test]
fn a_vault_locked_to_a_mac_opens_here_only_with_the_recovery_key_or_kit() {
    let f = Fixture::new();
    fs::write(f.root().join("mac.key"), b"{}").unwrap();
    assert_eq!(f.store.unlock_with_password(&f.password).err(), Some(Error::Vault(VaultError::NotThisComputer)));
    assert!(f.store.unlock_with_recovery_key(&f.recovery).is_ok());
    assert!(f.store.unlock_with_kit(&[&f.pieces[0], &f.pieces[1]]).is_ok());
}

#[test]
fn a_changed_blob_is_reported_and_the_rest_still_come_out() {
    let f = Fixture::new();
    let open = f.store.unlock_with_password(&f.password).unwrap();
    let photo = open.list().files.iter().find(|i| i.name == "photo.bin").unwrap();
    let path = f.store.blob(&photo.sealed_as.unwrap());
    let mut sealed = fs::read(&path).unwrap();
    sealed[100] ^= 1;
    fs::write(&path, sealed).unwrap();

    let out = f.out("out");
    let report = export(&open, &out);
    assert_eq!(report.taken, 4);
    assert_eq!(report.failed.len(), 1);
    assert_eq!(report.failed[0].0, std::path::Path::new("photo.bin"));
    assert!(matches!(report.failed[0].1, ItemFailure::Damaged(VaultError::Damaged)));
    assert!(!out.join("photo.bin").exists() && !out.join("photo.bin.partial").exists());
    assert_eq!(fs::read(out.join("big.bin")).unwrap(), f.big);
}

#[test]
fn sealed_files_cant_stand_in_for_each_other() {
    let f = Fixture::new();
    let open = f.store.unlock_with_password(&f.password).unwrap();
    let blob_of = |name: &str| f.store.blob(&open.list().files.iter().find(|i| i.name == name).unwrap().sealed_as.unwrap());
    // The note's blob put in the w2's place: its key and binding are the note's, so it opens as nothing.
    fs::copy(blob_of("Shopping"), blob_of("w2.txt")).unwrap();
    let report = export(&open, &f.out("out"));
    assert_eq!(report.failed.len(), 1);
    assert_eq!(report.failed[0].0, std::path::Path::new("Taxes").join("2025").join("w2.txt"));
}

#[test]
fn a_chunked_blob_cut_short_reordered_or_grown_fails() {
    let f = Fixture::new();
    let open = f.store.unlock_with_password(&f.password).unwrap();
    let big = open.list().files.iter().find(|i| i.name == "big.bin").unwrap();
    let (sealed_as, key) = (big.sealed_as.unwrap(), open.item_key(&big.sealed_as.unwrap()).unwrap());
    let path = f.store.blob(&sealed_as);
    let original = fs::read(&path).unwrap();
    let chunk = (1 << 20) + 28;
    let read = || blob::read(&path, &sealed_as, key, big.size, true).map(|d| d.len());
    assert_eq!(read(), Ok(f.big.len()));

    // The last chunk dropped, and the header's count left as it was.
    fs::write(&path, &original[..original.len() - 100]).unwrap();
    assert_eq!(read(), Err(VaultError::Damaged));
    // The first two chunks swapped: each is bound to its place.
    let mut swapped = original[..8].to_vec();
    swapped.extend_from_slice(&original[8 + chunk..8 + 2 * chunk]);
    swapped.extend_from_slice(&original[8..8 + chunk]);
    swapped.extend_from_slice(&original[8 + 2 * chunk..]);
    fs::write(&path, &swapped).unwrap();
    assert_eq!(read(), Err(VaultError::Damaged));
    // A chunk too many.
    let mut grown = original.clone();
    grown.extend_from_slice(&original[8..8 + chunk]);
    fs::write(&path, &grown).unwrap();
    assert_eq!(read(), Err(VaultError::Damaged));
    // An impossible chunk size.
    let mut header = original.clone();
    header[4..8].copy_from_slice(&u32::MAX.to_be_bytes());
    fs::write(&path, &header).unwrap();
    assert_eq!(read(), Err(VaultError::Damaged));
}

#[test]
fn any_range_of_a_chunked_file_reads_back() {
    let f = Fixture::new();
    let open = f.store.unlock_with_password(&f.password).unwrap();
    let big = open.list().files.iter().find(|i| i.name == "big.bin").unwrap();
    let sealed_as = big.sealed_as.unwrap();
    let reader = ChunkedReader::open(&f.store.blob(&sealed_as), open.item_key(&sealed_as).unwrap(), &sealed_as, big.size).unwrap();
    assert_eq!(reader.count(), 3);
    let mib = 1u64 << 20;
    for range in [0..10, mib - 5..mib + 5, 2 * mib - 1..2 * mib + 300_000, 0..f.big.len() as u64] {
        assert_eq!(*reader.read(range.clone()).unwrap(), f.big[range.start as usize..range.end as usize], "{range:?}");
    }
    // Past the end is clamped, as a player may ask.
    assert_eq!(reader.read(f.big.len() as u64 - 3..f.big.len() as u64 + 50).unwrap().len(), 3);
    assert!(reader.read(f.big.len() as u64 + 10..f.big.len() as u64 + 20).unwrap().is_empty());
}

#[test]
fn a_list_from_a_newer_stillroom_isnt_read() {
    let f = Fixture::new();
    let list = json!({"format": 5, "vault": {"anything": "new"}});
    write_list(&f.store, f.yours, &f.slot_key, &f.cover, &serde_json::to_vec(&list).unwrap());
    assert_eq!(f.store.unlock_with_password(&f.password).err(), Some(Error::Vault(VaultError::NewerVault)));
}

#[test]
fn a_list_naming_an_item_without_its_key_is_damaged() {
    let f = Fixture::new();
    let mut item = seal_thing(&f.store, &Thing::file("x", None, b"x".to_vec()));
    item.as_object_mut().unwrap().remove("key");
    let list = json!({"format": 4, "vault": {"files": [item], "folders": [], "showInCapture": false,
        "intruder": b64(&[5; 32]), "touchID": b64(&[0; 64]), "kitMade": "000000000000", "kitReminded": "000000000000"}});
    write_list(&f.store, f.yours, &f.slot_key, &f.cover, &serde_json::to_vec(&list).unwrap());
    assert_eq!(f.store.unlock_with_password(&f.password).err(), Some(Error::Vault(VaultError::Damaged)));
}

#[test]
fn a_list_with_files_must_be_wrapped() {
    let f = Fixture::new();
    let item = seal_thing(&f.store, &Thing::file("x", None, b"x".to_vec()));
    let bare = json!({"files": [item], "folders": [], "showInCapture": false,
        "intruder": b64(&[5; 32]), "touchID": b64(&[0; 64]), "kitMade": "000000000000", "kitReminded": "000000000000"});
    write_list(&f.store, f.yours, &f.slot_key, &f.cover, &serde_json::to_vec(&bare).unwrap());
    assert_eq!(f.store.unlock_with_password(&f.password).err(), Some(Error::Vault(VaultError::Damaged)));
}

#[test]
fn a_list_or_cover_key_moved_into_the_other_slot_doesnt_open() {
    let f = Fixture::new();
    let (mine, theirs) = (f.root().join(f.yours.letter()), f.root().join(other(f.yours).letter()));
    // Their list in my slot: it's bound to their letter, so my slot reads it as damaged.
    fs::copy(theirs.join("list"), mine.join("list")).unwrap();
    assert_eq!(f.store.unlock_with_password(&f.password).err(), Some(Error::Vault(VaultError::Damaged)));
    let cover = Store::at(f.root()).open_cover(f.yours, &f.slot_key).unwrap();
    assert!(f.store.read_covered(Covered::List, f.yours, &cover).is_none());
    // And their cover key in my slot: sealed with their slot key and letter.
    fs::copy(theirs.join("cover.key"), mine.join("cover.key")).unwrap();
    assert!(f.store.open_cover(f.yours, &f.slot_key).is_none());
}

#[test]
fn names_that_windows_wont_take_are_made_safe() {
    assert_eq!(safe("26\u{2215}10\u{2215}26"), "26-10-26");
    assert_eq!(safe("a/b:c"), "a-b-c");
    assert_eq!(safe("what? <yes> | \"no\" *"), "what- -yes- - -no- -");
    assert_eq!(safe("trailing dots..."), "trailing dots");
    assert_eq!(safe("  "), "Untitled");
    assert_eq!(safe(".."), "Untitled");
    assert_eq!(safe("CON"), "_CON");
    assert_eq!(safe("lpt1.txt"), "_lpt1.txt");
    // Windows 11 reserves COM0 and LPT0 too, and the superscript ports.
    assert_eq!(safe("COM0"), "_COM0");
    assert_eq!(safe("com¹.log"), "_com¹.log");
    assert_eq!(safe("LPT³"), "_LPT³");
    assert_eq!(safe("conin$"), "_conin$");
    assert_eq!(safe("CONOUT$.txt"), "_CONOUT$.txt");
    assert_eq!(safe("COM10"), "COM10");
    assert_eq!(safe("..\\..\\x.bat"), "..-..-x.bat");
    assert_eq!(safe("console"), "console");
    assert_eq!(safe("tab\there"), "tab-here");
}

#[test]
fn two_items_of_one_name_both_come_out() {
    let f = Fixture::new();
    let things = [Thing::file("same.txt", None, b"one".to_vec()), Thing::file("same.txt", None, b"two".to_vec())];
    let store = Store::at(f.dir.path().join("Two"));
    let cover = Key::random();
    write_slot(&store, Slot::A, &cover, "pw", "AAAAA", "kit", &things, &[]);
    write_slot(&store, Slot::B, &cover, "other", "BBBBB", "kit2", &[], &[]);
    let out = f.out("out-two");
    export(&store.unlock_with_password("pw").unwrap(), &out);
    assert_eq!(fs::read(out.join("same.txt")).unwrap(), b"one");
    assert_eq!(fs::read(out.join("same 2.txt")).unwrap(), b"two");
}

/// The test vault written to disk in the layout of the Mac's `writesFormatFixture` (vault/, source/, answers.json),
/// so tools/stillroom-open.py and the stillroom-open binary can be run against it. Only runs when asked:
/// `STILLROOM_FIXTURE_DIR=<empty folder> cargo test --test read_path writes_format_fixture`.
#[test]
fn writes_format_fixture() {
    let Some(dir) = std::env::var_os("STILLROOM_FIXTURE_DIR") else { return };
    let dir = std::path::PathBuf::from(dir);
    let f = Fixture::new();
    copy_tree(f.root(), &dir.join("vault"));
    let source = dir.join("source");
    fs::create_dir_all(source.join("Taxes/2025")).unwrap();
    fs::write(source.join("Taxes/2025/w2.txt"), &f.w2).unwrap();
    fs::write(source.join("photo.bin"), &f.photo).unwrap();
    fs::write(source.join("big.bin"), &f.big).unwrap();
    let answers = json!({
        "password": f.password, "recovery": f.recovery, "pieces": f.pieces, "decoy": f.decoy,
        "secretLines": ["Bank: First Savings", "Password: hunter2: with a colon"],
    });
    fs::write(dir.join("answers.json"), serde_json::to_vec_pretty(&answers).unwrap()).unwrap();
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

#[test]
fn an_empty_file_and_an_empty_chunked_file_come_out_empty() {
    let f = Fixture::new();
    let things = [
        Thing::file("empty", None, vec![]),
        Thing { chunked: Some(1 << 20), ..Thing::file("empty-streamed", None, vec![]) },
        Thing { chunked: Some(4096), ..Thing::file("small-chunks", None, bytes(1, 10_000)) },
    ];
    let store = Store::at(f.dir.path().join("Empty"));
    let cover = Key::random();
    write_slot(&store, Slot::A, &cover, "pw", "AAAAA", "kit", &things, &[]);
    write_slot(&store, Slot::B, &cover, "other", "BBBBB", "kit2", &[], &[]);
    let out = f.out("out-empty");
    let report = export(&store.unlock_with_password("pw").unwrap(), &out);
    assert_eq!((report.taken, report.failed.len()), (3, 0));
    assert_eq!(fs::read(out.join("empty")).unwrap(), b"");
    assert_eq!(fs::read(out.join("empty-streamed")).unwrap(), b"");
    assert_eq!(fs::read(out.join("small-chunks")).unwrap(), bytes(1, 10_000));
}

#[test]
fn printing_an_open_list_shows_no_keys_or_secrets() {
    let f = Fixture::new();
    let open = f.store.unlock_with_password(&f.password).unwrap();
    let printed = format!("{:?}", open.list());
    assert!(!open.list().intruder.is_empty() && !printed.contains(&open.list().intruder));
    assert!(printed.contains("Item") && !printed.contains("key:"));
    let secret: stillroom_core::list::Secret =
        serde_json::from_value(json!({"fields": [{"label": "Password", "value": "hunter2", "concealed": true}]})).unwrap();
    assert!(!format!("{secret:?}").contains("hunter2"));
}
