//! Taking everything out of an open vault into plain files: `exportAll` in AppState.swift, and `take_out` in
//! tools/stillroom-open.py. Folders are made as the list names them (empty ones too), notes come out as `.md`, secrets
//! as `.txt` with one `label: value` line per field (hidden values included), and every file gets its dates back. One
//! damaged item doesn't stop the rest coming out.

use std::fs::{self, File, FileTimes};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};

use zeroize::Zeroizing;

use crate::blob;
use crate::list::{Entry, Item, Secret};
use crate::vault::Vault;
use crate::{system_time, VaultError};

/// What one item did, for showing progress.
pub struct Progress<'a> {
    /// 1-based.
    pub number: usize,
    pub of: usize,
    /// Where it went (or would have), inside the out folder.
    pub path: &'a Path,
    pub result: Result<(), &'a ItemFailure>,
}

/// Why an item didn't come out.
#[derive(Debug)]
pub enum ItemFailure {
    /// Its sealing is missing, cut short or was changed outside Stillroom.
    Damaged(VaultError),
    /// Writing it out failed (a full disk, a folder that can't be made).
    Writing(io::Error),
}

impl std::fmt::Display for ItemFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ItemFailure::Damaged(error) => error.fmt(f),
            ItemFailure::Writing(error) => write!(f, "couldn't write it: {error}"),
        }
    }
}

#[derive(Debug, Default)]
pub struct Report {
    pub taken: usize,
    /// Items that didn't come out, by where they would have gone (inside the out folder).
    pub failed: Vec<(PathBuf, ItemFailure)>,
}

/// Everything, as ordinary unencrypted files, in a new folder "Stillroom Export <date>" inside `parent`: the way to
/// leave Stillroom, or keep a readable copy. Returns the folder made, and what happened.
pub fn export_all(vault: &Vault, parent: &Path, progress: impl FnMut(Progress)) -> io::Result<(PathBuf, Report)> {
    let top = unused(&parent.join(format!("Stillroom Export {}", today())));
    let report = take_out(vault, &top, progress)?;
    Ok((top, report))
}

/// Everything in `vault`, unencrypted, into `out`.
pub fn take_out(vault: &Vault, out: &Path, mut progress: impl FnMut(Progress)) -> io::Result<Report> {
    fs::create_dir_all(out)?;
    let list = vault.list();
    for folder in &list.folders {
        place(out, Some(folder))?;
    }
    let mut report = Report::default();
    let count = list.files.len();
    for (i, item) in list.files.iter().enumerate() {
        let (target, result) = match place(out, item.folder.as_deref()) {
            Ok(folder) => {
                let target = unused(&folder.join(file_name(item)));
                let result = take_one(vault, item, &target);
                (target, result)
            }
            Err(error) => (out.join(file_name(item)), Err(ItemFailure::Writing(error))),
        };
        let shown = target.strip_prefix(out).unwrap_or(&target).to_path_buf();
        match result {
            Ok(()) => {
                report.taken += 1;
                progress(Progress { number: i + 1, of: count, path: &shown, result: Ok(()) });
            }
            Err(failure) => {
                progress(Progress { number: i + 1, of: count, path: &shown, result: Err(&failure) });
                report.failed.push((shown, failure));
            }
        }
    }
    Ok(report)
}

/// The name an item comes out under: its own, made safe, with `.md` for a note and `.txt` for a secret.
pub fn file_name(item: &Item) -> String {
    let extension = match item.entry {
        Some(Entry::Note) => ".md",
        Some(Entry::Secret) => ".txt",
        None => "",
    };
    safe(&item.name) + extension
}

/// One item's contents written to `target`, with its dates: made when it was first made, changed when it last changed.
pub fn take_one(vault: &Vault, item: &Item, target: &Path) -> Result<(), ItemFailure> {
    let sealed_as = item.sealed_as.ok_or(ItemFailure::Damaged(VaultError::Damaged))?;
    let key = vault.item_key(&sealed_as).ok_or(ItemFailure::Damaged(VaultError::Damaged))?;
    let path = vault.store().blob(&sealed_as);

    // Written beside the target first, so an item that fails partway leaves nothing that looks complete.
    let mut partial = target.as_os_str().to_owned();
    partial.push(".partial");
    let partial = PathBuf::from(partial);
    let written = (|| -> Result<(), ItemFailure> {
        let file = File::create(&partial).map_err(ItemFailure::Writing)?;
        let mut out = BufWriter::new(file);
        if item.entry == Some(Entry::Secret) {
            let json = blob::read(&path, &sealed_as, key, item.size, item.is_chunked()).map_err(ItemFailure::Damaged)?;
            let secret: Secret = serde_json::from_slice(&json).map_err(|_| ItemFailure::Damaged(VaultError::Damaged))?;
            let mut text = Zeroizing::new(String::new());
            for field in &secret.fields {
                text.push_str(&field.label);
                text.push_str(": ");
                text.push_str(&field.value);
                text.push('\n');
            }
            out.write_all(text.as_bytes()).map_err(ItemFailure::Writing)?;
        } else {
            blob::read_into(&path, &sealed_as, key, item.size, item.is_chunked(), &mut out).map_err(|error| match error {
                blob::ReadError::Damaged(error) => ItemFailure::Damaged(error),
                blob::ReadError::Writing(error) => ItemFailure::Writing(error),
            })?;
        }
        let file = out.into_inner().map_err(|e| ItemFailure::Writing(e.into_error()))?;
        // Marked before its dates are set (writing the mark counts as a change), and kept through the rename.
        crate::fsx::mark_downloaded(&partial);
        if let Some(changed) = system_time(item.shown_date()) {
            let mut times = FileTimes::new().set_accessed(changed).set_modified(changed);
            #[cfg(windows)]
            if let Some(made) = system_time(item.created.unwrap_or(item.added_at)) {
                use std::os::windows::fs::FileTimesExt;
                times = times.set_created(made);
            }
            file.set_times(times).map_err(ItemFailure::Writing)?;
        }
        file.sync_all().map_err(ItemFailure::Writing)?;
        drop(file);
        fs::rename(&partial, target).map_err(ItemFailure::Writing)
    })();
    if written.is_err() {
        let _ = fs::remove_file(&partial);
    }
    written
}

/// Today's date (UTC), as "2026-10-26".
fn today() -> String {
    let days = (crate::now() + crate::APPLE_EPOCH).div_euclid(86_400.0) as i64;
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!("{year:04}-{month:02}-{day:02}")
}

/// The folder an item sits in, made inside `out` and nowhere else: no "..", no empty parts.
fn place(out: &Path, folder: Option<&str>) -> io::Result<PathBuf> {
    let mut path = out.to_path_buf();
    for part in folder.unwrap_or("").split('/').filter(|p| !p.is_empty()) {
        path.push(safe(part));
    }
    fs::create_dir_all(&path)?;
    Ok(path)
}

/// `path`, or `name 2.ext`, `name 3.ext`… when it's taken.
pub fn unused(path: &Path) -> PathBuf {
    if !path.exists() {
        return path.to_path_buf();
    }
    let stem = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let extension = path.extension().map(|e| format!(".{}", e.to_string_lossy())).unwrap_or_default();
    (2..)
        .map(|n| path.with_file_name(format!("{stem} {n}{extension}")))
        .find(|candidate| !candidate.exists())
        .unwrap()
}

/// Whether Windows would take `name` for a device: CON, PRN, AUX, NUL, COM0–9, LPT0–9 (and the superscript ¹ ² ³
/// forms), CONIN$ or CONOUT$, in any case, with or without an extension ("nul.txt").
pub fn is_device_name(name: &str) -> bool {
    let stem = name.split('.').next().unwrap_or("").trim_end().to_uppercase();
    if matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$") {
        return true;
    }
    let mut chars = stem.chars();
    let prefix: String = chars.by_ref().take(3).collect();
    let (Some(last), None) = (chars.next(), chars.next()) else { return false };
    (prefix == "COM" || prefix == "LPT") && (last.is_ascii_digit() || matches!(last, '¹' | '²' | '³'))
}

/// A name from the list as a file name Windows accepts. The Mac keeps a "/" typed in a name as a look-alike (∕) and
/// may have ":" in one; neither can be in a Windows name, nor `< > " \ | ? *`, control characters, a trailing dot or
/// space, or a device name such as CON or LPT1.
pub fn safe(name: &str) -> String {
    let mut text: String = name
        .chars()
        .map(|c| match c {
            '\u{2215}' | '/' | ':' | '<' | '>' | '"' | '\\' | '|' | '?' | '*' => '-',
            c if c.is_control() => '-',
            c => c,
        })
        .collect();
    while text.ends_with(['.', ' ']) {
        text.pop();
    }
    if text.is_empty() {
        return "Untitled".into();
    }
    if is_device_name(&text) {
        text.insert(0, '_');
    }
    text
}
