//! The words only Windows can read (a PDF's, a picture's) are read by the app with the vault free, not inside an
//! engine call: a long reading would otherwise keep the vault from locking. The engine lists what's wanted
//! (`search_wanting`), the app gives the words back (`set_words`), and they're sealed and found like any others.

mod common;

use common::{sample, store_in};
use stillroom_core::search::Entry;
use stillroom_core::vault::Vault;
use tempfile::TempDir;

const PASSWORD: &str = "correct horse battery staple";

fn made() -> (TempDir, Vault) {
    let dir = tempfile::tempdir().unwrap();
    let (vault, _) = store_in(dir.path()).create(PASSWORD).unwrap();
    (dir, vault)
}

fn entry(vault: &Vault, id: &uuid::Uuid, text: &str) -> Entry {
    let item = vault.item(id).unwrap();
    Entry { changed: item.changed_at(), size: item.size, text: text.into() }
}

#[test]
fn pictures_and_pdfs_wait_for_the_app_and_are_found_once_read() {
    let (dir, mut vault) = made();
    let files = [
        sample(dir.path(), "receipt.png", b"\x89PNG not really"),
        sample(dir.path(), "lease.pdf", b"%PDF-1.4 not really"),
        sample(dir.path(), "notes.txt", b"plain words"),
    ];
    let added = vault.add(&files, None);
    assert!(added.failed.is_empty());
    let (picture, pdf, text) = (added.items[0], added.items[1], added.items[2]);

    // Without a reader, the text file is read and the other two are left: not recorded as having no words.
    assert!(vault.refresh_search(None).unwrap());
    assert_eq!(vault.search("plain").len(), 1);
    let mut wanted: Vec<_> = vault.search_wanting().iter().map(|i| i.id).collect();
    wanted.sort();
    let mut expected = vec![picture, pdf];
    expected.sort();
    assert_eq!(wanted, expected);
    assert!(!vault.refresh_search(None).unwrap(), "nothing more to read without the app");

    let words = vec![(picture, entry(&vault, &picture, "TOTAL 42.00 Café")), (pdf, entry(&vault, &pdf, ""))];
    vault.set_words(words).unwrap();
    assert!(vault.search_wanting().is_empty(), "an empty reading counts: it isn't asked for again");
    assert_eq!(vault.search("café"), [picture]);
    assert_eq!(vault.snippet(&picture, "42"), Some("TOTAL 42.00 Café".into()));
    assert!(vault.search("not really").is_empty());
    assert_eq!(vault.search("plain"), [text]);

    // Sealed: a fresh unlock finds them without reading again.
    let store = store_in(dir.path());
    drop(vault);
    let reopened = store.unlock_with_password(PASSWORD).unwrap();
    assert_eq!(reopened.search("café"), [picture]);
    assert!(reopened.search_wanting().is_empty());
}

#[test]
fn words_read_before_a_change_or_for_an_item_gone_dont_stick() {
    let (dir, mut vault) = made();
    let added = vault.add(&[sample(dir.path(), "a.jpg", b"one"), sample(dir.path(), "b.jpg", b"two")], None);
    let (kept, gone) = (added.items[0], added.items[1]);
    let stale = Entry { changed: -1.0, ..entry(&vault, &kept, "old words") };
    let removed = entry(&vault, &gone, "gone words");
    vault.delete(&gone).unwrap();
    vault.set_words(vec![(kept, stale), (gone, removed)]).unwrap();
    // Recorded, but against a different date: wanted again, and the vanished item isn't searchable.
    assert_eq!(vault.search_wanting().iter().map(|i| i.id).collect::<Vec<_>>(), [kept]);
    assert!(vault.search("gone words").is_empty());
}
