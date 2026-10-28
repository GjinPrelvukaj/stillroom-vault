//! A test vault, written straight from docs/FORMAT.md, like the one the Mac app's `writesFormatFixture` makes:
//! folders, a file in chunks, a note, a secret, a recovery key, an emergency kit and a decoy holding a note.
//!
//! This only stands in until a vault written by the Mac app itself is in the tests: it shows the reader follows the
//! format as written down, not that the Mac app writes what's written down.

#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};

use base64::Engine as _;
use serde_json::{json, Value};
use stillroom_core::blob::{chunk_binding, chunk_count};
use stillroom_core::crypto::{bound, normalized_recovery_code, padded_length, seal, seal_with_password, Key, PasswordCost};
use stillroom_core::kit;
use stillroom_core::vault::{Slot, Store};
use tempfile::TempDir;
use uuid::Uuid;

/// Low enough to keep the tests quick, as the Mac tests turn `PasswordCost.current` down.
pub const QUICK: PasswordCost = PasswordCost { memory_kib: 64, passes: 1, lanes: 1 };

/// Seconds between 1970 and 2001.
pub const APPLE_EPOCH: i64 = 978_307_200;

pub struct Fixture {
    pub dir: TempDir,
    pub store: Store,
    /// Which slot is yours; the decoy is the other.
    pub yours: Slot,
    pub password: String,
    pub recovery: String,
    pub pieces: Vec<String>,
    pub decoy: String,
    pub w2: Vec<u8>,
    pub photo: Vec<u8>,
    pub big: Vec<u8>,
    pub slot_key: Key,
    pub cover: Key,
}

/// One item to seal into a slot.
pub struct Thing {
    pub name: String,
    pub folder: Option<String>,
    pub entry: Option<&'static str>,
    pub contents: Vec<u8>,
    /// Chunk size when sealed in chunks.
    pub chunked: Option<u32>,
    pub content_modified: Option<f64>,
}

impl Thing {
    pub fn file(name: &str, folder: Option<&str>, contents: Vec<u8>) -> Thing {
        Thing { name: name.into(), folder: folder.map(Into::into), entry: None, contents, chunked: None, content_modified: None }
    }
}

pub fn bytes(seed: u8, count: usize) -> Vec<u8> {
    (0..count).map(|i| (i as u32).wrapping_mul(2_654_435_761).to_be_bytes()[0] ^ seed).collect()
}

impl Fixture {
    /// The vault in slot b and the decoy in a, so nothing can lean on "a is yours".
    pub fn new() -> Fixture {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::at(dir.path().join("Store"));
        let cover = Key::random();
        let yours = Slot::B;

        let w2 = b"Wages 52,011.00\n".to_vec();
        let photo = bytes(7, 40_000);
        // Over two chunks at the Mac's 1 MiB, so the middle and the last both get checked.
        let big = bytes(3, 2_500_000);
        let secret = json!({"template": "login", "fields": [
            {"id": Uuid::new_v4(), "label": "Bank", "value": "First Savings", "concealed": false},
            {"id": Uuid::new_v4(), "label": "Password", "value": "hunter2: with a colon", "concealed": true},
        ]});
        let things = vec![
            Thing::file("w2.txt", Some("Taxes/2025"), w2.clone()),
            Thing { content_modified: Some((1_560_000_000 - APPLE_EPOCH) as f64), ..Thing::file("photo.bin", None, photo.clone()) },
            Thing { chunked: Some(1 << 20), ..Thing::file("big.bin", None, big.clone()) },
            Thing { entry: Some("note"), ..Thing::file("Shopping", None, b"milk\neggs\n".to_vec()) },
            Thing { entry: Some("secret"), ..Thing::file("Bank", None, serde_json::to_vec(&secret).unwrap()) },
        ];
        let folders = vec!["Taxes".to_string(), "Taxes/2025".to_string(), "Empty".to_string()];

        let password = "correct horse battery staple".to_string();
        let recovery = stillroom_core::crypto::make_recovery_code();
        let kit_secret: [u8; 16] = Key::random().as_bytes()[..16].try_into().unwrap();
        let pieces: Vec<String> = kit::split(&kit_secret, 2, 3).iter().map(kit::code).collect();
        let slot_key = write_slot(&store, yours, &cover, &password, &recovery, &kit::password(&kit_secret), &things, &folders);

        let decoy = "a different password entirely".to_string();
        let groceries = Thing { entry: Some("note"), ..Thing::file("Groceries", None, b"bread\n".to_vec()) };
        write_slot(&store, other(yours), &cover, &decoy, &stillroom_core::crypto::make_recovery_code(),
                   &kit::password(&[9; 16]), &[groceries], &[]);

        Fixture { dir, store, yours, password, recovery, pieces, decoy, w2, photo, big, slot_key, cover }
    }

    pub fn root(&self) -> &Path {
        self.store.root()
    }

    pub fn out(&self, name: &str) -> PathBuf {
        self.dir.path().join(name)
    }
}

pub fn other(slot: Slot) -> Slot {
    if slot == Slot::A { Slot::B } else { Slot::A }
}

/// A whole slot: its key files, its cover key, its list and its items. Returns the slot key.
#[allow(clippy::too_many_arguments)]
pub fn write_slot(store: &Store, slot: Slot, cover: &Key, password: &str, recovery: &str, kit_password: &str,
                  things: &[Thing], folders: &[String]) -> Key {
    let key = Key::random();
    let folder = store.root().join(slot.letter());
    fs::create_dir_all(&folder).unwrap();
    fs::write(folder.join("password.key"), seal_with_password(&key, password, QUICK).unwrap()).unwrap();
    fs::write(folder.join("recovery.key"), seal_with_password(&key, &normalized_recovery_code(recovery), QUICK).unwrap()).unwrap();
    fs::write(folder.join("kit.key"), seal_with_password(&key, kit_password, QUICK).unwrap()).unwrap();
    fs::write(folder.join("cover.key"), seal(cover.as_bytes(), &key, Some(&bound::cover_key(slot.letter()))).unwrap()).unwrap();

    let files: Vec<Value> = things.iter().map(|thing| seal_thing(store, thing)).collect();
    let mut list = json!({
        "files": files, "folders": folders, "showInCapture": false,
        "intruder": b64(&[5; 32]), "touchID": b64(&[0; 64]),
        "kitMade": "000000000000", "kitReminded": "000000000000",
    });
    if !things.is_empty() {
        list = json!({"format": 4, "vault": list});
    }
    write_list(store, slot, &key, cover, &serde_json::to_vec(&list).unwrap());
    key
}

fn pad(n: usize) -> usize {
    padded_length(n as u64).unwrap() as usize
}

/// A list as given, padded with spaces, sealed with the slot key and put in its cover.
pub fn write_list(store: &Store, slot: Slot, key: &Key, cover: &Key, json: &[u8]) {
    let mut json = json.to_vec();
    json.resize(pad(json.len()), b' ');
    let inner = seal(&json, key, Some(bound::LIST)).unwrap();
    let mut plain = (inner.len() as u64).to_be_bytes().to_vec();
    plain.extend_from_slice(&inner);
    plain.resize(pad(plain.len()), 0);
    let covered = seal(&plain, cover, Some(&bound::cover("list", slot.letter()))).unwrap();
    fs::write(store.root().join(slot.letter()).join("list"), covered).unwrap();
}

/// One item sealed into Files/ with a fresh key and id; its entry in the list.
pub fn seal_thing(store: &Store, thing: &Thing) -> Value {
    let item_key = Key::random();
    let sealed_as = Uuid::new_v4();
    let path = store.blob(&sealed_as);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    let mut padded = thing.contents.clone();
    padded.resize(pad(padded.len()), 0);
    let blob = match thing.chunked {
        None => seal(&padded, &item_key, Some(&bound::item(sealed_as.as_bytes()))).unwrap(),
        Some(chunk_size) => {
            let count = chunk_count(thing.contents.len() as u64, u64::from(chunk_size)).unwrap();
            let mut blob = b"VLT2".to_vec();
            blob.extend_from_slice(&chunk_size.to_be_bytes());
            for index in 0..count {
                let start = (index * u64::from(chunk_size)) as usize;
                let end = (start + chunk_size as usize).min(padded.len());
                let binding = chunk_binding(&sealed_as, index, index == count - 1);
                blob.extend(seal(&padded[start..end], &item_key, Some(&binding)).unwrap());
            }
            blob
        }
    };
    fs::write(&path, blob).unwrap();
    json!({
        "id": Uuid::new_v4(), "name": thing.name, "uti": "public.data", "size": thing.contents.len(),
        "addedAt": 783_000_000.0, "folder": thing.folder, "entry": thing.entry,
        "chunked": thing.chunked.map(|_| true), "contentModified": thing.content_modified,
        "sealedAs": sealed_as.hyphenated().to_string().to_uppercase(), "key": b64(item_key.as_bytes()),
    })
}

pub fn b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// A store of a test's own, in a folder of its own, with passwords stretched at the quick cost. The real vault is
/// never touched.
pub fn store_in(dir: &Path) -> Store {
    Store::at(dir.join("Store")).with_cost(QUICK)
}

/// A file to add, beside the store.
pub fn sample(dir: &Path, name: &str, contents: &[u8]) -> PathBuf {
    let folder = dir.join(format!("in-{}", Uuid::new_v4().simple()));
    fs::create_dir_all(&folder).unwrap();
    let path = folder.join(name);
    fs::write(&path, contents).unwrap();
    path
}
