//! Windows Hello's way in, with a stand-in for Windows Hello: like Hello's RSA signature it's deterministic (one
//! challenge, one signature, always) and only "this device" can make it. Everything the engine does with a signature
//! is checked; the real Windows Hello prompt is the app's, tested where Hello is set up.

mod common;

use std::fs;

use common::store_in;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use stillroom_core::vault::{Store, Vault};
use stillroom_core::{Error, VaultError};

const REAL: &str = "real password 123";
const DECOY: &str = "decoy password 456";

/// The stand-in: a device's signature of a challenge.
fn sign(device: &[u8], challenge: &[u8]) -> Vec<u8> {
    let mut mac = Hmac::<Sha256>::new_from_slice(device).unwrap();
    mac.update(challenge);
    mac.finalize().into_bytes().to_vec()
}

const DEVICE: &[u8] = b"this pc's windows hello";
const PUBLIC_KEY: &[u8] = b"the credential's public key";

fn turn_on(vault: &mut Vault, device: &[u8], public_key: &[u8]) {
    let challenge = Vault::hello_new_challenge();
    vault.turn_on_hello(&challenge, &sign(device, &challenge), public_key).unwrap();
}

fn unlock(store: &Store, device: &[u8]) -> Result<Vault, Error> {
    let challenge = store.hello_challenge()?;
    store.unlock_with_hello(&sign(device, &challenge))
}

#[test]
fn hello_opens_the_vault_that_turned_it_on() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (mut vault, _) = store.create(REAL).unwrap();
    let mine = vault.slot();
    let note = vault.new_entry(stillroom_core::list::Entry::Note, "Plans", b"by hello", None).unwrap();
    vault.set_other_slot(DECOY).unwrap();
    assert!(!vault.hello_is_mine());
    turn_on(&mut vault, DEVICE, PUBLIC_KEY);
    assert!(vault.hello_is_mine() && store.hello_key().exists());
    drop(vault);

    let vault = unlock(&store, DEVICE).unwrap();
    assert_eq!(vault.slot(), mine);
    assert!(!vault.must_set_password(), "Hello is a way in like the password");
    assert_eq!(*vault.read(&note).unwrap(), b"by hello");
    // Another device's signature (Hello set up again) opens nothing.
    assert_eq!(unlock(&store, b"some other pc").err(), Some(Error::Vault(VaultError::HelloChanged)));
    assert_eq!(store.unlock_with_hello(&[]).err(), Some(Error::Vault(VaultError::HelloChanged)));
}

/// Like Touch ID, a face or a finger can't choose a vault: Hello opens whichever turned it on last.
#[test]
fn hello_moves_to_the_vault_that_last_turned_it_on() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (mut vault, _) = store.create(REAL).unwrap();
    let mine = vault.slot();
    vault.set_other_slot(DECOY).unwrap();
    turn_on(&mut vault, DEVICE, PUBLIC_KEY);
    drop(vault);

    let mut decoy = store.unlock_with_password(DECOY).unwrap();
    assert!(!decoy.hello_is_mine());
    turn_on(&mut decoy, DEVICE, b"a newer credential");
    drop(decoy);
    assert_eq!(unlock(&store, DEVICE).unwrap().slot(), mine.other());
    assert!(!store.unlock_with_password(REAL).unwrap().hello_is_mine());
}

#[test]
fn turned_off_hello_opens_nothing() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (mut vault, _) = store.create(REAL).unwrap();
    turn_on(&mut vault, DEVICE, PUBLIC_KEY);
    vault.turn_off_hello().unwrap();
    assert!(!vault.hello_is_mine() && !store.hello_key().exists());
    drop(vault);
    assert_eq!(store.hello_challenge().err(), Some(Error::NotFound));
    assert_eq!(store.unlock_with_hello(b"anything").err(), Some(Error::NotFound));
}

/// Replacing the vault Hello opens takes Hello with it: it would open nothing.
#[test]
fn replacing_the_vault_hello_opens_takes_hello_with_it() {
    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (mut vault, _) = store.create(REAL).unwrap();
    vault.set_other_slot(DECOY).unwrap();
    drop(vault);
    let mut decoy = store.unlock_with_password(DECOY).unwrap();
    turn_on(&mut decoy, DEVICE, PUBLIC_KEY);
    drop(decoy);
    let mut vault = store.unlock_with_password(REAL).unwrap();
    vault.set_other_slot("a new decoy 789").unwrap();
    assert!(!store.hello_key().exists());
    // Replacing the other vault while Hello is this one's keeps it.
    turn_on(&mut vault, DEVICE, PUBLIC_KEY);
    vault.reset_other_slot().unwrap();
    assert!(vault.hello_is_mine());
}

/// A list the Mac wrote has no "hello" field: it reads as Hello off. And Hello is the Windows counterpart of Touch ID,
/// so the Mac's touchID field is left exactly as it was.
#[test]
fn a_list_the_mac_wrote_reads_as_hello_off() {
    let fixture = Store::at(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vault")).read_only();
    let vault = fixture.unlock_with_password("fixture password one").unwrap();
    assert!(!vault.hello_is_mine());
    assert_eq!(vault.list().hello, stillroom_core::hello::none());

    let dir = tempfile::tempdir().unwrap();
    let store = store_in(dir.path());
    let (mut vault, _) = store.create(REAL).unwrap();
    let touch_id = vault.list().touch_id.clone();
    turn_on(&mut vault, DEVICE, PUBLIC_KEY);
    assert_eq!(vault.list().touch_id, touch_id);
    assert!(fs::read_to_string(store.hello_key()).unwrap().contains("\"publicKey\""));
}
