//! The licence and the free tier, as the Mac's LicenseTests and DecoyTests check them: a pure parser plus Ed25519,
//! 25 items without a licence with only adding ever stopping, and nothing in either that tells one vault from the
//! other. Every key here is signed by a test pair, never the production one.

mod common;

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use common::{sample, store_in};
use ed25519_dalek::{Signer, SigningKey, VerifyingKey};
use serde_json::Value;
use stillroom_core::export::export_all;
use stillroom_core::import;
use stillroom_core::licence::{self, check, full_message, Edition, Licence, Problem, FREE_ITEMS};
use stillroom_core::list::Entry;
use stillroom_core::session::Contents;
use stillroom_core::vault::{Store, Vault};
use stillroom_core::{backup, Error};
use tempfile::TempDir;

const PAYLOAD: &str = r#"{"v":1,"id":"txn_1","edition":"personal","seats":1,"name":"Ana Buyer","email":"ana@example.com","issued":"2026-10-28"}"#;
const PASSWORD: &str = "real password 123";
const DECOY: &str = "decoy password 456";

fn pair(seed: u8) -> SigningKey {
    SigningKey::from_bytes(&[seed; 32])
}

/// A key as the website's signer writes it (website/server/licence.ts), signed here by `key`.
fn mint(json: &str, key: &SigningKey, version: &str) -> String {
    let signed = format!("{version}.{}", URL_SAFE_NO_PAD.encode(json));
    let signature = key.sign(signed.as_bytes());
    format!("{signed}.{}", URL_SAFE_NO_PAD.encode(signature.to_bytes()))
}

fn checked(typed: &str, signer: &SigningKey) -> Result<Licence, Problem> {
    check(typed, Some(&signer.verifying_key()), &[])
}

fn ana() -> Licence {
    Licence {
        id: "txn_1".into(),
        edition: Edition::Personal,
        seats: 1,
        name: "Ana Buyer".into(),
        email: "ana@example.com".into(),
        issued: "2026-10-28".into(),
    }
}

// MARK: The check

#[test]
fn a_good_key_checks_out() {
    let key = pair(1);
    assert_eq!(checked(&mint(PAYLOAD, &key, "SR1"), &key), Ok(ana()));
}

/// Mail apps wrap long lines and people paste with spaces around: all of it is taken out.
#[test]
fn spaces_and_line_breaks_dont_matter() {
    let key = pair(1);
    let minted = mint(PAYLOAD, &key, "SR1");
    let wrapped: String = minted.chars().enumerate().map(|(i, c)| if i % 40 == 39 { format!("{c}\r\n") } else { c.to_string() }).collect();
    assert_eq!(checked(&format!("  {wrapped} \n"), &key).unwrap().name, "Ana Buyer");
}

#[test]
fn a_changed_payload_is_refused() {
    let key = pair(1);
    let minted = mint(PAYLOAD, &key, "SR1");
    let signature = minted.split('.').nth(2).unwrap();
    let more = URL_SAFE_NO_PAD.encode(PAYLOAD.replace(r#""seats":1"#, r#""seats":500"#));
    assert_eq!(checked(&format!("SR1.{more}.{signature}"), &key), Err(Problem::NotSigned));
}

#[test]
fn a_changed_signature_is_refused() {
    let key = pair(1);
    let minted = mint(PAYLOAD, &key, "SR1");
    let parts: Vec<&str> = minted.split('.').collect();
    let mut signature: Vec<char> = parts[2].chars().collect();
    signature[10] = if signature[10] == 'A' { 'B' } else { 'A' };
    let typed = format!("{}.{}.{}", parts[0], parts[1], signature.into_iter().collect::<String>());
    assert_eq!(checked(&typed, &key), Err(Problem::NotSigned));
}

#[test]
fn a_key_from_another_pair_is_refused() {
    assert_eq!(checked(&mint(PAYLOAD, &pair(2), "SR1"), &pair(1)), Err(Problem::NotSigned));
    // And against the real key built in, a test key never checks out.
    let real = licence::built_in().expect("the production public key is a valid Ed25519 key");
    assert_eq!(check(&mint(PAYLOAD, &pair(1), "SR1"), Some(&real), &[]), Err(Problem::NotSigned));
    // No signer at all trusts nothing.
    assert_eq!(check(&mint(PAYLOAD, &pair(1), "SR1"), None, &[]), Err(Problem::NotSigned));
}

#[test]
fn truncated_or_garbled_input_is_refused() {
    let key = pair(1);
    let minted = mint(PAYLOAD, &key, "SR1");
    let payload = minted.split('.').nth(1).unwrap();
    for typed in [
        String::new(),
        "hello".into(),
        "SR1".into(),
        "SR1..".into(),
        "SR1.a.b".into(),
        "SR1.a.b.c".into(),
        minted[..minted.len() - 8].into(),
        minted[6..].into(),
        minted.replace('.', ","),
        format!("{minted}="),
        format!("{}/{}", &minted[..10], &minted[10..]),
        format!("SR1.{payload}."),
        "A".repeat(5000),
    ] {
        assert_eq!(checked(&typed, &key), Err(Problem::Malformed), "{}", &typed[..typed.len().min(30)]);
    }
    // Signed, but not what the signer writes: unknown edition, no seats, not JSON.
    for json in [PAYLOAD.replace("personal", "gold"), PAYLOAD.replace(r#""seats":1"#, r#""seats":0"#), r#"{"v":1}"#.into(), "not json".into()] {
        assert_eq!(checked(&mint(&json, &key, "SR1"), &key), Err(Problem::Malformed), "{json}");
    }
}

#[test]
fn an_unknown_version_is_refused() {
    let key = pair(1);
    assert_eq!(checked(&mint(PAYLOAD, &key, "SR2"), &key), Err(Problem::NewerVersion));
    assert_eq!(checked(&mint(&PAYLOAD.replace(r#""v":1"#, r#""v":2"#), &key, "SR1"), &key), Err(Problem::NewerVersion));
    assert_eq!(checked(&mint(PAYLOAD, &key, "XX1"), &key), Err(Problem::Malformed));
}

/// A key posted publicly is refused once its id is on the blocked list; every other key still checks out.
#[test]
fn a_blocked_key_is_refused() {
    let key = pair(1);
    let minted = mint(PAYLOAD, &key, "SR1");
    assert_eq!(check(&minted, Some(&key.verifying_key()), &["txn_1"]), Err(Problem::Blocked));
    assert_eq!(check(&minted, Some(&key.verifying_key()), &["txn_other"]).unwrap().id, "txn_1");
}

/// The Windows list matches the Mac's, so a key turned off there is turned off here.
#[test]
fn the_blocked_list_and_public_key_match_the_macs() {
    let swift = fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("../../macos/Sources/Stillroom/Security/License.swift")).unwrap();
    assert!(swift.contains(&format!("static let publicKey = \"{}\"", licence::PUBLIC_KEY)), "the public key differs from the Mac's");
    let mac_blocked = swift.lines().find(|l| l.contains("static let blocked")).unwrap();
    let quoted: Vec<&str> = mac_blocked.split('"').skip(1).step_by(2).collect();
    assert_eq!(quoted, licence::BLOCKED, "the blocked list differs from the Mac's");
    assert!(swift.contains(&format!("static let freeItems = {FREE_ITEMS}")));
}

/// A key minted by the website's Node signer (website/server/fixtures/test-licence.json, checked on that side by
/// signer.test.ts) checks out here, accents and all: the signer, the Mac and Windows can't drift apart.
#[test]
fn a_node_minted_key_verifies() {
    let fixture: Value = serde_json::from_slice(&node_fixture()).unwrap();
    let public: [u8; 32] = STANDARD.decode(fixture["publicKey"].as_str().unwrap()).unwrap().try_into().unwrap();
    let signer = VerifyingKey::from_bytes(&public).unwrap();
    let found = check(fixture["key"].as_str().unwrap(), Some(&signer), &[]).unwrap();
    assert_eq!(
        found,
        Licence {
            id: "txn_01test0000000000000000000".into(),
            edition: Edition::Family,
            seats: 5,
            name: "Zoë Ångström-Test".into(),
            email: "zoe@example.com".into(),
            issued: "2026-10-28".into(),
        }
    );
    assert_eq!(checked(fixture["key"].as_str().unwrap(), &pair(1)), Err(Problem::NotSigned));
}

fn node_fixture() -> Vec<u8> {
    fs::read(Path::new(env!("CARGO_MANIFEST_DIR")).join("../../website/server/fixtures/test-licence.json")).unwrap()
}

// MARK: The free tier

/// A store trusting the test pair, as the Mac's tests set `License.signerForTests`.
fn made() -> (TempDir, Store, Vault) {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path()).trusting_licences_from(pair(9).verifying_key().to_bytes());
    let (vault, _) = store.create(PASSWORD).unwrap();
    (dir, store, vault)
}

fn test_licence() -> String {
    mint(PAYLOAD, &pair(9), "SR1")
}

fn fill(vault: &mut Vault, dir: &TempDir, to: usize) {
    let paths: Vec<PathBuf> = (vault.files().len()..to).map(|i| sample(dir.path(), &format!("item {i}.txt"), format!("item {i}").as_bytes())).collect();
    let added = vault.add(&paths, None);
    assert!(added.failed.is_empty() && added.refused == 0, "{:?}", added.failed);
    assert_eq!(vault.files().len(), to);
}

fn logins() -> Vec<import::Login> {
    import::logins(b"Title,URL,Username,Password\nA,https://a.com,me,1\nB,https://b.com,me,2\n").unwrap()
}

#[test]
fn the_twenty_sixth_item_needs_a_licence() {
    let (dir, store, mut vault) = made();
    assert_eq!(store.licence(), None);
    fill(&mut vault, &dir, 20);

    // Ten dropped at once: five fit, and only their originals may be removed.
    let ten: Vec<PathBuf> = (0..10).map(|i| sample(dir.path(), &format!("more {i}.txt"), b"more")).collect();
    let added = vault.add(&ten, None);
    assert_eq!((vault.files().len(), added.items.len(), added.originals.files.len(), added.refused), (25, 5, 5, 5));
    assert_eq!(vault.room(), 0);
    assert_eq!(Error::Full(5).to_string(), full_message(5));

    // Every other way in stops too, and says why.
    assert_eq!(vault.add(&[sample(dir.path(), "one more.txt", b"x")], None).refused, 1);
    assert_eq!(vault.new_entry(Entry::Note, "Note", b"", None).err(), Some(Error::Full(1)));
    assert_eq!(vault.add_data(b"scan", "Scan.pdf", None).err(), Some(Error::Full(1)));
    assert_eq!(vault.import_logins(&logins()).unwrap(), (0, 0, 2));
    assert_eq!(vault.files().len(), 25);
    // Folders don't count.
    vault.make_folder("Empty", None).unwrap();
    assert!(vault.folders().contains(&"Empty".to_owned()));

    // A licence lifts it at once, and is still there after locking and opening again.
    store.add_licence(&test_licence()).unwrap();
    vault.new_entry(Entry::Note, "Note", b"", None).unwrap();
    assert_eq!(vault.add(&[sample(dir.path(), "twenty-seventh.txt", b"x")], None).refused, 0);
    assert_eq!(vault.import_logins(&logins()).unwrap(), (2, 0, 0));
    assert_eq!(vault.files().len(), 29);
    drop(vault);
    let mut again = store.unlock_with_password(PASSWORD).unwrap();
    assert_eq!(store.licence().unwrap().name, "Ana Buyer");
    again.add_data(b"scan", "Scan.pdf", None).unwrap();
    assert_eq!(again.files().len(), 30);

    // Removed, the limit is back; nothing in the vault is touched.
    store.remove_licence().unwrap();
    assert_eq!(store.licence(), None);
    assert_eq!(again.new_entry(Entry::Note, "Note", b"", None).err(), Some(Error::Full(1)));
    assert_eq!(again.files().len(), 30);
    // Removing it twice is fine.
    store.remove_licence().unwrap();
}

/// A key that doesn't check out is never kept.
#[test]
fn a_bad_key_is_refused_and_not_kept() {
    let (_dir, store, _vault) = made();
    assert_eq!(store.add_licence(&mint(PAYLOAD, &pair(2), "SR1")).err(), Some(Error::Licence(Problem::NotSigned)));
    assert_eq!(store.add_licence("SR1.nonsense").err(), Some(Error::Licence(Problem::Malformed)));
    assert!(!store.licence_file().exists());
    // One the built-in key didn't sign doesn't load, and says why.
    fs::write(store.licence_file(), mint(PAYLOAD, &pair(2), "SR1")).unwrap();
    assert_eq!((store.licence(), store.licence_problem()), (None, Some(Problem::NotSigned)));
}

/// Over the limit, everything but adding works: opening, editing (and the versions it makes), moving, renaming,
/// deleting, exporting, backing up, restoring a backup of more than 25 items, checking.
#[test]
fn over_the_limit_nothing_but_adding_stops() {
    let (dir, store, mut vault) = made();
    store.add_licence(&test_licence()).unwrap();
    let note = vault.new_entry(Entry::Note, "Plans", b"first", None).unwrap();
    fill(&mut vault, &dir, 30);
    store.remove_licence().unwrap();
    assert_eq!(vault.room(), 0);

    // Edit, with a version kept, and put back.
    vault.backdate_for_tests(&note, 3600.0).unwrap();
    vault.update(&note, Contents::Bytes(b"second"), None).unwrap();
    assert_eq!(*vault.read(&note).unwrap(), b"second");
    let version = vault.item(&note).unwrap().versions.as_ref().unwrap()[0].id;
    vault.restore_version(&note, &version).unwrap();
    // Move, rename, tag, delete.
    vault.make_folder("Old", None).unwrap();
    let three: Vec<_> = vault.files()[..3].iter().map(|i| i.id).collect();
    vault.move_items(&three, Some("Old")).unwrap();
    assert_eq!(vault.files().iter().filter(|i| i.folder.as_deref() == Some("Old")).count(), 3);
    let (fifth, sixth, seventh) = (vault.files()[5].id, vault.files()[6].id, vault.files()[7].id);
    vault.rename(&fifth, "Renamed.txt").unwrap();
    vault.set_tags(&sixth, &["kept".into()]).unwrap();
    vault.delete(&seventh).unwrap();
    assert_eq!(vault.files().len(), 29);
    // Still over 25 after a delete: adding still stops.
    assert_eq!(vault.new_entry(Entry::Note, "Note", b"", None).err(), Some(Error::Full(1)));

    // Export one, export everything, check.
    let out = tempfile::tempdir().unwrap();
    vault.export_item(&vault.files()[0].id.clone(), &out.path().join("one.txt")).unwrap();
    let (_, report) = export_all(&vault, out.path(), |_| {}).unwrap();
    assert_eq!((report.taken, report.failed.len()), (29, 0));
    assert!(vault.check(|_, _| {}).is_empty());

    // Back up, then restore over a vault that's gone: all 29 come back, unlicensed.
    let file = out.path().join("backup.stillroombackup");
    vault.backup(&file).unwrap();
    vault.wipe().unwrap();
    assert_eq!(backup::restore(&store, &file).unwrap(), None);
    let restored = store.unlock_with_password(PASSWORD).unwrap();
    assert_eq!(restored.files().len(), 29);
    assert_eq!(store.licence(), None);
    // The version put back before the backup is what it holds.
    assert_eq!(*restored.read(&note).unwrap(), b"first");
}

/// The licence and the free tier tell nothing: the limit stops both vaults at the same count with the same words,
/// a licence added in either lifts it in both, and adding or removing one writes nothing in the vault folder.
#[test]
fn the_licence_and_the_limit_are_the_same_in_either_vault() {
    let (dir, store, mut vault) = made();
    vault.set_other_slot(DECOY).unwrap();
    drop(vault);

    // What each vault does when full: its room, and what adding by every way says.
    let probe = |password: &str| -> Vec<String> {
        let mut open = store.unlock_with_password(password).unwrap();
        let to = open.files().len().max(FREE_ITEMS);
        fill(&mut open, &dir, to);
        let mut said = vec![if open.room() == usize::MAX { "unlimited".into() } else { open.room().to_string() }];
        let added = open.add(&[sample(dir.path(), "extra.txt", b"x")], None);
        said.push(if added.refused > 0 { full_message(added.refused) } else { "added".into() });
        said.push(match open.new_entry(Entry::Note, "Note", b"", None) {
            Ok(_) => "added".into(),
            Err(error) => error.to_string(),
        });
        said
    };

    let without = (probe(PASSWORD), probe(DECOY));
    assert_eq!(without.0, without.1);
    assert_eq!(without.0, ["0".to_owned(), full_message(1), full_message(1)]);

    // Added from the decoy, it lifts the limit in both; the vault folder doesn't change by a byte.
    let decoy = store.unlock_with_password(DECOY).unwrap();
    let before = listing(store.root());
    store.add_licence(&test_licence()).unwrap();
    assert_eq!(listing(store.root()), before);
    drop(decoy);
    assert!(!store.licence_file().starts_with(store.root()));

    let with = (probe(PASSWORD), probe(DECOY));
    assert_eq!(with.0, with.1);
    assert_eq!(with.0, ["unlimited", "added", "added"]);

    let before = listing(store.root());
    store.remove_licence().unwrap();
    assert_eq!(listing(store.root()), before);
    assert_eq!(probe(DECOY), probe(PASSWORD));
}

/// Every file in the vault folder with its size and contents' length.
fn listing(root: &Path) -> BTreeMap<String, u64> {
    fn walk(root: &Path, folder: &Path, found: &mut BTreeMap<String, u64>) {
        for entry in fs::read_dir(folder).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                walk(root, &path, found);
            } else {
                found.insert(path.strip_prefix(root).unwrap().to_string_lossy().into(), fs::metadata(&path).unwrap().len());
            }
        }
    }
    let mut found = BTreeMap::new();
    walk(root, root, &mut found);
    found
}

/// Adding the folder that holds the vault never seals the licence in, nor offers it as an original to delete.
#[test]
fn the_licence_is_never_added_into_the_vault() {
    let (dir, store, mut vault) = made();
    store.add_licence(&test_licence()).unwrap();
    let added = vault.add(&[dir.path().to_path_buf()], None);
    assert!(!vault.files().iter().any(|i| i.name.ends_with("License")), "{:?}", vault.files().iter().map(|i| &i.name).collect::<Vec<_>>());
    assert!(!added.originals.files.iter().any(|p| p.ends_with("License")));
}
