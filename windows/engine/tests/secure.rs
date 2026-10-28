//! Keys in locked memory (`secure.rs`): each in a slot of its own, kept out of the page file, wiped when dropped. One
//! test alone in its own file, as the arena is the whole process's.

use std::collections::HashSet;

use stillroom_core::crypto::Key;
use stillroom_core::secure::{self, Slot};

#[test]
fn keys_live_in_locked_memory_and_are_wiped() {
    // A key dropped is wiped before its slot is handed out again (slots are reused last in, first out).
    let key = Key::random();
    assert_ne!(key.as_bytes(), &[0u8; 32]);
    let place = key.as_bytes().as_ptr();
    drop(key);
    let reused = Slot::new();
    assert_eq!(reused.bytes().as_ptr(), place);
    assert_eq!(reused.bytes(), &[0u8; 32], "a dropped key's slot is wiped");
    drop(reused);

    // Forty thousand keys (as many item keys as a big vault has): twenty chunks, far past the locked memory Windows
    // gives a process by default, so the arena has to raise it. Every one is its own and reads back as it was made.
    let before = secure::status();
    let keys: Vec<Key> = (0..40_000u32).map(|n| {
        let mut bytes = [0u8; 32];
        bytes[..4].copy_from_slice(&n.to_le_bytes());
        Key::from_slice(&bytes).unwrap()
    }).collect();
    let places: HashSet<usize> = keys.iter().map(|k| k.as_bytes().as_ptr() as usize).collect();
    assert_eq!(places.len(), keys.len());
    for (n, key) in keys.iter().enumerate() {
        assert_eq!(&key.as_bytes()[..4], &(n as u32).to_le_bytes());
    }
    let status = secure::status();
    assert_eq!(status.keys, before.keys + 40_000);
    assert!(status.chunks >= 20);
    #[cfg(windows)]
    assert!(status.all_locked, "Windows refused to lock key memory: {status:?}");

    drop(keys);
    assert_eq!(secure::status().keys, before.keys);
}

/// The app is kept out of Windows Error Reporting; this test's own program is taken off the list again at once.
#[test]
fn the_program_can_be_kept_out_of_crash_reports() {
    secure::exclude_from_crash_reports(false).unwrap();
    #[cfg(windows)]
    {
        let exe = std::env::current_exe().unwrap();
        let listed = std::process::Command::new("reg")
            .args(["query", r"HKCU\Software\Microsoft\Windows\Windows Error Reporting\ExcludedApplications", "/f"])
            .arg(exe.file_name().unwrap())
            .output()
            .unwrap();
        assert!(String::from_utf8_lossy(&listed.stdout).contains(&*exe.file_name().unwrap().to_string_lossy()));
    }
    secure::exclude_from_crash_reports(true).unwrap();
}
