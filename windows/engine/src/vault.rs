//! A vault folder and the ways into it: `Storage/VaultStore.swift` and `AppState`'s unlocking.
//!
//! ```text
//! Store/
//!   a/  b/        password.key, recovery.key, kit.key, cover.key, list, search
//!   intruder.pub  both slots' intruder public keys
//!   intruder/     the intruder log
//!   touchid.key   when Touch ID is on (it opens one slot; Mac only)
//!   mac.key       when the vault is locked to a Mac
//!   Files/        both slots' items
//! ```
//!
//! Every way in is tried on both slots, every time, so how long unlocking takes doesn't tell which slot opened. The two
//! slots are built by the same code, alike: nothing on disk says which one is yours (docs/SECURITY.md rule 2).

use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use base64::Engine as _;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zeroize::{Zeroize, Zeroizing};

use crate::blob::{self, ChunkedReader};
use crate::crypto::{
    bound, fill_random, make_recovery_code, normalized_recovery_code, open_with_password, padded_size, seal,
    seal_with_password, unseal, Key, PasswordCost,
};
use crate::list::{Item, VaultList};
use crate::names::{ItemSeal, Names};
use crate::{fsx, intruder, kinds, kit, search, Error, VaultError};

/// One of the two slots, built exactly alike. The letters say nothing about which is whose.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Slot {
    A,
    B,
}

impl Slot {
    pub const ALL: [Slot; 2] = [Slot::A, Slot::B];

    pub fn letter(self) -> &'static str {
        match self {
            Slot::A => "a",
            Slot::B => "b",
        }
    }

    pub fn other(self) -> Slot {
        match self {
            Slot::A => Slot::B,
            Slot::B => Slot::A,
        }
    }
}

/// The two kinds of covered file in a slot.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Covered {
    List,
    Search,
}

impl Covered {
    fn name(self) -> &'static str {
        match self {
            Covered::List => "list",
            Covered::Search => "search",
        }
    }
}

/// A password, recovery code or kit secret nobody will ever type: what seals a slot nobody set.
pub fn unknowable() -> Zeroizing<String> {
    Zeroizing::new(base64::engine::general_purpose::STANDARD.encode(Key::random().as_bytes()))
}

/// A vault folder on disk.
#[derive(Clone, Debug)]
pub struct Store {
    root: PathBuf,
    cost: PasswordCost,
    read_only: bool,
}

impl Store {
    pub fn at(root: impl Into<PathBuf>) -> Store {
        Store { root: root.into(), cost: PasswordCost::CURRENT, read_only: false }
    }

    /// Where the vault lives on Windows: %APPDATA%\Stillroom\Store.
    pub fn default_root() -> Option<PathBuf> {
        std::env::var_os("APPDATA").map(|appdata| PathBuf::from(appdata).join("Stillroom").join("Store"))
    }

    /// Passwords stretched at this cost from now on. Tests turn it down, as the Mac tests do.
    pub fn with_cost(mut self, cost: PasswordCost) -> Store {
        self.cost = cost;
        self
    }

    /// Opens without tidying anything and refuses every write: for taking a vault out (stillroom-open), which must
    /// leave it exactly as it was.
    pub fn read_only(mut self) -> Store {
        self.read_only = true;
        self
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn cost(&self) -> PasswordCost {
        self.cost
    }

    pub fn slot_folder(&self, slot: Slot) -> PathBuf {
        self.root.join(slot.letter())
    }

    pub fn slot_file(&self, slot: Slot, name: &str) -> PathBuf {
        self.slot_folder(slot).join(name)
    }

    /// Where a new slot is made before it's swapped in.
    pub fn staging(&self, slot: Slot) -> PathBuf {
        self.root.join(format!(".{}-new", slot.letter()))
    }

    /// One folder of items for both slots.
    pub fn files(&self) -> PathBuf {
        self.root.join("Files")
    }

    /// Where an item's sealing lies: `Files/<sealedAs>.stillroom`, the id in capitals as the Mac writes it.
    pub fn blob(&self, sealed_as: &Uuid) -> PathBuf {
        let name = sealed_as.hyphenated().encode_upper(&mut Uuid::encode_buffer()).to_owned();
        self.files().join(name + ".stillroom")
    }

    /// Wrong tries, kept beside the vault folder (not in it): see `tries.rs`.
    pub fn try_limit(&self) -> crate::tries::TryLimit {
        let beside = self.root.parent().unwrap_or(&self.root);
        crate::tries::TryLimit::at(beside.join("tries.json"))
    }

    /// The vault's own folder and what lives beside it: a swap a crash left (`<name>.swapping`), copies a restore set
    /// aside, the wrong-try count. Never added into the vault, so never offered as originals to delete: adding a folder
    /// that holds the vault (a whole user folder, say) must not seal the vault into itself, nor then delete its keys.
    /// As found on disk now (canonical), for comparing with what's being added.
    pub fn own_paths(&self) -> Vec<PathBuf> {
        let canonical = |p: &Path| fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf());
        let mut own = vec![canonical(&self.root)];
        if let (Some(parent), Some(name)) = (self.root.parent(), self.root.file_name()) {
            let name = name.to_string_lossy().into_owned();
            for entry in fs::read_dir(parent).into_iter().flatten().flatten() {
                let other = entry.file_name().to_string_lossy().into_owned();
                if other != name && (other.starts_with(&name) || other.starts_with("Store-before-restore-")) {
                    own.push(canonical(&entry.path()));
                }
            }
            own.push(canonical(&parent.join("tries.json")));
        }
        own
    }

    pub fn mac_key(&self) -> PathBuf {
        self.root.join("mac.key")
    }

    pub fn touch_id_key(&self) -> PathBuf {
        self.root.join("touchid.key")
    }

    /// Windows Hello's way in to one slot (`hello.rs`).
    pub fn hello_key(&self) -> PathBuf {
        self.root.join("hello.key")
    }

    /// Lock to this PC (`tpm.rs`).
    pub fn pc_key(&self) -> PathBuf {
        self.root.join("pc.key")
    }

    /// Locked to a PC: its password keys are sealed again by that PC's TPM. Here, if this is the PC; elsewhere only the
    /// recovery key or the kit opens it.
    pub fn is_locked_to_a_pc(&self) -> bool {
        self.pc_key().is_file()
    }

    fn read_pc_key(&self) -> Result<crate::tpm::PcKey, VaultError> {
        let data = fs::read(self.pc_key()).map_err(|_| VaultError::Damaged)?;
        serde_json::from_slice(&data).map_err(|_| VaultError::Damaged)
    }

    /// The key that seals both slots' password keys again, when the vault is locked to this PC; None when it isn't
    /// locked. `NotThisComputer` when it's locked to a Mac, or to a PC whose TPM key isn't here.
    pub(crate) fn password_lock(&self) -> Result<Option<Key>, VaultError> {
        if self.is_locked_to_a_mac() {
            return Err(VaultError::NotThisComputer);
        }
        if !self.is_locked_to_a_pc() {
            return Ok(None);
        }
        crate::tpm::unwrap(&self.read_pc_key()?).map(Some)
    }

    /// A slot's password key as read from disk, ready for the password: unsealed by `lock` when there is one. One left
    /// unsealed (the lock was being turned on or off when the PC stopped) is taken as it is: it still needs the password.
    pub(crate) fn read_password_key(&self, slot: Slot, lock: Option<&Key>) -> Option<Vec<u8>> {
        let data = fs::read(self.slot_file(slot, "password.key")).ok()?;
        match lock {
            Some(lock) => Some(unseal(&data, lock, None).map(|plain| plain.to_vec()).unwrap_or(data)),
            None => Some(data),
        }
    }

    /// A password key as it's written to disk: sealed again for this PC when the lock is on.
    pub(crate) fn seal_password_key(&self, plain: Vec<u8>, lock: Option<&Key>) -> Result<Vec<u8>, VaultError> {
        match lock {
            Some(lock) => seal(&plain, lock, None),
            None => Ok(plain),
        }
    }

    /// Lock to this PC turned on: a new TPM key, and both slots' password keys sealed again with the outer key it
    /// wraps. The lock file goes first, so a stop midway leaves keys that still open (`read_password_key`).
    pub(crate) fn lock_to_this_pc(&self) -> Result<(), Error> {
        self.writable()?;
        if self.is_locked_to_a_mac() {
            return Err(Error::LockedElsewhere);
        }
        if self.is_locked_to_a_pc() {
            return Ok(());
        }
        let (file, outer) = crate::tpm::make().map_err(|_| Error::NoTpm)?;
        self.write_key(&self.pc_key(), &serde_json::to_vec(&file).map_err(std::io::Error::other)?)?;
        for slot in Slot::ALL {
            let Some(plain) = self.read_password_key(slot, None) else { continue };
            self.write_key(&self.slot_file(slot, "password.key"), &seal(&plain, &outer, None)?)?;
        }
        Ok(())
    }

    /// Lock to this PC turned off: both password keys back as they were, and the TPM key deleted.
    pub(crate) fn unlock_from_this_pc(&self) -> Result<(), Error> {
        self.writable()?;
        let Some(lock) = self.password_lock()? else { return Ok(()) };
        for slot in Slot::ALL {
            let Some(plain) = self.read_password_key(slot, Some(&lock)) else { continue };
            self.write_key(&self.slot_file(slot, "password.key"), &plain)?;
        }
        let file = self.read_pc_key()?;
        fs::remove_file(self.pc_key())?;
        crate::tpm::delete(&file);
        fsx::even_dates(&self.key_files(), SystemTime::now());
        Ok(())
    }

    /// After a recovery key or kit on another PC: the lock comes here. A new TPM key here seals this slot's new password
    /// key; the other slot's stays sealed to the old PC (same size and layout as ever) until its own recovery key is
    /// used, as on the Mac. With no TPM here the lock comes off. Gives the lock to seal the new password key with.
    pub(crate) fn move_pc_lock_here(&self) -> Result<Option<Key>, Error> {
        if let Ok(lock) = self.password_lock() {
            return Ok(lock);
        }
        let old = self.read_pc_key().ok();
        fs::remove_file(self.pc_key())?;
        if let Some(old) = old {
            crate::tpm::delete(&old);
        }
        match crate::tpm::make() {
            Ok((file, outer)) => {
                self.write_key(&self.pc_key(), &serde_json::to_vec(&file).map_err(std::io::Error::other)?)?;
                Ok(Some(outer))
            }
            Err(_) => {
                fsx::even_dates(&self.key_files(), SystemTime::now());
                Ok(None)
            }
        }
    }

    /// Both slots' password keys are written last when a vault is made, so their being there means it's whole.
    pub fn exists(&self) -> bool {
        Slot::ALL.iter().all(|&slot| self.slot_file(slot, "password.key").is_file())
    }

    /// A folder left by a build before format 4. It's never read, and nothing is written over it.
    pub fn is_old_format(&self) -> bool {
        !self.exists() && self.root.join("password.key").exists()
    }

    /// Locked to the Mac that made it: its password keys are sealed again by that Mac's Secure Enclave, so only the
    /// recovery key or the kit opens it here.
    pub fn is_locked_to_a_mac(&self) -> bool {
        self.mac_key().is_file()
    }

    // MARK: Writing

    fn writable(&self) -> Result<(), Error> {
        if self.read_only { Err(Error::ReadOnly) } else { Ok(()) }
    }

    /// Written whole or not at all.
    pub fn write(&self, path: &Path, data: &[u8]) -> Result<(), Error> {
        self.writable()?;
        Ok(fsx::write_atomic(path, data)?)
    }

    /// Every file that opens a way in, and the slot folders. They all share one date, so a key written later (a decoy
    /// set a year on) isn't newer than the rest.
    pub fn key_files(&self) -> Vec<PathBuf> {
        let mut files = Vec::new();
        for slot in Slot::ALL {
            files.push(self.slot_folder(slot));
            for name in ["password.key", "recovery.key", "kit.key", "cover.key"] {
                files.push(self.slot_file(slot, name));
            }
        }
        files.extend([intruder::public_key_path(self), self.touch_id_key(), self.mac_key(), self.hello_key(), self.pc_key()]);
        files
    }

    /// A key file written, then every key file given the same dates.
    pub fn write_key(&self, path: &Path, data: &[u8]) -> io::Result<()> {
        if self.read_only {
            return Err(io::Error::other("read only"));
        }
        fsx::write_atomic(path, data)?;
        fsx::even_dates(&self.key_files(), SystemTime::now());
        Ok(())
    }

    // MARK: Covers

    fn covered_path(&self, kind: Covered, slot: Slot) -> PathBuf {
        self.slot_file(slot, kind.name())
    }

    /// The cover key, opened with a slot key. None when the slot key isn't this slot's.
    pub fn open_cover(&self, slot: Slot, key: &Key) -> Option<Key> {
        let sealed = fs::read(self.slot_file(slot, "cover.key")).ok()?;
        let raw = unseal(&sealed, key, Some(&bound::cover_key(slot.letter()))).ok()?;
        Key::from_slice(&raw).ok()
    }

    /// What's inside a slot's list or index cover: the slot's own sealed list or index, its padding off.
    pub fn read_covered(&self, kind: Covered, slot: Slot, cover: &Key) -> Option<Vec<u8>> {
        read_covered_at(&self.covered_path(kind, slot), kind, slot, cover)
    }

    /// One slot's sealed list or index, in a cover padded to `size` (or the least that holds it).
    pub fn cover(inner: &[u8], kind: Covered, slot: Slot, cover: &Key, size: usize) -> Result<Vec<u8>, VaultError> {
        let mut plain = (inner.len() as u64).to_be_bytes().to_vec();
        plain.extend_from_slice(inner);
        let size = size.max(plain.len());
        plain.resize(size, 0);
        seal(&plain, cover, Some(&bound::cover(kind.name(), slot.letter())))
    }

    /// The size both covers of a kind share: enough for the larger inside.
    pub fn cover_size(a: usize, b: usize) -> Result<usize, VaultError> {
        padded_size(8 + a.max(b))
    }

    /// Writes a slot's new list or index, and the other slot's again as it was, both in fresh covers of one size and
    /// with one date: a copy of the folder sees both change together, whichever slot is open.
    pub fn write_covered(&self, inner: &[u8], kind: Covered, slot: Slot, cover: &Key) -> Result<(), Error> {
        let theirs = self.read_covered(kind, slot.other(), cover);
        let size = Store::cover_size(inner.len(), theirs.as_ref().map_or(0, Vec::len))?;
        self.write(&self.covered_path(kind, slot), &Store::cover(inner, kind, slot, cover, size)?)?;
        if let Some(theirs) = theirs {
            self.write(&self.covered_path(kind, slot.other()), &Store::cover(&theirs, kind, slot.other(), cover, size)?)?;
        }
        let both = [self.covered_path(kind, slot), self.covered_path(kind, slot.other())];
        fsx::even_dates(&both, SystemTime::now());
        Ok(())
    }

    /// Both slots' lists and indexes in fresh covers, as they are: after a slot was swapped in.
    pub fn recover_covers(&self, cover: &Key) -> Result<(), Error> {
        for kind in [Covered::List, Covered::Search] {
            if let Some(a) = self.read_covered(kind, Slot::A, cover) {
                self.write_covered(&a, kind, Slot::A, cover)?;
            }
        }
        Ok(())
    }

    // MARK: The list

    /// The list sealed with the slot key, padded with spaces, each item's own key (by `sealedAs`) written in. A list
    /// holding files is wrapped as `{"format": 4, "vault": {…}}`; an empty one isn't, so every empty list is one size.
    pub fn sealed_list(list: &VaultList, key: &Key, item_keys: &HashMap<Uuid, Key>) -> Result<Vec<u8>, Error> {
        #[derive(Serialize)]
        struct Wrapped<'a> {
            format: u32,
            vault: &'a VaultList,
        }
        let mut stored = list.clone();
        let written = |sealed_as: Option<Uuid>| {
            sealed_as.and_then(|id| item_keys.get(&id)).map(|k| base64::engine::general_purpose::STANDARD.encode(k.as_bytes()))
        };
        for item in &mut stored.files {
            item.key = written(item.sealed_as);
            for version in item.versions.iter_mut().flatten() {
                version.key = written(version.sealed_as);
            }
        }
        let json = if stored.files.is_empty() {
            serde_json::to_vec(&stored)
        } else {
            serde_json::to_vec(&Wrapped { format: 4, vault: &stored })
        };
        let mut json = Zeroizing::new(json.map_err(io::Error::other)?);
        for item in &mut stored.files {
            item.key.zeroize();
            for version in item.versions.iter_mut().flatten() {
                version.key.zeroize();
            }
        }
        let padded = padded_size(json.len())?;
        json.resize(padded, b' ');
        Ok(seal(&json, key, Some(bound::LIST))?)
    }

    pub fn save_list(&self, list: &VaultList, key: &Key, item_keys: &HashMap<Uuid, Key>, slot: Slot, cover: &Key) -> Result<(), Error> {
        self.write_covered(&Store::sealed_list(list, key, item_keys)?, Covered::List, slot, cover)
    }

    /// The list, and each item's own key by `sealedAs`. The keys are taken out of the list as it's read, so no `Item`
    /// carries one. Every item and version must have its key: one without is damage.
    pub fn load_list(&self, slot: Slot, key: &Key, cover: &Key) -> Result<(VaultList, HashMap<Uuid, Key>), VaultError> {
        let inner = self.read_covered(Covered::List, slot, cover).ok_or(VaultError::Damaged)?;
        let json = unseal(&inner, key, Some(bound::LIST))?;
        let mut list = decode_list(&json)?;

        let mut keys = HashMap::new();
        fn take(keys: &mut HashMap<Uuid, Key>, text: &mut Option<String>, sealed_as: Option<Uuid>) -> Result<(), VaultError> {
            let (Some(written), Some(sealed_as)) = (text.as_mut(), sealed_as) else { return Err(VaultError::Damaged) };
            let raw = Zeroizing::new(
                base64::engine::general_purpose::STANDARD.decode(written.as_bytes()).map_err(|_| VaultError::Damaged)?,
            );
            written.zeroize();
            *text = None;
            keys.insert(sealed_as, Key::from_slice(&raw)?);
            Ok(())
        }
        for item in &mut list.files {
            take(&mut keys, &mut item.key, item.sealed_as)?;
            for version in item.versions.iter_mut().flatten() {
                take(&mut keys, &mut version.key, version.sealed_as)?;
            }
        }
        Ok((list, keys))
    }

    // MARK: Making a slot

    /// A whole slot, made beside the vault and swapped in at once, so a crash leaves the old slot or the new one, never
    /// half of each. Its password, recovery code and kit secret seal a fresh slot key; its list is empty. The same code
    /// makes a slot you set and one nobody did, so they can't be told apart. Stretches three times. Returns the new
    /// slot key.
    pub fn make_slot(&self, slot: Slot, password: &str, recovery_code: &str, cover: &Key) -> Result<Key, Error> {
        self.writable()?;
        let key = Key::random();
        let staging = self.staging(slot);
        fsx::remove_tree(&staging)?;
        fs::create_dir_all(&staging)?;
        let put = |name: &str, data: &[u8]| fsx::write_atomic(&staging.join(name), data);
        // Sealed again for this PC when the vault is locked to it, as every password key is.
        let lock = self.password_lock()?;
        put("password.key", &self.seal_password_key(seal_with_password(&key, password, self.cost)?, lock.as_ref())?)?;
        put("recovery.key", &seal_with_password(&key, &normalized_recovery_code(recovery_code), self.cost)?)?;
        put("kit.key", &seal_with_password(&key, &unknowable(), self.cost)?)?;
        put("cover.key", &seal(cover.as_bytes(), &key, Some(&bound::cover_key(slot.letter())))?)?;
        let (private, public) = intruder::new_key();
        let list = Store::sealed_list(&VaultList::new(private.to_string()), &key, &HashMap::new())?;
        // Sized as the other slot's are today; both are put in fresh covers of one size once this is in.
        let theirs = |kind| self.read_covered(kind, slot.other(), cover).map_or(0, |v| v.len());
        put("list", &Store::cover(&list, Covered::List, slot, cover, Store::cover_size(list.len(), theirs(Covered::List))?)?)?;
        let index = search::sealed(&search::Index::new(), &key)?;
        put("search", &Store::cover(&index, Covered::Search, slot, cover, Store::cover_size(index.len(), theirs(Covered::Search))?)?)?;
        let live = self.slot_folder(slot);
        if live.exists() {
            fsx::swap_folders(&staging, &live)?;
            fsx::remove_tree(&staging)?;
        } else {
            fs::create_dir_all(&self.root)?;
            fs::rename(&staging, &live)?;
        }
        intruder::set_public_key(self, &public, slot)?;
        self.recover_covers(cover)?;
        fsx::even_dates(&self.key_files(), SystemTime::now());
        Ok(key)
    }

    /// Puts right what a crash left: a slot or a restore swapped halfway is finished or undone, and a half-made slot
    /// goes (the slot it was replacing is whole). Run before anything reads the folder.
    pub fn recover(&self) -> Result<(), Error> {
        if self.read_only {
            return Ok(());
        }
        // A restore stopped after the backup went in: the old vault is kept beside it, as a finished restore keeps it.
        fsx::recover_swap(&self.root, |old| {
            let aside = crate::backup::aside_name(&self.root);
            fs::rename(old, aside)
        })?;
        for slot in Slot::ALL {
            // Stopped after the new slot went in: the old one is no longer wanted.
            fsx::recover_swap(&self.slot_folder(slot), fsx::remove_tree)?;
            fsx::remove_tree(&self.staging(slot))?;
        }
        Ok(())
    }

    // MARK: Items

    /// Seals bytes in one piece into a sealing's blob, padded first so the sealed size gives away little of the real
    /// one (the list keeps the real size), and bound to its id.
    fn store_piece(&self, data: &[u8], seal_: &ItemSeal) -> Result<(), Error> {
        let size = padded_size(data.len())?;
        let mut padded = Zeroizing::new(Vec::with_capacity(size));
        padded.extend_from_slice(data);
        padded.resize(size, 0);
        self.write(&self.blob(&seal_.blob), &seal(&padded, &seal_.key, Some(&bound::item(seal_.blob.as_bytes())))?)
    }

    /// Bytes sealed in as a new sealing, with a fresh id and key of its own: one piece, or in chunks.
    pub fn put(&self, data: &[u8], streamed: bool, slot: Slot, names: &Names) -> Result<ItemSeal, Error> {
        self.writable()?;
        let seal_ = names.fresh(slot);
        if streamed {
            blob::seal_chunked(data, data.len() as u64, &self.blob(&seal_.blob), &seal_.key, &seal_.blob)?;
        } else {
            self.store_piece(data, &seal_)?;
        }
        Ok(seal_)
    }

    /// A file on disk sealed in, in chunks, as a new sealing: never whole in memory. Returns it and the real size.
    pub fn put_streaming(&self, path: &Path, slot: Slot, names: &Names) -> Result<(ItemSeal, u64), Error> {
        self.writable()?;
        let seal_ = names.fresh(slot);
        let file = File::open(path)?;
        let size = file.metadata()?.len();
        blob::seal_chunked(file, size, &self.blob(&seal_.blob), &seal_.key, &seal_.blob)?;
        Ok((seal_, size))
    }

    /// Seals a file from disk into the vault, with a key of its own. The original is left where it was. Big files, and
    /// all audio and video, go in chunks: never whole in memory, and playable as they lie.
    pub fn add_file(&self, path: &Path, folder: Option<&str>, slot: Slot, names: &Names, now: f64) -> Result<(Item, ItemSeal), Error> {
        let meta = fs::metadata(path)?;
        if meta.is_dir() {
            return Err(VaultError::Folder.into());
        }
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "Untitled".into());
        let uti = kinds::uti_for_name(&name);
        let mut item = Item::new(&name, uti, meta.len(), now);
        item.folder = folder.map(Into::into);
        item.created = meta.created().ok().map(crate::apple_seconds);
        item.content_modified = meta.modified().ok().map(crate::apple_seconds);
        let seal_ = if kinds::streams(meta.len(), uti) {
            let (seal_, size) = self.put_streaming(path, slot, names)?;
            item.size = size;
            item.chunked = Some(true);
            seal_
        } else {
            let mut data = Zeroizing::new(Vec::new());
            File::open(path)?.read_to_end(&mut data)?;
            item.size = data.len() as u64;
            self.put(&data, false, slot, names)?
        };
        item.sealed_as = Some(seal_.blob);
        Ok((item, seal_))
    }

    /// The contents of a sealing, whichever form it's in.
    pub fn contents(&self, sealed_as: &Uuid, key: &Key, streamed: bool, size: u64) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        blob::read(&self.blob(sealed_as), sealed_as, key, size, streamed)
    }

    /// Whether a sealing opens all the way through: every chunk's seal checks out and nothing is missing.
    pub fn is_intact(&self, sealed_as: &Uuid, key: &Key, streamed: bool, size: u64) -> bool {
        if streamed {
            let Ok(reader) = ChunkedReader::open(&self.blob(sealed_as), key, sealed_as, size) else { return false };
            return (0..reader.count()).all(|i| reader.chunk(i).is_ok());
        }
        self.contents(sealed_as, key, false, size).is_ok_and(|d| d.len() as u64 == size)
    }

    pub fn remove_blob(&self, id: &Uuid) {
        if !self.read_only {
            let _ = fs::remove_file(self.blob(id));
        }
    }

    /// Every item file, by the id that names it.
    fn items(&self) -> Vec<(PathBuf, Uuid)> {
        let Ok(found) = fs::read_dir(self.files()) else { return Vec::new() };
        found
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter_map(|path| {
                (path.extension()? == "stillroom").then_some(())?;
                let id = Uuid::parse_str(&path.file_stem()?.to_string_lossy()).ok()?;
                Some((path, id))
            })
            .collect()
    }

    /// Deletes the open slot's sealed files that its list no longer names (left by a crash midway), and files that are
    /// no slot's. The other slot's are never touched.
    pub fn prune(&self, keeping: &HashSet<Uuid>, slot: Slot, names: &Names) {
        if self.read_only {
            return;
        }
        for (path, id) in self.items() {
            if !keeping.contains(&id) && names.owner(&id).is_none_or(|owner| owner == slot) {
                let _ = fs::remove_file(path);
            }
        }
    }

    /// Every item file of a slot, for when it's replaced: none of an old decoy stays behind.
    pub fn remove_all(&self, slot: Slot, names: &Names) {
        if self.read_only {
            return;
        }
        for (path, id) in self.items() {
            if names.owner(&id) == Some(slot) {
                let _ = fs::remove_file(path);
            }
        }
    }

    /// What goes in for each thing dropped or chosen: a file as itself; a folder as every file inside it, however deep,
    /// each remembering the folder it was in (its own name first: "Taxes/2025"). Hidden files and links are left out.
    /// Returns the files and how many things were skipped.
    pub fn expand(paths: &[PathBuf]) -> (Vec<(PathBuf, Option<String>)>, usize) {
        let mut items = Vec::new();
        let skipped = 0;
        for path in paths {
            let Ok(meta) = fs::symlink_metadata(path) else { continue };
            if !meta.is_dir() {
                items.push((path.clone(), None));
                continue;
            }
            let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            walk(path, &name, &mut items);
        }
        fn walk(folder: &Path, place: &str, items: &mut Vec<(PathBuf, Option<String>)>) {
            let Ok(entries) = fs::read_dir(folder) else { return };
            let mut entries: Vec<_> = entries.filter_map(Result::ok).collect();
            entries.sort_by_key(|e| e.file_name());
            for entry in entries {
                let path = entry.path();
                let Ok(meta) = fs::symlink_metadata(&path) else { continue };
                if is_hidden(&path, &meta) || meta.file_type().is_symlink() {
                    continue;
                }
                let name = entry.file_name().to_string_lossy().into_owned();
                if meta.is_dir() {
                    walk(&path, &format!("{place}/{name}"), items);
                } else if meta.is_file() {
                    items.push((path, Some(place.to_owned())));
                }
            }
        }
        (items, skipped)
    }

    /// Everything, keys included: nothing in the vault can be opened again. Copies set aside by a restore go too, and
    /// the TPM key of a vault locked to this PC.
    pub fn wipe(&self) -> Result<(), Error> {
        self.writable()?;
        if let Ok(file) = self.read_pc_key() {
            crate::tpm::delete(&file);
        }
        fsx::remove_tree(&self.root)?;
        if let Some(parent) = self.root.parent() {
            for entry in fs::read_dir(parent).into_iter().flatten().flatten() {
                if entry.file_name().to_string_lossy().starts_with("Store-before-restore-") {
                    let _ = fsx::remove_tree(&entry.path());
                }
            }
        }
        Ok(())
    }

    // MARK: Getting in

    /// A new vault. Yours goes in either slot, at random, and the choice is written nowhere. The other is a real slot
    /// whose passwords nobody knows, made by the same code as a decoy you set: the two can't be told apart. Returns the
    /// open vault and its recovery key, to be shown once.
    pub fn create(&self, password: &str) -> Result<(Vault, String), Error> {
        self.writable()?;
        self.recover()?;
        // Only this account can list or read it: other accounts on this PC can't copy it to guess at offline.
        crate::platform::protect_folder(&self.root)?;
        let mut coins = [0u8; 1];
        fill_random(&mut coins);
        let mine = if coins[0] & 1 == 0 { Slot::A } else { Slot::B };
        let cover = Key::random();
        let code = make_recovery_code();
        // Made in a random order, so which slot's files are newer says nothing about which one is yours.
        let other_first = coins[0] & 2 == 0;
        let other = || self.make_slot(mine.other(), &unknowable(), &unknowable(), &cover);
        if other_first {
            other()?;
        }
        let key = self.make_slot(mine, password, &code, &cover)?;
        if !other_first {
            other()?;
        }
        Ok((self.open(mine, key)?, code))
    }

    /// Locked to a Mac, or to a PC whose TPM key isn't here: `NotThisComputer` (open it with the recovery key or kit).
    pub fn unlock_with_password(&self, password: &str) -> Result<Vault, Error> {
        self.recover()?;
        let lock = self.password_lock()?;
        let (slot, key) = self
            .try_each_with(password, |slot| self.read_password_key(slot, lock.as_ref()))
            .ok_or(VaultError::WrongPassword)?;
        self.open(slot, key)
    }

    /// The challenge Windows Hello is asked to sign, from hello.key. `NotFound` when Hello isn't on.
    pub fn hello_challenge(&self) -> Result<Vec<u8>, Error> {
        let file = self.read_hello_key().ok_or(Error::NotFound)?;
        Ok(crate::hello::decode(&file.challenge)?)
    }

    pub(crate) fn read_hello_key(&self) -> Option<crate::hello::HelloKey> {
        serde_json::from_slice(&fs::read(self.hello_key()).ok()?).ok()
    }

    /// Windows Hello's signature of the challenge opens the slot that turned it on (whichever opens its cover key).
    /// `HelloChanged` when it opens nothing: Hello was set up again, or the vault's way in was replaced.
    pub fn unlock_with_hello(&self, signature: &[u8]) -> Result<Vault, Error> {
        self.recover()?;
        let file = self.read_hello_key().ok_or(Error::NotFound)?;
        let wrapping = crate::hello::wrapping_key(signature)?;
        let sealed = crate::hello::decode(&file.vault_key)?;
        let raw = unseal(&sealed, &wrapping, None).map_err(|_| VaultError::HelloChanged)?;
        let key = Key::from_slice(&raw).map_err(|_| VaultError::HelloChanged)?;
        let slot = Slot::ALL.into_iter().find(|&slot| self.open_cover(slot, &key).is_some()).ok_or(VaultError::HelloChanged)?;
        self.open(slot, key)
    }

    /// A recovery key, as typed: any case, with or without dashes and spaces. Opens its slot on any computer; a new
    /// password must be set before anything else.
    pub fn unlock_with_recovery_key(&self, typed: &str) -> Result<Vault, Error> {
        self.recover()?;
        let normalized = normalized_recovery_code(typed);
        let (slot, key) = self.try_each("recovery.key", &normalized).ok_or(VaultError::WrongRecoveryKey)?;
        let mut vault = self.open(slot, key)?;
        vault.must_set_password = true;
        Ok(vault)
    }

    /// Pieces of an emergency kit, as typed. A piece that doesn't read, or pieces from different kits, fail before
    /// anything is stretched; enough good pieces that open neither slot are `WrongKit`.
    pub fn unlock_with_kit(&self, typed: &[&str]) -> Result<Vault, Error> {
        self.recover()?;
        let pieces = typed.iter().filter(|t| !t.trim().is_empty()).map(|t| kit::piece(t)).collect::<Result<Vec<_>, _>>()?;
        let secret = kit::join(&pieces)?;
        let password = kit::password(&secret);
        let (slot, key) = self.try_each("kit.key", &password).ok_or(VaultError::WrongKit)?;
        let mut vault = self.open(slot, key)?;
        vault.must_set_password = true;
        Ok(vault)
    }

    /// One secret stretched against both slots' file of this name, both of them every time. A slot whose file is
    /// missing, can't be read, or is refused before stretching (damaged) costs a stretch anyway, so how long a try takes
    /// never says how many slots answered.
    fn try_each(&self, name: &str, secret: &str) -> Option<(Slot, Key)> {
        self.try_each_with(secret, |slot| fs::read(self.slot_file(slot, name)).ok())
    }

    /// `try_each` over key files as `read` gives them (the password keys, unsealed by the PC lock first).
    fn try_each_with(&self, secret: &str, read: impl Fn(Slot) -> Option<Vec<u8>>) -> Option<(Slot, Key)> {
        let mut found = None;
        for slot in Slot::ALL {
            let Some(sealed) = read(slot) else {
                self.stretch_in_vain(secret);
                continue;
            };
            // Any failure, a doctored file included, is just "doesn't open": the other slot is still tried.
            match open_with_password(&sealed, secret) {
                Ok(key) => {
                    if found.is_none() {
                        found = Some((slot, key));
                    }
                }
                Err(VaultError::Damaged) => self.stretch_in_vain(secret),
                Err(_) => {}
            }
        }
        found
    }

    /// One stretch at today's cost whose result is thrown away: the time a slot that can't answer would have taken.
    fn stretch_in_vain(&self, secret: &str) {
        let mut salt = [0u8; 16];
        fill_random(&mut salt);
        let _ = crate::crypto::stretch_argon(secret, &salt, self.cost);
    }

    /// A slot opened with its slot key: its cover key, then its list. Unless read only, it's tidied as the Mac tidies
    /// on opening: a half-made slot goes, sealed files no list names go, the intruder log's key is checked, and the
    /// search index is read.
    pub fn open(&self, slot: Slot, key: Key) -> Result<Vault, Error> {
        let cover = self.open_cover(slot, &key).ok_or(VaultError::Damaged)?;
        let (list, item_keys) = self.load_list(slot, &key, &cover)?;
        let names = Names::new(&cover);
        let mut vault = Vault {
            store: self.clone(),
            slot,
            key,
            cover,
            names,
            list,
            item_keys,
            must_set_password: false,
            words: search::Index::new(),
            intruder_reset: false,
        };
        if self.read_only {
            return Ok(vault);
        }
        self.recover()?;
        let keeping: HashSet<Uuid> = vault.list.files.iter().flat_map(Item::blobs).collect();
        self.prune(&keeping, slot, &vault.names);
        let (checked, swapped) = intruder::check(self, &vault.list.intruder, slot)?;
        if *checked != vault.list.intruder {
            vault.list.intruder = checked.to_string();
            vault.intruder_reset = swapped;
            vault.save()?;
        }
        vault.words = search::load(self, &vault.key, slot, &vault.cover);
        Ok(vault)
    }

    /// Records a wrong try at the lock screen, for both slots (works while locked).
    pub fn record_intruder(&self, kind: intruder::Kind, photo: Option<&[u8]>) -> Result<(), Error> {
        self.writable()?;
        Ok(intruder::record(self, kind, photo, crate::now())?)
    }
}

fn read_covered_at(path: &Path, kind: Covered, slot: Slot, cover: &Key) -> Option<Vec<u8>> {
    let sealed = fs::read(path).ok()?;
    let plain = unseal(&sealed, cover, Some(&bound::cover(kind.name(), slot.letter()))).ok()?;
    if plain.len() < 8 {
        return None;
    }
    let length = u64::from_be_bytes(plain[..8].try_into().unwrap());
    let length = usize::try_from(length).ok().filter(|&n| n <= plain.len() - 8)?;
    Some(plain[8..8 + length].to_vec())
}

/// Hidden as Windows and the Mac both mean it: marked hidden or system, or named with a leading dot.
fn is_hidden(path: &Path, meta: &fs::Metadata) -> bool {
    if path.file_name().is_some_and(|n| n.to_string_lossy().starts_with('.')) {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const HIDDEN: u32 = 0x2;
        const SYSTEM: u32 = 0x4;
        if meta.file_attributes() & (HIDDEN | SYSTEM) != 0 {
            return true;
        }
    }
    let _ = meta;
    false
}

/// The list as written once it holds items: `{"format": 4, "vault": {…}}`. An empty one is written bare.
fn decode_list(json: &[u8]) -> Result<VaultList, VaultError> {
    #[derive(Deserialize)]
    struct Wrapped {
        format: u64,
        vault: VaultList,
    }
    #[derive(Deserialize)]
    struct Format {
        format: u64,
    }
    if let Ok(wrapped) = serde_json::from_slice::<Wrapped>(json) {
        // A list from a newer Stillroom: read nothing rather than misread it and save over it.
        return if wrapped.format == 4 { Ok(wrapped.vault) } else { Err(VaultError::NewerVault) };
    }
    if let Ok(Format { format }) = serde_json::from_slice::<Format>(json) {
        if format != 4 {
            return Err(VaultError::NewerVault);
        }
    }
    match serde_json::from_slice::<VaultList>(json) {
        Ok(plain) if plain.files.is_empty() => Ok(plain),
        _ => Err(VaultError::Damaged),
    }
}

/// An open vault: one slot's keys, its list and every item's key, held in memory only while open. Dropping it is
/// locking: the keys and everything decrypted are wiped. The engine's `AppState`; its actions are in `session.rs`.
pub struct Vault {
    pub(crate) store: Store,
    pub(crate) slot: Slot,
    pub(crate) key: Key,
    pub(crate) cover: Key,
    pub(crate) names: Names,
    pub(crate) list: VaultList,
    pub(crate) item_keys: HashMap<Uuid, Key>,
    /// Opened with the recovery key or the kit: a new password must be set before anything else.
    pub(crate) must_set_password: bool,
    /// The words inside items, for search.
    pub(crate) words: search::Index,
    /// The intruder log's lock was found changed on opening, and has been reset.
    pub(crate) intruder_reset: bool,
}

impl Vault {
    pub fn store(&self) -> &Store {
        &self.store
    }

    /// Which slot is open. Shown alike in every way: nothing should decide anything by it but storage.
    pub fn slot(&self) -> Slot {
        self.slot
    }

    pub fn list(&self) -> &VaultList {
        &self.list
    }

    pub fn files(&self) -> &[Item] {
        &self.list.files
    }

    pub fn key(&self) -> &Key {
        &self.key
    }

    pub fn cover(&self) -> &Key {
        &self.cover
    }

    pub fn names(&self) -> &Names {
        &self.names
    }

    /// The key of one sealing (an item's current contents or one earlier version), by its `sealedAs`.
    pub fn item_key(&self, sealed_as: &Uuid) -> Option<&Key> {
        self.item_keys.get(sealed_as)
    }

    pub fn must_set_password(&self) -> bool {
        self.must_set_password
    }

    pub fn intruder_was_reset(&self) -> bool {
        self.intruder_reset
    }

    /// Writes the list as it now stands, in both slots' covers.
    pub fn save(&self) -> Result<(), Error> {
        self.store.save_list(&self.list, &self.key, &self.item_keys, self.slot, &self.cover)
    }
}
