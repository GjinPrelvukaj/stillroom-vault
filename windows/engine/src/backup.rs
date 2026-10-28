//! Backups (`Storage/Backup.swift`): one file holding the whole vault folder, in Stillroom's own plain format. Everything
//! in the folder is already sealed, so the file needs no sealing of its own; it opens with the vault's password. A
//! backup made on a Mac restores here and one made here restores on a Mac.
//!
//! The format is deliberately plain: the mark "STILLBK1", then each file as (path length u16, path, size u64, bytes),
//! then a zero length. Paths use "/". It holds nothing but regular files at simple paths inside the vault folder: no
//! links, no folders of its own, no paths that climb out, so unpacking can't be tricked into writing anywhere else.
//!
//! A restore is staged beside the vault, then swapped in (`fsx::swap_folders`), so a crash at any moment leaves a whole
//! vault: the old one, or the restored one with the old one beside it as "Store-before-restore-<time>" (never deleted).

use std::fs::{self, File};
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};

use uuid::Uuid;

use crate::export::is_device_name;
use crate::vault::{Slot, Store};
use crate::{fsx, Error};

pub const FILE_EXTENSION: &str = "stillroombackup";
const MARK: &[u8; 8] = b"STILLBK1";

/// A name like "Stillroom Backup 2026-10-23.stillroombackup", for a day written "2026-10-23".
pub fn suggested_name(day: &str) -> String {
    format!("Stillroom Backup {day}.{FILE_EXTENSION}")
}

/// Writes the whole vault folder into one file at `to`: to a temp file beside it first, then renamed into place, so
/// the last step is a rename on the same disk, never a half-copied file. A folder that isn't there isn't made.
pub fn make(store: &Store, to: &Path) -> Result<(), Error> {
    if !store.exists() {
        return Err(Error::NotFound);
    }
    let folder = to.parent().filter(|p| p.is_dir()).ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no such folder"))?;
    let temp = folder.join(format!(".{}.partial", Uuid::new_v4().hyphenated()));
    let written = (|| -> Result<(), Error> {
        let mut out = BufWriter::new(File::create(&temp)?);
        pack(store.root(), &mut out)?;
        let file = out.into_inner().map_err(|e| e.into_error())?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temp, to)?;
        Ok(())
    })();
    if written.is_err() {
        let _ = fs::remove_file(&temp);
    }
    written
}

/// Checks a file is a Stillroom backup (it unpacks to a folder holding both slots' password keys) without touching the
/// live vault.
pub fn check(file: &Path) -> Result<(), Error> {
    let (dir, _) = unpack(file, &std::env::temp_dir())?;
    let _ = fsx::remove_tree(&dir);
    Ok(())
}

/// Puts the vault back from a backup. Returns where the vault it replaced was set aside (None if there was none).
pub fn restore(store: &Store, file: &Path) -> Result<Option<PathBuf>, Error> {
    store.recover()?;
    let staged = stage(store, file)?;
    let root = store.root();
    let aside = if root.exists() {
        if let Err(error) = fsx::swap_folders(&staged, root) {
            // Nothing live was touched; the staged copy is only the backup's.
            let _ = fsx::remove_tree(&staged);
            return Err(error.into());
        }
        Some(staged)
    } else {
        fs::rename(&staged, root)?;
        None
    };
    // Only this account can list or read it, wherever the backup came from.
    crate::platform::protect_folder(root)?;
    Ok(aside)
}

/// The backup unpacked and checked on the vault's own disk, then renamed beside the vault under the name the current
/// vault takes once it's set aside. Nothing live is touched.
pub fn stage(store: &Store, file: &Path) -> Result<PathBuf, Error> {
    let parent = store.root().parent().ok_or(Error::NotFound)?;
    fs::create_dir_all(parent)?;
    let (dir, vault) = unpack(file, parent)?;
    let spot = aside_name(store.root());
    let moved = fs::rename(&vault, &spot);
    let _ = fsx::remove_tree(&dir);
    moved?;
    Ok(spot)
}

/// "Store-before-restore-<UTC time>", beside the vault, made unique with "-2", "-3"…
pub fn aside_name(root: &Path) -> PathBuf {
    let parent = root.parent().unwrap_or(root);
    let seconds = (crate::now() + crate::APPLE_EPOCH).max(0.0) as i64;
    let (days, day_seconds) = (seconds.div_euclid(86_400), seconds.rem_euclid(86_400));
    let day = civil(days);
    let base = format!(
        "Store-before-restore-{day}-{:02}{:02}{:02}",
        day_seconds / 3600,
        day_seconds % 3600 / 60,
        day_seconds % 60
    );
    let mut spot = parent.join(&base);
    let mut n = 2;
    while spot.exists() || fsx::swapping(&spot).exists() {
        spot = parent.join(format!("{base}-{n}"));
        n += 1;
    }
    spot
}

fn civil(days: i64) -> String {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    format!("{:04}-{month:02}-{day:02}", yoe + era * 400 + i64::from(month <= 2))
}

// MARK: The format

/// Streams every regular file under `folder` into `out`; big videos never sit whole in memory.
fn pack(folder: &Path, out: &mut impl Write) -> Result<(), Error> {
    out.write_all(MARK)?;
    let mut files = Vec::new();
    walk(folder, "", &mut files)?;
    for (path, relative) in files {
        if !is_safe_path(&relative) {
            continue;
        }
        let mut input = File::open(&path)?;
        let size = input.metadata()?.len();
        out.write_all(&(relative.len() as u16).to_be_bytes())?;
        out.write_all(relative.as_bytes())?;
        out.write_all(&size.to_be_bytes())?;
        let copied = io::copy(&mut (&mut input).take(size), out)?;
        if copied != size {
            return Err(io::Error::other("a file changed while it was being backed up").into());
        }
    }
    out.write_all(&0u16.to_be_bytes())?;
    Ok(())
}

/// Every plain file below `folder`, with its path from there ("a/list"). Links are left out.
fn walk(folder: &Path, prefix: &str, files: &mut Vec<(PathBuf, String)>) -> io::Result<()> {
    let mut entries: Vec<_> = fs::read_dir(folder)?.collect::<Result<_, _>>()?;
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let meta = fs::symlink_metadata(entry.path())?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let relative = if prefix.is_empty() { name } else { format!("{prefix}/{name}") };
        if meta.file_type().is_symlink() {
            continue;
        }
        if meta.is_dir() {
            walk(&entry.path(), &relative, files)?;
        } else if meta.is_file() {
            files.push((entry.path(), relative));
        }
    }
    Ok(())
}

/// Unpacks into a fresh folder inside `near` (a folder named Store inside it). `NotABackup` for anything that isn't
/// exactly what `pack` writes, or that has no password key.
fn unpack(file: &Path, near: &Path) -> Result<(PathBuf, PathBuf), Error> {
    let dir = near.join(format!(".unpack-{}", Uuid::new_v4().hyphenated()));
    let vault = dir.join("Store");
    let unpacked = (|| -> Result<(), Error> {
        let input = File::open(file).map_err(|_| Error::NotABackup)?;
        let total = input.metadata()?.len();
        let mut input = BufReader::new(input);
        let mut mark = [0u8; 8];
        input.read_exact(&mut mark).map_err(|_| Error::NotABackup)?;
        if &mark != MARK {
            return Err(Error::NotABackup);
        }
        fs::create_dir_all(&vault)?;
        let mut at = MARK.len() as u64;
        loop {
            let length = u16::from_be_bytes(read_exact(&mut input)?) as usize;
            at += 2;
            if length == 0 {
                break;
            }
            let mut raw = vec![0u8; length];
            input.read_exact(&mut raw).map_err(|_| Error::NotABackup)?;
            at += length as u64;
            let path = String::from_utf8(raw).map_err(|_| Error::NotABackup)?;
            if !is_safe_path(&path) {
                return Err(Error::NotABackup);
            }
            let size = u64::from_be_bytes(read_exact(&mut input)?);
            at += 8;
            if size > total.saturating_sub(at) {
                return Err(Error::NotABackup);
            }
            let target = path.split('/').fold(vault.clone(), |p, part| p.join(part));
            fs::create_dir_all(target.parent().ok_or(Error::NotABackup)?)?;
            // A path given twice would mean a doctored file.
            let mut out = File::options().write(true).create_new(true).open(&target).map_err(|_| Error::NotABackup)?;
            let copied = io::copy(&mut (&mut input).take(size), &mut out)?;
            if copied != size {
                return Err(Error::NotABackup);
            }
            at += size;
        }
        let keys = Slot::ALL.iter().all(|slot| {
            fs::symlink_metadata(vault.join(slot.letter()).join("password.key")).is_ok_and(|m| m.is_file())
        });
        if !keys || !is_plain_tree(&vault) {
            return Err(Error::NotABackup);
        }
        Ok(())
    })();
    match unpacked {
        Ok(()) => Ok((dir, vault)),
        Err(error) => {
            let _ = fsx::remove_tree(&dir);
            Err(match error {
                Error::Io(_) => Error::NotABackup,
                other => other,
            })
        }
    }
}

fn read_exact<const N: usize>(input: &mut impl Read) -> Result<[u8; N], Error> {
    let mut bytes = [0u8; N];
    input.read_exact(&mut bytes).map_err(|_| Error::NotABackup)?;
    Ok(bytes)
}

/// A path inside the vault folder as the vault writes them: a few plain names, letters, digits, dots, dashes. On
/// Windows also no device name (CON, NUL…) and no name ending in a dot, which Windows would quietly change.
fn is_safe_path(path: &str) -> bool {
    let parts: Vec<&str> = path.split('/').collect();
    !parts.is_empty()
        && parts.len() <= 3
        && parts.iter().all(|part| {
            !part.is_empty()
                && *part != "."
                && *part != ".."
                && part.chars().count() <= 120
                && part.chars().all(|c| c.is_ascii_alphanumeric() || ".-_".contains(c))
                && !part.ends_with('.')
                && !is_device_name(part)
        })
}

/// Only plain files and folders, the folder itself included: no links or other reparse points anywhere.
fn is_plain_tree(folder: &Path) -> bool {
    fn plain(meta: &fs::Metadata) -> bool {
        #[cfg(windows)]
        {
            use std::os::windows::fs::MetadataExt;
            const REPARSE_POINT: u32 = 0x400;
            if meta.file_attributes() & REPARSE_POINT != 0 {
                return false;
            }
        }
        !meta.file_type().is_symlink() && (meta.is_dir() || meta.is_file())
    }
    let Ok(meta) = fs::symlink_metadata(folder) else { return false };
    if !plain(&meta) || !meta.is_dir() {
        return false;
    }
    let Ok(entries) = fs::read_dir(folder) else { return false };
    entries.flatten().all(|entry| {
        let Ok(meta) = fs::symlink_metadata(entry.path()) else { return false };
        plain(&meta) && (!meta.is_dir() || is_plain_tree(&entry.path()))
    })
}
