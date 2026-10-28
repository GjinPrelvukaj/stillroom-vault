//! Process hardening, alone in its own file: the policies can't be undone for a process. Each is turned on, Windows is
//! asked whether it took, and a vault is then made and read to show the engine still works hardened.

#![cfg(windows)]

mod common;

use stillroom_core::platform::{harden_process, Hardened};
use windows_sys::Win32::System::Threading::{
    GetCurrentProcess, GetProcessMitigationPolicy, ProcessExtensionPointDisablePolicy, ProcessImageLoadPolicy,
    ProcessStrictHandleCheckPolicy,
};

fn policy(which: i32) -> u32 {
    let mut flags = 0u32;
    // SAFETY: each of these policies is a 4-byte flags word.
    let ok = unsafe { GetProcessMitigationPolicy(GetCurrentProcess(), which, (&mut flags as *mut u32).cast(), 4) };
    assert!(ok != 0);
    flags
}

#[test]
fn the_process_is_hardened_and_the_vault_still_works() {
    assert_eq!(policy(ProcessExtensionPointDisablePolicy) & 1, 0, "not on before");

    let hardened = harden_process(true);
    assert_eq!(hardened, Hardened { extension_dlls_blocked: true, image_loads_restricted: true, strict_handles: true });
    assert_eq!(policy(ProcessExtensionPointDisablePolicy) & 1, 1, "extension DLLs blocked");
    assert_eq!(policy(ProcessImageLoadPolicy) & 0b111, 0b111, "no remote or low-integrity images, System32 first");
    assert_eq!(policy(ProcessStrictHandleCheckPolicy) & 0b11, 0b11, "invalid handles are fatal");

    // Argon2, AES-GCM, files and the folder permissions all still work.
    let dir = tempfile::tempdir().unwrap();
    let store = common::store_in(dir.path());
    let (mut vault, _) = store.create("real password 123").unwrap();
    let note = vault.new_entry(stillroom_core::list::Entry::Note, "Plans", b"still works", None).unwrap();
    drop(vault);
    let vault = store.unlock_with_password("real password 123").unwrap();
    assert_eq!(*vault.read(&note).unwrap(), b"still works");
}
