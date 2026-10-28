//! The file system as the vault needs it on Windows: writes that land whole or not at all, dates evened across files
//! (so a copy of the folder doesn't show which was written last), and folders swapped without a moment with neither.
//!
//! The Mac swaps two folders in one step (`renamex_np` with `RENAME_SWAP`). Windows has no such call, so a swap here is
//! three renames through a marker name, and `recover_swap` finishes or undoes one a crash cut short. Every caller of
//! `swap_folders` runs `recover_swap` before it looks at the folder again (docs/SECURITY.md rule 7).

use std::fs::{self, File, FileTimes, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// Writes `data` beside `path`, flushed to disk, then renames it into place: a crash leaves the old file or the new
/// one, never half of one. Folders on the way are made.
pub fn write_atomic(path: &Path, data: &[u8]) -> io::Result<()> {
    let folder = path.parent().ok_or_else(|| io::Error::other("no folder"))?;
    fs::create_dir_all(folder)?;
    let temp = folder.join(format!(".{}.partial", uuid::Uuid::new_v4().hyphenated()));
    let written = (|| {
        let mut file = File::create(&temp)?;
        file.write_all(data)?;
        file.sync_all()?;
        drop(file);
        // Replaces what's there in one step (MoveFileEx with MOVEFILE_REPLACE_EXISTING).
        fs::rename(&temp, path)
    })();
    if written.is_err() {
        let _ = fs::remove_file(&temp);
    }
    written
}

/// A file or folder opened just to set its dates. A folder needs FILE_FLAG_BACKUP_SEMANTICS to be opened at all.
fn open_for_dates(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        const FILE_WRITE_ATTRIBUTES: u32 = 0x100;
        const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x0200_0000;
        options.access_mode(FILE_WRITE_ATTRIBUTES).custom_flags(FILE_FLAG_BACKUP_SEMANTICS);
    }
    #[cfg(not(windows))]
    options.write(true);
    options.open(path)
}

/// Gives a file or folder these dates: made (where the system keeps that) and last changed.
pub fn set_dates(path: &Path, created: Option<SystemTime>, modified: SystemTime) -> io::Result<()> {
    let mut times = FileTimes::new().set_modified(modified).set_accessed(modified);
    #[cfg(windows)]
    if let Some(created) = created {
        use std::os::windows::fs::FileTimesExt;
        times = times.set_created(created);
    }
    #[cfg(not(windows))]
    let _ = created;
    open_for_dates(path)?.set_times(times)
}

/// Every one of `paths` that exists given the same made and changed date.
pub fn even_dates(paths: &[PathBuf], date: SystemTime) {
    for path in paths {
        if path.exists() {
            let _ = set_dates(path, Some(date), date);
        }
    }
}

/// The name a folder has while it's being swapped out.
pub fn swapping(live: &Path) -> PathBuf {
    let mut name = live.file_name().unwrap_or_default().to_os_string();
    name.push(".swapping");
    live.with_file_name(name)
}

/// Swaps two folders on one disk: afterwards `live` holds what `staged` held, and `staged` what `live` held.
///
/// 1. `live` is renamed to its swapping name;
/// 2. `staged` is renamed to `live`;
/// 3. the swapping name is renamed to `staged`.
///
/// Stopped after 1, `recover_swap` puts `live` back; stopped after 2, the new folder is in place and the old one is
/// under the swapping name, for `recover_swap` to deal with as the caller says.
pub fn swap_folders(staged: &Path, live: &Path) -> io::Result<()> {
    let marker = swapping(live);
    fs::rename(live, &marker)?;
    if let Err(error) = fs::rename(staged, live) {
        // Nothing new went in: the old folder goes straight back.
        let _ = fs::rename(&marker, live);
        return Err(error);
    }
    fs::rename(&marker, staged)
}

/// Finishes or undoes a swap a crash cut short. With `live` gone, the swap never got the new folder in: the old one
/// goes back. With both there, the new one is in and the old one is under the swapping name: `old` is given it, to
/// keep or delete.
pub fn recover_swap(live: &Path, old: impl FnOnce(&Path) -> io::Result<()>) -> io::Result<()> {
    let marker = swapping(live);
    if !marker.exists() {
        return Ok(());
    }
    if live.exists() {
        old(&marker)
    } else {
        fs::rename(&marker, live)
    }
}

/// Marks a file taken out of the vault as downloaded from the internet (the Mark of the Web, a `Zone.Identifier`
/// stream): nothing kept in the vault carries one, so a downloaded program would otherwise come out unflagged and run
/// without SmartScreen checking it first. The Windows counterpart of the Mac's quarantine flag. A disk that can't hold
/// it (FAT, exFAT) is left as it is.
pub fn mark_downloaded(path: &Path) {
    #[cfg(windows)]
    {
        let mut stream = path.as_os_str().to_owned();
        stream.push(":Zone.Identifier");
        let _ = fs::write(stream, b"[ZoneTransfer]\r\nZoneId=3\r\nReferrerUrl=about:stillroom\r\n");
    }
    #[cfg(not(windows))]
    let _ = path;
}

/// Everything under `path`, gone. Missing is fine.
pub fn remove_tree(path: &Path) -> io::Result<()> {
    match fs::remove_dir_all(path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        other => other,
    }
}
