//! Wrong tries (`TryLimit` in Views/LockView.swift): the first three are free, then each next try waits longer (5 s,
//! 10 s, 20 s… up to 5 minutes). Kept across restarts beside the vault folder (the Mac keeps it in the app's
//! preferences), never inside it, so it isn't in a backup and says nothing about either slot. This slows someone at
//! the computer; a stolen copy is only slowed by the password's stretching and length.
//!
//! The lock screen counts its wrong passwords, recovery keys and kits here and clears it on a good one. The engine
//! counts every check of a new password against the other slot, as that answers a guess at the other slot's password.

use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::{fsx, VaultError};

pub struct TryLimit {
    path: PathBuf,
}

#[derive(Default, Deserialize, Serialize)]
struct Count {
    failures: u32,
    /// The last wrong try, in seconds since 1970.
    last: f64,
}

impl TryLimit {
    pub fn at(path: PathBuf) -> TryLimit {
        TryLimit { path }
    }

    fn count(&self) -> Count {
        fs::read(&self.path).ok().and_then(|data| serde_json::from_slice(&data).ok()).unwrap_or_default()
    }

    /// When the next try may be made, in seconds since 1970 (0: now).
    pub fn next_try(&self) -> f64 {
        let count = self.count();
        if count.failures <= 3 {
            return 0.0;
        }
        let wait = (5.0 * 2f64.powi(count.failures as i32 - 4)).min(300.0);
        count.last + wait
    }

    /// Seconds to wait before the next try, rounded up; 0 when one may be made now.
    pub fn wait_left(&self) -> u64 {
        (self.next_try() - unix_now()).max(0.0).ceil() as u64
    }

    pub fn failed(&self) {
        let count = self.count();
        let next = Count { failures: count.failures.saturating_add(1), last: unix_now() };
        let _ = fsx::write_atomic(&self.path, &serde_json::to_vec(&next).expect("plain data"));
    }

    pub fn succeeded(&self) {
        let _ = fs::remove_file(&self.path);
    }

    /// A guess that isn't made at the lock screen (a new password checked against the other slot): refused while a
    /// wait is on, counted otherwise.
    pub fn count_guess(&self) -> Result<(), VaultError> {
        if unix_now() < self.next_try() {
            return Err(VaultError::TooSoon);
        }
        self.failed();
        Ok(())
    }
}

fn unix_now() -> f64 {
    crate::now() + crate::APPLE_EPOCH
}
