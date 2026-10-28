//! What was added from disk, once it's safely in (`Storage/Originals.swift`): only files whose sealed copy read back byte
//! for byte, so they can be deleted for good without losing anything.

use std::collections::HashSet;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::blob::ChunkedReader;
use crate::crypto::Key;
use crate::list::Item;
use crate::vault::Store;

#[derive(Clone, Debug, Default)]
pub struct Originals {
    /// Files whose sealed copy was checked against them.
    pub files: Vec<PathBuf>,
    /// Folders added whole. One goes whole only when every file in it is among `files`; otherwise just its checked
    /// files go, and anything that never went in (hidden files, links) stays where it is.
    pub folders: Vec<PathBuf>,
}

/// Files the system leaves in folders that never go in, and needn't keep a folder: Finder's and Explorer's.
const LEFT_BY_THE_SYSTEM: &[&str] = &[".DS_Store", "desktop.ini", "Thumbs.db"];

impl Originals {
    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }

    /// Whether a sealed copy reads back exactly as the file it came from: same size, same SHA-256. Streamed a MiB at a
    /// time on both sides, so a big video is never whole in memory.
    pub fn matches(store: &Store, item: &Item, original: &Path, key: &Key) -> bool {
        let Some(sealed_as) = item.sealed_as else { return false };
        let Ok(mut source) = File::open(original) else { return false };
        if source.metadata().map(|m| m.len()).ok() != Some(item.size) {
            return false;
        }
        let mut theirs = Sha256::new();
        let mut buffer = vec![0u8; 1 << 20];
        loop {
            match source.read(&mut buffer) {
                Ok(0) => break,
                Ok(n) => theirs.update(&buffer[..n]),
                Err(_) => return false,
            }
        }
        let mut ours = Sha256::new();
        if item.is_chunked() {
            let Ok(reader) = ChunkedReader::open(&store.blob(&sealed_as), key, &sealed_as, item.size) else { return false };
            let mut at = 0;
            while at < item.size {
                let Ok(piece) = reader.read(at..(at + reader.chunk_size()).min(item.size)) else { return false };
                ours.update(&piece);
                at += reader.chunk_size();
            }
        } else {
            let Ok(data) = store.contents(&sealed_as, key, false, item.size) else { return false };
            ours.update(&data);
        }
        theirs.finalize() == ours.finalize()
    }

    /// What actually gets removed: covered folders whole, and every other checked file on its own.
    pub fn removals(&self) -> Vec<PathBuf> {
        let checked: HashSet<PathBuf> = self.files.iter().map(|p| canonical(p)).collect();
        let whole: Vec<&PathBuf> = self.folders.iter().filter(|f| covered(f, &checked)).collect();
        let inside: Vec<PathBuf> = whole.iter().map(|f| canonical(f)).collect();
        let mut out: Vec<PathBuf> = whole.into_iter().cloned().collect();
        out.extend(self.files.iter().filter(|f| !inside.iter().any(|folder| canonical(f).starts_with(folder))).cloned());
        out
    }

    /// Deleted for good, skipping the Recycle Bin. Returns the names that couldn't be.
    pub fn delete(&self) -> Vec<String> {
        self.removals()
            .into_iter()
            .filter_map(|path| {
                let gone = if path.is_dir() { fs::remove_dir_all(&path) } else { fs::remove_file(&path) };
                gone.is_err().then(|| path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default())
            })
            .collect()
    }
}

fn canonical(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

/// Every file in the folder, hidden ones too, is a checked one (the system's own leftovers aside). A link, or any file
/// that didn't go in, keeps the folder.
fn covered(folder: &Path, checked: &HashSet<PathBuf>) -> bool {
    let Ok(entries) = fs::read_dir(folder) else { return false };
    for entry in entries {
        let Ok(entry) = entry else { return false };
        let path = entry.path();
        let Ok(meta) = fs::symlink_metadata(&path) else { return false };
        if meta.file_type().is_symlink() {
            return false;
        }
        if meta.is_dir() {
            if !covered(&path, checked) {
                return false;
            }
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        if LEFT_BY_THE_SYSTEM.contains(&name.as_str()) || (meta.is_file() && checked.contains(&canonical(&path))) {
            continue;
        }
        return false;
    }
    true
}
