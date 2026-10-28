//! What an open vault does: `AppState`'s actions, for the Windows app to call. Every change to the list goes through
//! `change`, which saves it in both slots' covers and puts it back as it was if saving fails, so what's in memory never
//! says something the disk doesn't. Where the Mac app shows a `problem`, these return the error for the app to show.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use uuid::Uuid;
use zeroize::Zeroizing;

use crate::crypto::{fill_random, make_recovery_code, normalized_recovery_code, open_with_password, seal_with_password};
use crate::import::Login;
use crate::list::{self, Entry, Item, Secret, Template, Version, VaultList};
use crate::originals::Originals;
use crate::vault::{unknowable, Covered, Vault};
use crate::{fsx, intruder, kinds, kit, now, search, Error, VaultError};

/// How long an item must be left alone before a change keeps what it held as a version (so typing in a note doesn't
/// make a version a second), and how many versions are kept.
pub const VERSION_AFTER: f64 = 600.0;
pub const MOST_VERSIONS: usize = 20;
/// The emergency kit is brought up once a year.
const KIT_REMINDER: f64 = 365.0 * 24.0 * 3600.0;

/// New contents for an item.
pub enum Contents<'a> {
    Bytes(&'a [u8]),
    /// A file on disk (a save from editing in place): big ones go in chunks, never whole in memory.
    File(&'a Path),
}

/// What adding files did.
#[derive(Debug, Default)]
pub struct Added {
    /// The items made, in order.
    pub items: Vec<Uuid>,
    /// The originals whose sealed copy read back byte for byte: the only ones that may be deleted.
    pub originals: Originals,
    /// Files that went in but didn't read back the same (were they changing?): their originals are kept.
    pub unchecked: Vec<PathBuf>,
    /// Files that didn't go in, and why.
    pub failed: Vec<(PathBuf, Error)>,
    /// Things that can't go in at all.
    pub skipped: usize,
}

/// Something that no longer opens: an item's current contents, or one of its earlier versions.
#[derive(Clone, Debug, PartialEq)]
pub struct Damage {
    pub item: Uuid,
    /// The damaged version; None when it's the current contents.
    pub version: Option<Uuid>,
    /// For damaged current contents: the newest earlier version that still opens, to fall back to.
    pub fallback: Option<Uuid>,
}

impl Vault {
    pub fn item(&self, id: &Uuid) -> Option<&Item> {
        self.list.files.iter().find(|i| i.id == *id)
    }

    fn index(&self, id: &Uuid) -> Result<usize, Error> {
        self.list.files.iter().position(|i| i.id == *id).ok_or(Error::NotFound)
    }

    /// Applies a change to the list and saves it; if saving fails the change is undone.
    fn change(&mut self, edit: impl FnOnce(&mut VaultList)) -> Result<(), Error> {
        let before = (self.list.files.clone(), self.list.folders.clone());
        edit(&mut self.list);
        if let Err(error) = self.save() {
            (self.list.files, self.list.folders) = before;
            return Err(error);
        }
        Ok(())
    }

    /// A new item and its sealing taken into the list, saved; on failure, nothing of it stays.
    fn take_in(&mut self, item: Item, sealed: crate::names::ItemSeal) -> Result<Uuid, Error> {
        let (id, blob) = (item.id, sealed.blob);
        self.item_keys.insert(blob, sealed.key);
        self.list.files.push(item);
        if let Err(error) = self.save() {
            self.list.files.retain(|i| i.id != id);
            self.item_keys.remove(&blob);
            self.store.remove_blob(&blob);
            return Err(error);
        }
        Ok(id)
    }

    // MARK: Adding and reading

    /// Encrypts files into the vault, one by one, the list saved after each so a crash loses nothing; a folder brings
    /// every file inside it, each remembering where it was. Each sealed copy is read back and checked against its file.
    pub fn add(&mut self, paths: &[PathBuf], into: Option<&str>) -> Added {
        let mut added = Added::default();
        let own = self.store.own_paths();
        let is_own = |path: &PathBuf| {
            let path = std::fs::canonicalize(path).unwrap_or_else(|_| path.clone());
            own.iter().any(|mine| path.starts_with(mine))
        };
        for source in paths {
            let (items, skipped) = crate::vault::Store::expand(std::slice::from_ref(source));
            added.skipped += skipped;
            if items.first().is_some_and(|(_, folder)| folder.is_some()) {
                added.originals.folders.push(source.clone());
            }
            for (path, folder) in items {
                // The vault's own files stay out: they'd be offered back as originals to delete.
                if is_own(&path) {
                    added.skipped += 1;
                    continue;
                }
                // Dropped into a folder that's open: it goes in there, keeping any folders it brought.
                let place: Vec<&str> = [into, folder.as_deref()].into_iter().flatten().collect();
                let place = (!place.is_empty()).then(|| place.join("/"));
                let sealed = self.store.add_file(&path, place.as_deref(), self.slot, &self.names, now());
                let (item, sealed) = match sealed {
                    Ok(made) => made,
                    Err(error) => {
                        added.failed.push((path, error));
                        continue;
                    }
                };
                let checked = Originals::matches(&self.store, &item, &path, &sealed.key);
                match self.take_in(item, sealed) {
                    Ok(id) => {
                        added.items.push(id);
                        if checked { added.originals.files.push(path) } else { added.unchecked.push(path) }
                    }
                    Err(error) => added.failed.push((path, error)),
                }
            }
        }
        added
    }

    /// Something held only in memory (an email's attachment) sealed in as a file of its own.
    pub fn add_data(&mut self, data: &[u8], name: &str, folder: Option<&str>) -> Result<Uuid, Error> {
        let uti = kinds::uti_for_name(name);
        let mut item = Item::new(name, uti, data.len() as u64, now());
        item.folder = folder.map(Into::into);
        let streamed = kinds::streams(data.len() as u64, uti);
        let sealed = self.store.put(data, streamed, self.slot, &self.names)?;
        item.chunked = streamed.then_some(true);
        item.sealed_as = Some(sealed.blob);
        self.take_in(item, sealed)
    }

    /// A new note (Markdown) or secret (JSON), in `folder`. Returns it, to be opened for editing.
    pub fn new_entry(&mut self, entry: Entry, name: &str, content: &[u8], folder: Option<&str>) -> Result<Uuid, Error> {
        let uti = if entry == Entry::Note { "net.daringfireball.markdown" } else { "public.json" };
        let now = now();
        let mut item = Item::new(name, uti, content.len() as u64, now);
        item.folder = folder.map(Into::into);
        item.modified_at = Some(now);
        item.entry = Some(entry);
        let sealed = self.store.put(content, false, self.slot, &self.names)?;
        item.sealed_as = Some(sealed.blob);
        self.take_in(item, sealed)
    }

    fn seal_key(&self, sealed_as: Option<Uuid>) -> Result<(Uuid, &crate::crypto::Key), Error> {
        let sealed_as = sealed_as.ok_or(VaultError::Damaged)?;
        Ok((sealed_as, self.item_keys.get(&sealed_as).ok_or(VaultError::Damaged)?))
    }

    /// An item's current contents.
    pub fn read(&self, id: &Uuid) -> Result<Zeroizing<Vec<u8>>, Error> {
        let item = self.item(id).ok_or(Error::NotFound)?;
        let (sealed_as, key) = self.seal_key(item.sealed_as)?;
        Ok(self.store.contents(&sealed_as, key, item.is_chunked(), item.size)?)
    }

    pub fn read_version(&self, id: &Uuid, version: &Uuid) -> Result<Zeroizing<Vec<u8>>, Error> {
        let item = self.item(id).ok_or(Error::NotFound)?;
        let version = item.versions.iter().flatten().find(|v| v.id == *version).ok_or(Error::NotFound)?;
        let (sealed_as, key) = self.seal_key(version.sealed_as)?;
        Ok(self.store.contents(&sealed_as, key, version.is_chunked(), version.size)?)
    }

    /// An item's contents written to a place outside the vault (a copy the person saves, or a working copy), with its
    /// own dates.
    pub fn export_item(&self, id: &Uuid, to: &Path) -> Result<(), Error> {
        let item = self.item(id).ok_or(Error::NotFound)?;
        crate::export::take_one(self, item, to).map_err(|failure| match failure {
            crate::export::ItemFailure::Damaged(error) => Error::Vault(error),
            crate::export::ItemFailure::Writing(error) => Error::Io(error),
        })
    }

    /// Deleted, versions too. The list first: a sealed file the list forgets is harmless, a listed one that is gone is
    /// not.
    pub fn delete(&mut self, id: &Uuid) -> Result<(), Error> {
        let blobs = self.item(id).ok_or(Error::NotFound)?.blobs();
        self.change(|list| list.files.retain(|i| i.id != *id))?;
        self.forget_blobs(&blobs);
        Ok(())
    }

    fn forget_blobs(&mut self, blobs: &[Uuid]) {
        for blob in blobs {
            self.store.remove_blob(blob);
            self.item_keys.remove(blob);
        }
    }

    // MARK: Versions

    /// The current contents of an item, as a version: it keeps its blob and key.
    fn as_version(item: &Item) -> Version {
        Version { id: Uuid::new_v4(), date: item.changed_at(), size: item.size, chunked: item.chunked, sealed_as: item.sealed_as, key: None }
    }

    /// New contents for an item, and a new name if given. What it held before is kept as a version, unless it was
    /// itself changed less than ten minutes ago; at most 20 are kept.
    pub fn update(&mut self, id: &Uuid, contents: Contents, name: Option<&str>) -> Result<(), Error> {
        let at = self.index(id)?;
        let mut item = self.list.files[at].clone();
        let now = now();
        // Blobs to delete once the list no longer names them: the contents replaced, and versions past 20.
        let mut unused: Vec<Uuid> = Vec::new();
        if item.changed_at() < now - VERSION_AFTER {
            let versions = item.versions.get_or_insert_with(Vec::new);
            versions.push(Self::as_version(&self.list.files[at]));
            while versions.len() > MOST_VERSIONS {
                unused.extend(versions.remove(0).sealed_as);
            }
        } else {
            unused.extend(item.sealed_as);
        }
        let sealed = match contents {
            Contents::File(path) if kinds::streams(fs::metadata(path)?.len(), &item.uti) => {
                let (sealed, size) = self.store.put_streaming(path, self.slot, &self.names)?;
                item.size = size;
                item.chunked = Some(true);
                sealed
            }
            contents => {
                let data = match contents {
                    Contents::Bytes(data) => Zeroizing::new(data.to_vec()),
                    Contents::File(path) => Zeroizing::new(fs::read(path)?),
                };
                item.size = data.len() as u64;
                item.chunked = None;
                self.store.put(&data, false, self.slot, &self.names)?
            }
        };
        let blob = sealed.blob;
        item.sealed_as = Some(blob);
        item.modified_at = Some(now);
        if let Some(name) = name {
            item.name = name.to_owned();
        }
        self.item_keys.insert(blob, sealed.key);
        if let Err(error) = self.change(|list| list.files[at] = item) {
            self.forget_blobs(&[blob]);
            return Err(error);
        }
        self.forget_blobs(&unused);
        Ok(())
    }

    /// Puts an earlier version back; what was current becomes the newest version, so nothing is lost.
    pub fn restore_version(&mut self, id: &Uuid, version: &Uuid) -> Result<(), Error> {
        let at = self.index(id)?;
        let mut item = self.list.files[at].clone();
        let chosen = item.versions.iter().flatten().find(|v| v.id == *version).cloned().ok_or(Error::NotFound)?;
        let current = Self::as_version(&item);
        let versions = item.versions.get_or_insert_with(Vec::new);
        versions.retain(|v| v.id != *version);
        versions.push(current);
        item.size = chosen.size;
        item.chunked = chosen.chunked;
        item.sealed_as = chosen.sealed_as;
        item.modified_at = Some(now());
        self.change(|list| list.files[at] = item)
    }

    /// An earlier version taken out of an item's list, and its sealed file deleted.
    pub fn drop_version(&mut self, id: &Uuid, version: &Uuid) -> Result<(), Error> {
        let at = self.index(id)?;
        let gone = self.list.files[at].versions.iter().flatten().find(|v| v.id == *version).ok_or(Error::NotFound)?.sealed_as;
        self.change(|list| {
            if let Some(versions) = list.files[at].versions.as_mut() {
                versions.retain(|v| v.id != *version);
            }
        })?;
        self.forget_blobs(&gone.into_iter().collect::<Vec<_>>());
        Ok(())
    }

    /// Damaged current contents swapped for an earlier version that still opens; the damaged blob goes.
    pub fn fall_back(&mut self, id: &Uuid, version: &Uuid) -> Result<(), Error> {
        let at = self.index(id)?;
        let mut item = self.list.files[at].clone();
        let damaged = item.sealed_as;
        let chosen = item.versions.iter().flatten().find(|v| v.id == *version).cloned().ok_or(Error::NotFound)?;
        if let Some(versions) = item.versions.as_mut() {
            versions.retain(|v| v.id != *version);
        }
        item.size = chosen.size;
        item.chunked = chosen.chunked;
        item.sealed_as = chosen.sealed_as;
        item.modified_at = Some(now());
        self.change(|list| list.files[at] = item)?;
        self.forget_blobs(&damaged.into_iter().collect::<Vec<_>>());
        Ok(())
    }

    /// Reads every item and every earlier version all the way through and lists what doesn't open (a disk fault, a
    /// crash midway, a file changed from outside). `progress` hears (done, total).
    pub fn check(&self, mut progress: impl FnMut(usize, usize)) -> Vec<Damage> {
        let total = self.list.files.iter().map(|i| 1 + i.versions.as_ref().map_or(0, Vec::len)).sum();
        let mut done = 0;
        let mut found = Vec::new();
        let intact = |sealed_as: Option<Uuid>, streamed: bool, size: u64| {
            self.seal_key(sealed_as).is_ok_and(|(id, key)| self.store.is_intact(&id, key, streamed, size))
        };
        for item in &self.list.files {
            let versions: Vec<(&Version, bool)> =
                item.versions.iter().flatten().map(|v| (v, intact(v.sealed_as, v.is_chunked(), v.size))).collect();
            if !intact(item.sealed_as, item.is_chunked(), item.size) {
                let fallback = versions.iter().rev().find(|(_, ok)| *ok).map(|(v, _)| v.id);
                found.push(Damage { item: item.id, version: None, fallback });
            }
            for (version, ok) in &versions {
                if !ok {
                    found.push(Damage { item: item.id, version: Some(version.id), fallback: None });
                }
            }
            done += 1 + versions.len();
            progress(done, total);
        }
        found
    }

    #[doc(hidden)]
    /// Tests only: makes an item look last changed `seconds` ago, as `backdate` does in the Mac's DEBUG builds.
    pub fn backdate_for_tests(&mut self, id: &Uuid, seconds: f64) -> Result<(), Error> {
        let at = self.index(id)?;
        let when = now() - seconds;
        self.change(|list| list.files[at].modified_at = Some(when))
    }

    // MARK: Names, tags and folders

    pub fn rename(&mut self, id: &Uuid, name: &str) -> Result<(), Error> {
        let name = name.trim();
        if name.is_empty() {
            return Ok(());
        }
        let at = self.index(id)?;
        self.change(|list| list.files[at].name = name.to_owned())
    }

    pub fn set_tags(&mut self, id: &Uuid, tags: &[String]) -> Result<(), Error> {
        let at = self.index(id)?;
        self.change(|list| list.files[at].tags = (!tags.is_empty()).then(|| tags.to_vec()))
    }

    /// Every tag in use, A to Z.
    pub fn tags(&self) -> Vec<String> {
        let all: HashSet<&String> = self.list.files.iter().flat_map(|i| i.tag_list()).collect();
        sorted(all.into_iter().cloned().collect())
    }

    /// Every folder: those made, and those that hold something, with each one's parents.
    pub fn folders(&self) -> Vec<String> {
        let mut all: HashSet<String> = self.list.folders.iter().cloned().collect();
        for path in self.list.files.iter().filter_map(|i| i.folder.as_deref()) {
            let mut parts: Vec<&str> = path.split('/').filter(|p| !p.is_empty()).collect();
            while !parts.is_empty() {
                all.insert(parts.join("/"));
                parts.pop();
            }
        }
        sorted(all.into_iter().collect())
    }

    /// "/" divides a folder's path ("Taxes/2025"), so one typed in a name (a date, 26/10/26) becomes "∕", which looks
    /// the same.
    pub fn folder_name(typed: &str) -> String {
        typed.replace('/', "\u{2215}").trim().to_owned()
    }

    pub fn make_folder(&mut self, name: &str, parent: Option<&str>) -> Result<(), Error> {
        let name = Self::folder_name(name);
        if name.is_empty() {
            return Ok(());
        }
        let path = [parent, Some(name.as_str())].into_iter().flatten().collect::<Vec<_>>().join("/");
        if self.folders().contains(&path) {
            return Ok(());
        }
        self.change(|list| list.folders.push(path))
    }

    pub fn move_items(&mut self, ids: &[Uuid], folder: Option<&str>) -> Result<(), Error> {
        self.change(|list| {
            for item in list.files.iter_mut().filter(|i| ids.contains(&i.id)) {
                item.folder = folder.map(Into::into);
            }
        })
    }

    /// Renames a folder, carrying everything inside it along. Returns its new path, or None when nothing changed.
    pub fn rename_folder(&mut self, path: &str, name: &str) -> Result<Option<String>, Error> {
        let name = Self::folder_name(name);
        if name.is_empty() {
            return Ok(None);
        }
        let parent = path.rsplit_once('/').map(|(p, _)| p);
        let new = parent.map_or(name.clone(), |p| format!("{p}/{name}"));
        Ok(self.relocate(path, &new)?.then_some(new))
    }

    /// A folder, with everything in it, into another folder (None: the top).
    pub fn move_folder(&mut self, path: &str, into: Option<&str>) -> Result<(), Error> {
        if into == Some(path) {
            return Ok(());
        }
        if into.is_some_and(|p| p.starts_with(&format!("{path}/"))) {
            return Err(Error::FolderIntoItself);
        }
        let name = path.rsplit('/').next().unwrap_or(path);
        let new = into.map_or(name.to_owned(), |p| format!("{p}/{name}"));
        self.relocate(path, &new).map(|_| ())
    }

    /// A folder and everything below it to a new path. False when it was already there.
    fn relocate(&mut self, path: &str, new: &str) -> Result<bool, Error> {
        if new == path {
            return Ok(false);
        }
        if self.folders().iter().any(|f| f == new) {
            return Err(Error::FolderExists(new.rsplit('/').next().unwrap_or(new).to_owned()));
        }
        let inside = format!("{path}/");
        let moved = |p: &str| {
            if p == path { new.to_owned() } else if let Some(rest) = p.strip_prefix(&inside) { format!("{new}/{rest}") } else { p.to_owned() }
        };
        self.change(|list| {
            list.folders = list.folders.iter().map(|f| moved(f)).collect();
            for item in &mut list.files {
                if let Some(folder) = &item.folder {
                    item.folder = Some(moved(folder));
                }
            }
        })?;
        Ok(true)
    }

    /// Deletes a folder and everything inside it, versions too.
    pub fn delete_folder(&mut self, path: &str) -> Result<(), Error> {
        let gone: Vec<Uuid> = self.list.files.iter().filter(|i| i.is_inside(path)).flat_map(Item::blobs).collect();
        let inside = format!("{path}/");
        self.change(|list| {
            list.files.retain(|i| !i.is_inside(path));
            list.folders.retain(|f| f != path && !f.starts_with(&inside));
        })?;
        self.forget_blobs(&gone);
        Ok(())
    }

    // MARK: Settings kept with the vault

    /// Shown in screenshots and screen sharing once open: kept sealed in the vault, so nothing else can switch the
    /// protection off unseen.
    pub fn show_in_capture(&self) -> bool {
        self.list.show_in_capture
    }

    pub fn set_show_in_capture(&mut self, on: bool) -> Result<(), Error> {
        self.change(|list| list.show_in_capture = on)
    }

    // MARK: Keys

    /// The password key of a slot as it's opened here. A vault locked to a Mac has its password keys sealed again by
    /// that Mac's Secure Enclave, which this computer can't undo.
    /// The password key of a slot as it's opened here: unsealed by this PC's lock when the vault is locked to it.
    /// `NotThisComputer` when it's locked to a Mac, or to another PC.
    fn password_key(&self, slot: crate::vault::Slot) -> Result<Vec<u8>, Error> {
        let lock = self.store.password_lock()?;
        self.store.read_password_key(slot, lock.as_ref()).ok_or_else(|| std::io::Error::from(std::io::ErrorKind::NotFound).into())
    }

    /// Whether `password` opens the other slot: one password, one slot. Checked the same from either slot. It answers a
    /// guess at the other slot's password, so each action that checks counts it as a wrong try first (`TryLimit`).
    fn opens_other(&self, password: &str) -> bool {
        let lock = self.store.password_lock().ok().flatten();
        self.store
            .read_password_key(self.slot.other(), lock.as_ref())
            .is_some_and(|other| open_with_password(&other, password).is_ok())
    }

    /// A new password for the open slot, after the current one is given again.
    pub fn change_password(&mut self, current: &str, new: &str) -> Result<(), Error> {
        self.store.try_limit().count_guess()?;
        let sealed = self.password_key(self.slot)?;
        open_with_password(&sealed, current)?;
        if self.opens_other(new) {
            return Err(VaultError::SameAsOther.into());
        }
        let lock = self.store.password_lock()?;
        let written = self.store.seal_password_key(seal_with_password(&self.key, new, self.store.cost())?, lock.as_ref())?;
        Ok(self.store.write_key(&self.store.slot_file(self.slot, "password.key"), &written)?)
    }

    /// After a recovery key or kit: a new password. A vault locked to a Mac comes unlocked here, as Windows can't hold a
    /// Mac's lock: mac.key goes and the new password key is written plain. One locked to another PC has its lock moved
    /// to this one (or taken off, with no TPM here). Either way the other slot's password key stays sealed to the
    /// computer it was locked to (same size and layout as ever); its own recovery key brings it back.
    pub fn set_password_after_recovery(&mut self, new: &str) -> Result<(), Error> {
        if !self.must_set_password {
            return Ok(());
        }
        self.store.try_limit().count_guess()?;
        if self.opens_other(new) {
            return Err(VaultError::SameAsOther.into());
        }
        let written = seal_with_password(&self.key, new, self.store.cost())?;
        let lock = if self.store.is_locked_to_a_mac() {
            fs::remove_file(self.store.mac_key())?;
            None
        } else if self.store.is_locked_to_a_pc() {
            self.store.move_pc_lock_here()?
        } else {
            None
        };
        let written = self.store.seal_password_key(written, lock.as_ref())?;
        self.store.write_key(&self.store.slot_file(self.slot, "password.key"), &written)?;
        self.must_set_password = false;
        Ok(())
    }

    /// A decoy password: the other slot becomes a new, empty vault it opens, with a recovery key of its own (returned,
    /// to be shown once). Whatever the other slot held is deleted. The same from either slot.
    pub fn set_other_slot(&mut self, password: &str) -> Result<String, Error> {
        self.store.try_limit().count_guess()?;
        let mine = self.password_key(self.slot)?;
        if open_with_password(&mine, password).is_ok() {
            return Err(VaultError::SameAsOther.into());
        }
        let code = make_recovery_code();
        self.replace_other_slot(password, &code)?;
        Ok(code)
    }

    /// No decoy: the other slot becomes one whose passwords nobody knows, and what it held is deleted.
    pub fn reset_other_slot(&mut self) -> Result<(), Error> {
        self.password_key(self.slot)?;
        self.replace_other_slot(&unknowable(), &unknowable())
    }

    fn replace_other_slot(&mut self, password: &str, code: &str) -> Result<(), Error> {
        // Touch ID or Windows Hello that opened the slot being replaced would open nothing now.
        let mut removed = false;
        if !self.touch_id_is_mine() && self.store.touch_id_key().exists() {
            fs::remove_file(self.store.touch_id_key())?;
            removed = true;
        }
        if !self.hello_is_mine() && self.store.hello_key().exists() {
            fs::remove_file(self.store.hello_key())?;
            removed = true;
        }
        if removed {
            fsx::even_dates(&self.store.key_files(), std::time::SystemTime::now());
        }
        let other = self.slot.other();
        self.store.remove_all(other, &self.names);
        self.store.make_slot(other, password, code, &self.cover)?;
        Ok(())
    }

    // MARK: Lock to this PC

    /// Whether the vault is locked to a PC (this one, since it's open here with its password, or another after a
    /// recovery key).
    pub fn is_locked_to_a_pc(&self) -> bool {
        self.store.is_locked_to_a_pc()
    }

    /// Locks both slots' password keys to this PC's TPM: either slot can, as it needs no slot key. Makes a new recovery
    /// key for this vault, as otherwise a dead PC would take the vault with it; returned, to be shown once. The other
    /// slot's recovery key is never locked, so it opens that slot anywhere. None when it was already on.
    pub fn lock_to_this_pc(&mut self) -> Result<Option<String>, Error> {
        if self.store.is_locked_to_a_pc() {
            return Ok(None);
        }
        if self.store.is_locked_to_a_mac() {
            return Err(Error::LockedElsewhere);
        }
        if !crate::tpm::available() {
            return Err(Error::NoTpm);
        }
        let code = self.new_recovery_key()?;
        self.store.lock_to_this_pc()?;
        Ok(Some(code))
    }

    /// The lock off: both password keys back as they were, and the TPM key deleted.
    pub fn unlock_from_this_pc(&mut self) -> Result<(), Error> {
        self.store.unlock_from_this_pc()
    }

    // MARK: Windows Hello

    /// 32 random bytes for Windows Hello to sign, to turn it on.
    pub fn hello_new_challenge() -> [u8; 32] {
        crate::hello::new_challenge()
    }

    /// Windows Hello opens this vault from now on: given the challenge, Windows Hello's signature of it and the
    /// credential's public key. It moves here from whichever vault had it.
    pub fn turn_on_hello(&mut self, challenge: &[u8], signature: &[u8], public_key: &[u8]) -> Result<(), Error> {
        if challenge.len() != 32 || public_key.is_empty() {
            return Err(VaultError::HelloUnavailable.into());
        }
        let wrapping = crate::hello::wrapping_key(signature)?;
        let file = crate::hello::HelloKey {
            challenge: crate::hello::encode(challenge),
            public_key: crate::hello::encode(public_key),
            vault_key: crate::hello::encode(&crate::crypto::seal(self.key.as_bytes(), &wrapping, None)?),
        };
        self.store.write_key(&self.store.hello_key(), &serde_json::to_vec(&file).map_err(std::io::Error::other)?)?;
        let fingerprint = crate::hello::fingerprint(public_key);
        self.change(|list| list.hello = fingerprint)
    }

    /// Windows Hello no longer opens this vault.
    pub fn turn_off_hello(&mut self) -> Result<(), Error> {
        if self.hello_is_mine() {
            fs::remove_file(self.store.hello_key())?;
            fsx::even_dates(&self.store.key_files(), std::time::SystemTime::now());
        }
        let none = crate::hello::none();
        self.change(|list| list.hello = none)
    }

    /// Whether the hello.key on disk opens this vault: its credential is the one this vault's list remembers.
    pub fn hello_is_mine(&self) -> bool {
        self.store
            .read_hello_key()
            .and_then(|file| crate::hello::decode(&file.public_key).ok())
            .is_some_and(|public_key| crate::hello::fingerprint(&public_key) == self.list.hello)
    }

    /// Whether the touchid.key on disk (written by the Mac) opens this slot: its public key is the one this slot's list
    /// remembers.
    pub fn touch_id_is_mine(&self) -> bool {
        #[derive(serde::Deserialize)]
        struct Sealed {
            #[serde(rename = "publicKey")]
            public_key: String,
        }
        let Ok(data) = fs::read(self.store.touch_id_key()) else { return false };
        serde_json::from_slice::<Sealed>(&data).is_ok_and(|s| s.public_key == self.list.touch_id)
    }

    /// A new recovery key for the open slot; the old one stops working. Returns it, to be shown once.
    pub fn new_recovery_key(&mut self) -> Result<String, Error> {
        let code = make_recovery_code();
        let written = seal_with_password(&self.key, &normalized_recovery_code(&code), self.store.cost())?;
        self.store.write_key(&self.store.slot_file(self.slot, "recovery.key"), &written)?;
        Ok(code)
    }

    // MARK: Emergency kit

    pub fn has_kit(&self) -> bool {
        self.list.kit_made != list::NEVER
    }

    /// When the kit was made, in seconds since 2001.
    pub fn kit_made(&self) -> Option<f64> {
        list::stamped(&self.list.kit_made)
    }

    /// A new emergency kit: `count` printed pieces, any `threshold` of which open this slot. Any kit before it stops
    /// working. Returns the pieces, written out, to be printed once.
    pub fn make_kit(&mut self, threshold: u8, count: u8) -> Result<Vec<String>, Error> {
        if !(2..=count).contains(&threshold) {
            return Err(Error::Kit(kit::KitProblem::NotEnough(threshold.max(2))));
        }
        // Wiped however this ends, an early error included.
        let mut secret = Zeroizing::new([0u8; kit::SECRET_LENGTH]);
        fill_random(secret.as_mut());
        let password = kit::password(&secret);
        let written = seal_with_password(&self.key, &password, self.store.cost())?;
        self.store.write_key(&self.store.slot_file(self.slot, "kit.key"), &written)?;
        let stamp = list::stamp(now());
        self.change(|list| {
            list.kit_made = stamp;
            list.kit_reminded = list::NEVER.into();
        })?;
        Ok(kit::split(&secret, threshold, count).iter().map(kit::code).collect())
    }

    /// The kit's file is sealed again under a secret nobody has: every slot always has one, so none goes missing.
    pub fn remove_kit(&mut self) -> Result<(), Error> {
        let written = seal_with_password(&self.key, &unknowable(), self.store.cost())?;
        self.store.write_key(&self.store.slot_file(self.slot, "kit.key"), &written)?;
        self.change(|list| list.kit_made = list::NEVER.into())
    }

    /// Once a year: are the pieces still with the right people? True once, when it's time to say so (and it's then
    /// remembered as said).
    pub fn kit_reminder_due(&mut self) -> Result<bool, Error> {
        let Some(made) = self.kit_made() else { return Ok(false) };
        let last = list::stamped(&self.list.kit_reminded).unwrap_or(made);
        if now() - last <= KIT_REMINDER {
            return Ok(false);
        }
        let stamp = list::stamp(now());
        self.change(|list| list.kit_reminded = stamp)?;
        Ok(true)
    }

    // MARK: Intruders

    pub fn intruder_entries(&self) -> Vec<intruder::Entry> {
        intruder::entries(&self.store, &self.list.intruder, self.slot)
    }

    /// Gone for both slots.
    pub fn delete_intruder(&self, id: &Uuid) -> Result<(), Error> {
        Ok(intruder::delete(&self.store, id)?)
    }

    pub fn clear_intruders(&self) -> Result<(), Error> {
        Ok(intruder::clear(&self.store)?)
    }

    // MARK: Search

    /// Reads every item whose words aren't known or have changed since, forgets removed ones, and seals the index.
    /// `extra` reads what only the platform can (PDFs, the text in pictures). Returns whether anything changed.
    pub fn refresh_search(&mut self, extra: Option<search::Extra>) -> Result<bool, Error> {
        let stale: Vec<&Item> = self
            .list
            .files
            .iter()
            .filter(|item| {
                search::reads(item)
                    && self.words.get(&item.id).is_none_or(|known| known.changed != item.changed_at() || known.size != item.size)
            })
            .collect();
        let present: HashSet<Uuid> = self.list.files.iter().map(|i| i.id).collect();
        let forgotten = self.words.keys().any(|id| !present.contains(id));
        if stale.is_empty() && !forgotten {
            return Ok(false);
        }
        let mut read = Vec::new();
        for item in stale {
            let Ok(data) = self.read(&item.id) else { continue };
            let text = search::words(item, &data, extra).unwrap_or_default();
            read.push((item.id, search::Entry { changed: item.changed_at(), size: item.size, text }));
        }
        self.words.extend(read);
        self.words.retain(|id, _| present.contains(id));
        let sealed = search::sealed(&self.words, &self.key)?;
        self.store.write_covered(&sealed, Covered::Search, self.slot, &self.cover)?;
        Ok(true)
    }

    /// Items whose name, tags or words hold `query`, as the list shows them.
    pub fn search(&self, query: &str) -> Vec<Uuid> {
        let query = query.trim();
        if query.is_empty() {
            return Vec::new();
        }
        self.list
            .files
            .iter()
            .filter(|item| {
                search::contains(&item.name, query)
                    || item.tag_list().iter().any(|t| search::contains(t, query))
                    || self.words.get(&item.id).is_some_and(|w| search::contains(&w.text, query))
            })
            .map(|item| item.id)
            .collect()
    }

    /// A piece of an item's words around `query`, for its row in the results.
    pub fn snippet(&self, id: &Uuid, query: &str) -> Option<String> {
        search::snippet(&self.words.get(id)?.text, query)
    }

    // MARK: Importing passwords

    /// Accounts from a password export, each a Login secret in the "Imported" folder, all saved in one go. An account
    /// already in the vault (same site and username) is skipped, so importing twice adds nothing twice. Returns how
    /// many were added and skipped.
    pub fn import_logins(&mut self, logins: &[Login]) -> Result<(usize, usize), Error> {
        let mut known: HashSet<String> = self
            .list
            .files
            .iter()
            .filter(|i| i.entry == Some(Entry::Secret))
            .filter_map(|item| {
                let data = self.read(&item.id).ok()?;
                let secret: Secret = serde_json::from_slice(&data).ok()?;
                (secret.template == Template::Login).then(|| {
                    format!("{}|{}", crate::import::site(secret.field("Website").unwrap_or("")), secret.field("Username").unwrap_or("").to_lowercase())
                })
            })
            .collect();
        let folder = "Imported";
        let (mut added, mut skipped) = (Vec::new(), 0);
        let now = now();
        for login in logins {
            if !known.insert(login.key()) {
                skipped += 1;
                continue;
            }
            let content = Zeroizing::new(serde_json::to_vec(&login.secret()).map_err(std::io::Error::other)?);
            let mut item = Item::new(&login.name(), "public.json", content.len() as u64, now);
            item.folder = Some(folder.into());
            item.modified_at = Some(now);
            item.entry = Some(Entry::Secret);
            match self.store.put(&content, false, self.slot, &self.names) {
                Ok(sealed) => {
                    item.sealed_as = Some(sealed.blob);
                    self.item_keys.insert(sealed.blob, sealed.key);
                    added.push(item);
                }
                Err(error) => {
                    self.forget_blobs(&added.iter().filter_map(|i| i.sealed_as).collect::<Vec<_>>());
                    return Err(error);
                }
            }
        }
        if added.is_empty() {
            return Ok((0, skipped));
        }
        let count = added.len();
        let blobs: Vec<Uuid> = added.iter().filter_map(|i| i.sealed_as).collect();
        let result = self.change(|list| {
            list.files.extend(added);
            if !list.folders.iter().any(|f| f == folder) {
                list.folders.push(folder.into());
            }
        });
        if let Err(error) = result {
            self.forget_blobs(&blobs);
            return Err(error);
        }
        Ok((count, skipped))
    }

    // MARK: Backups

    /// A backup of this vault while it's open. Nothing in this process can save to it meanwhile, because the backup
    /// holds it borrowed, so the file never names one it doesn't hold (the Mac counts saves and packs again instead).
    pub fn backup(&self, to: &Path) -> Result<(), Error> {
        crate::backup::make(&self.store, to)
    }

    /// Puts the vault back from a backup. The vault is locked first (it's given up here), so nothing still holding the
    /// old keys can write into the restored one. Returns where the vault it replaced was set aside.
    pub fn restore_backup(self, file: &Path) -> Result<Option<PathBuf>, Error> {
        let store = self.store.clone();
        drop(self);
        crate::backup::restore(&store, file)
    }

    // MARK: Ending

    /// The vault and every file in it, for good.
    pub fn wipe(self) -> Result<(), Error> {
        self.store.wipe()
    }
}

/// A to Z, ignoring case, numbers in order (close to the Mac's `localizedStandardCompare`).
fn sorted(mut names: Vec<String>) -> Vec<String> {
    fn key(text: &str) -> Vec<(u8, u64, String)> {
        let mut parts = Vec::new();
        let mut chars = text.chars().peekable();
        while let Some(&c) = chars.peek() {
            if c.is_ascii_digit() {
                let mut n = String::new();
                while let Some(&d) = chars.peek().filter(|d| d.is_ascii_digit()) {
                    n.push(d);
                    chars.next();
                }
                parts.push((0, n.parse().unwrap_or(u64::MAX), String::new()));
            } else {
                parts.push((1, 0, c.to_lowercase().collect()));
                chars.next();
            }
        }
        parts
    }
    names.sort_by(|a, b| key(a).cmp(&key(b)).then_with(|| a.cmp(b)));
    names
}
