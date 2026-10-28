//! The fixes from the October 2026 code review, as the Mac's ReviewFixTests check them, and their Windows
//! counterparts: web pages and programs never open in place, inline pictures are capped, a doctored cover length is
//! refused, new passwords checked against the other slot count as tries, exported files carry the Mark of the Web, and
//! a backup or restore of an open vault can't race a save.

mod common;

use std::fs;
use std::time::UNIX_EPOCH;

use common::{sample, store_in};
use stillroom_core::crypto::{bound, seal, Key};
use stillroom_core::email;
use stillroom_core::kinds::{can_edit, uti_for_name};
use stillroom_core::vault::{Covered, Slot};
use stillroom_core::{backup, Error, VaultError};

#[test]
fn web_pages_and_programs_never_open_in_place() {
    for (name, uti) in [
        ("page.html", "public.html"),
        ("page.xhtml", "public.xhtml"),
        ("feed.xml", "public.xml"),
        ("logo.svg", "public.svg-image"),
        ("saved.webarchive", "com.apple.webarchive"),
        ("setup.exe", "public.data"),
        ("run.bat", "public.data"),
        ("script.ps1", "public.data"),
        ("shortcut.lnk", "public.data"),
        ("site.url", "public.data"),
        // A program renamed: its recorded kind says it runs.
        ("invoice.pdf", "com.microsoft.windows-executable"),
        // A document renamed to run: its name says so.
        ("invoice.pdf.exe", "com.adobe.pdf"),
        ("no extension", "public.plain-text"),
        (".txt", "public.plain-text"),
    ] {
        assert!(!can_edit(uti, name, true), "{name} must not open in place");
    }
    // Ordinary documents still do.
    for name in ["w2.pdf", "notes.txt", "letter.docx", "budget.xlsx", "photo.jpg", "clip.mp4", "song.mp3"] {
        assert!(can_edit(uti_for_name(name), name, true), "{name} should open in place");
    }
    // Notes and secrets never do.
    assert!(!can_edit("net.daringfireball.markdown", "Plans.md", false));
}

#[test]
fn inline_pictures_are_capped() {
    let pictures: String = (0..300)
        .map(|i| format!("--b\r\nContent-Type: image/png\r\nContent-ID: <p{i}>\r\nContent-Transfer-Encoding: base64\r\n\r\nAA==\r\n"))
        .collect();
    let text = format!(
        "From: a@example.com\r\nSubject: many\r\nContent-Type: multipart/related; boundary=\"b\"\r\n\r\n\
         --b\r\nContent-Type: text/html\r\n\r\n<img src=\"cid:p0\">\r\n{pictures}--b--\r\n"
    );
    let email = email::parse(text.as_bytes()).unwrap();
    assert_eq!(email.inline.len(), 256);
    // The rest aren't lost: they're listed as attachments.
    assert_eq!(email.attachments.len(), 44);
    assert!(!email.page().contains("cid:p0"));
}

#[test]
fn a_doctored_cover_length_is_refused_not_a_crash() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let cover = Key::random();
    // A length with the top bit set: read as a signed number it turned negative and crashed the Mac app.
    let mut inner = vec![0x80, 0, 0, 0, 0, 0, 0, 1];
    inner.extend([0u8; 64]);
    fs::create_dir_all(store.slot_folder(Slot::A)).unwrap();
    fs::write(store.slot_file(Slot::A, "list"), seal(&inner, &cover, Some(&bound::cover("list", "a"))).unwrap()).unwrap();
    assert!(store.read_covered(Covered::List, Slot::A, &cover).is_none());
}

/// Checking a new password against the other slot answers a guess at that slot's password, so each check counts as a
/// wrong try: the first three are free, then each waits longer. A good unlock at the lock screen clears it.
#[test]
fn password_checks_against_the_other_slot_count_as_tries() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (mut vault, _) = store.create("real password 123").unwrap();
    for n in 0..4 {
        vault.set_other_slot(&format!("decoy number {n}")).unwrap();
    }
    assert_eq!(vault.set_other_slot("decoy number 4").err(), Some(Error::Vault(VaultError::TooSoon)));
    assert_eq!(vault.change_password("real password 123", "another one").err(), Some(Error::Vault(VaultError::TooSoon)));
    assert!(store.try_limit().wait_left() > 0);
    // Kept beside the vault, not in it: never in a backup, and it says nothing about either slot.
    assert!(dir.path().join("tries.json").exists() && !store.root().join("tries.json").exists());
    store.try_limit().succeeded();
    vault.set_other_slot("decoy number 4").unwrap();
}

/// Everything taken out is marked as downloaded (the Windows counterpart of the Mac's quarantine), and keeps its dates.
#[test]
fn exported_files_carry_the_mark_of_the_web_and_their_dates() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (mut vault, _) = store.create("real password 123").unwrap();
    let id = vault.add(&[sample(dir.path(), "setup.exe", b"MZ not really")], None).items[0];
    let modified = vault.item(&id).unwrap().shown_date();
    let out = dir.path().join("setup.exe");
    vault.export_item(&id, &out).unwrap();
    let mark = fs::read_to_string(format!("{}:Zone.Identifier", out.display())).unwrap();
    assert!(mark.contains("ZoneId=3"), "{mark}");
    let seconds = fs::metadata(&out).unwrap().modified().unwrap().duration_since(UNIX_EPOCH).unwrap().as_secs_f64();
    assert!((seconds - (modified + stillroom_core::APPLE_EPOCH)).abs() < 1.0, "marking it didn't change its date");
}

/// A backup of an open vault holds it borrowed, so no save lands while it's packed; a restore gives the vault up first.
#[test]
fn a_backup_and_restore_of_an_open_vault() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (mut vault, _) = store.create("real password 123").unwrap();
    vault.add(&[sample(dir.path(), "first.txt", b"first")], None);
    let file = dir.path().join("open.stillroombackup");
    vault.backup(&file).unwrap();
    backup::check(&file).unwrap();
    vault.add(&[sample(dir.path(), "second.txt", b"second")], None);
    assert_eq!(vault.files().len(), 2);

    let aside = vault.restore_backup(&file).unwrap();
    assert!(aside.is_some());
    let vault = store.unlock_with_password("real password 123").unwrap();
    assert_eq!(vault.files().iter().map(|i| i.name.as_str()).collect::<Vec<_>>(), ["first.txt"]);
}
