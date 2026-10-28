//! Stillroom's vault engine for Windows. Everything that touches a key lives here, in Rust, so keys can be locked in
//! memory and wiped (windows/PORT.md, "Security parity plan"); the WinUI shell calls in over FFI and never holds one.
//!
//! The on-disk format is the Mac app's, unchanged: docs/FORMAT.md is the contract, and tools/stillroom-open.py must
//! open what this writes.

pub mod argon2;
pub mod backup;
pub mod blob;
pub mod crypto;
pub mod desktop;
pub mod email;
pub mod export;
pub mod ffi;
pub mod fsx;
pub mod hello;
pub mod import;
pub mod intruder;
pub mod kinds;
pub mod kit;
pub mod list;
pub mod names;
pub mod originals;
pub mod otp;
pub mod platform;
pub mod search;
pub mod secure;
pub mod session;
pub mod strength;
pub mod tpm;
pub mod tries;
pub mod vault;

use std::fmt;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Seconds from 1970 to 1 January 2001, Apple's reference date, which every date in a vault counts from.
pub const APPLE_EPOCH: f64 = 978_307_200.0;

/// Now, as seconds since 2001.
pub fn now() -> f64 {
    apple_seconds(SystemTime::now())
}

/// A system time as seconds since 2001.
pub fn apple_seconds(time: SystemTime) -> f64 {
    match time.duration_since(UNIX_EPOCH) {
        Ok(since) => since.as_secs_f64() - APPLE_EPOCH,
        Err(before) => -before.duration().as_secs_f64() - APPLE_EPOCH,
    }
}

/// Seconds since 2001 as a system time, or None for one that can't be real.
pub fn system_time(apple: f64) -> Option<SystemTime> {
    let unix = APPLE_EPOCH + apple;
    if !unix.is_finite() || unix.abs() > 1e12 {
        return None;
    }
    if unix >= 0.0 {
        UNIX_EPOCH.checked_add(Duration::from_secs_f64(unix))
    } else {
        UNIX_EPOCH.checked_sub(Duration::from_secs_f64(-unix))
    }
}

/// The ways opening or reading a vault can fail, as the Mac app's `VaultError`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VaultError {
    WrongPassword,
    WrongRecoveryKey,
    Damaged,
    Folder,
    HelloUnavailable,
    HelloChanged,
    NotThisComputer,
    SameAsOther,
    WrongKit,
    NewerVault,
    /// Too many new passwords checked against the other slot in a row (`TryLimit`).
    TooSoon,
}

impl fmt::Display for VaultError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            VaultError::WrongPassword => "That password doesn't open this vault.",
            VaultError::WrongRecoveryKey => "That recovery key doesn't open this vault.",
            VaultError::Damaged => "The vault's files are damaged or were changed outside Stillroom.",
            VaultError::Folder => "That's a folder. Add the folder itself and what's inside it goes in.",
            VaultError::HelloUnavailable => "This PC has no Windows Hello set up.",
            VaultError::HelloChanged => {
                "Windows Hello couldn't open it. Use your password, then turn Windows Hello on again in Settings."
            }
            VaultError::NotThisComputer => {
                "This vault is locked to another computer. Open it with your recovery key or emergency kit."
            }
            VaultError::SameAsOther => "Pick a different password: that one is already in use for this vault.",
            VaultError::WrongKit => "Those pieces don't open this vault. They may be from an older kit.",
            VaultError::NewerVault => {
                "This vault was saved by a newer version of Stillroom. Update Stillroom to open it."
            }
            VaultError::TooSoon => "Too many password changes in a row. Wait a few minutes, then try again.",
        })
    }
}

impl std::error::Error for VaultError {}

/// What any action on a vault can fail with.
#[derive(Debug)]
pub enum Error {
    /// The vault itself: a wrong way in, damage, a newer format.
    Vault(VaultError),
    /// Emergency kit pieces that don't read or don't belong together.
    Kit(kit::KitProblem),
    /// The disk.
    Io(std::io::Error),
    /// A write to a store opened read only.
    ReadOnly,
    /// No item (or version) with that id.
    NotFound,
    /// A folder by that name is already there.
    FolderExists(String),
    /// A folder can't go inside one of its own folders.
    FolderIntoItself,
    /// A backup that isn't one.
    NotABackup,
    /// Locked to a Mac: one computer holds the lock at a time.
    LockedElsewhere,
    /// This PC has no TPM Stillroom can use, so it can't be locked to it.
    NoTpm,
}

impl PartialEq for Error {
    fn eq(&self, other: &Error) -> bool {
        match (self, other) {
            (Error::Vault(a), Error::Vault(b)) => a == b,
            (Error::Kit(a), Error::Kit(b)) => a == b,
            (Error::Io(a), Error::Io(b)) => a.kind() == b.kind(),
            (Error::FolderExists(a), Error::FolderExists(b)) => a == b,
            (a, b) => std::mem::discriminant(a) == std::mem::discriminant(b),
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Vault(error) => error.fmt(f),
            Error::Kit(problem) => problem.fmt(f),
            Error::Io(error) => write!(f, "The disk said no: {error}"),
            Error::ReadOnly => f.write_str("This vault was opened only to read it."),
            Error::NotFound => f.write_str("That isn't in the vault any more."),
            Error::FolderExists(name) => write!(f, "There's already a folder called “{name}” there."),
            Error::FolderIntoItself => f.write_str("A folder can't go inside one of its own folders."),
            Error::NotABackup => f.write_str("That file isn't a Stillroom backup."),
            Error::LockedElsewhere => {
                f.write_str("This vault is locked to a Mac. Only one computer can hold the lock: turn it off on that Mac first.")
            }
            Error::NoTpm => f.write_str("This PC has no TPM that Stillroom can use, so the vault can't be locked to it."),
        }
    }
}

impl std::error::Error for Error {}

impl From<VaultError> for Error {
    fn from(error: VaultError) -> Self {
        Error::Vault(error)
    }
}

impl From<kit::KitProblem> for Error {
    fn from(problem: kit::KitProblem) -> Self {
        Error::Kit(problem)
    }
}

impl From<std::io::Error> for Error {
    fn from(error: std::io::Error) -> Self {
        Error::Io(error)
    }
}
