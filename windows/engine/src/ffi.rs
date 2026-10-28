//! The C interface the Windows app calls (`include/stillroom.h`, generated from this file). The app holds opaque
//! handles and plain data, and never a key (windows/PORT.md, "Security parity plan"):
//!
//! - A **store** is a vault folder; an open **vault** is one slot unlocked. Freeing a vault handle is locking: its keys
//!   are wiped. A vault handle may be used from any thread; calls on it take turns.
//! - **Secrets in** (passwords, recovery keys, kit pieces) are byte buffers, `(ptr, len)`, UTF-8, so the app can wipe
//!   its own copy afterwards. Kit pieces are one buffer, a piece per line.
//! - **Everything else in** is a NUL-terminated UTF-8 string; item ids are UUIDs as text.
//! - **Lists and reports out** are JSON strings. Contents out are `StillroomBytes`. Both are the engine's, wiped and
//!   freed with `stillroom_string_free` and `stillroom_bytes_free`.
//! - **Every call** returns a `StillroomStatus`: 0 for done, otherwise what went wrong, with the message in plain
//!   words from `stillroom_last_error()` on the same thread. A bug that panics is caught here and reported as
//!   `STILLROOM_PANICKED`, never let through.
//!
//! # Safety
//!
//! Every function that takes a pointer is `unsafe`, for one contract, the same for all of them (so it's said here and
//! not on each): a handle is one this interface gave and hasn't been freed; a string is NUL-terminated and stays valid
//! for the call; a `(ptr, len)` buffer holds `len` readable bytes (or `len` is 0); a result pointer is writable; and
//! anything the engine gave is freed once, with its own `_free` function. Null is checked everywhere and refused with
//! `STILLROOM_INVALID_ARGUMENT`; nothing else about a pointer can be checked.

#![allow(clippy::missing_safety_doc)]

use std::cell::RefCell;
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard};

use base64::Engine as _;
use serde::Serialize;
use serde_json::{json, Value};
use uuid::Uuid;
use zeroize::{Zeroize, Zeroizing};

use crate::blob::ChunkedReader;
use crate::kit::KitProblem;
use crate::list::{Entry, Item};
use crate::originals::Originals;
use crate::session::Contents;
use crate::vault::{Store, Vault};
use crate::{backup, email, export, import, intruder, kinds, otp, secure, strength, Error, VaultError};

/// The interface's version: raised when a function changes, so an app built against another can tell.
pub const STILLROOM_ABI_VERSION: u32 = 1;

// MARK: Status codes

/// What a call did: 0 for done, otherwise why not.
pub type StillroomStatus = i32;

pub const STILLROOM_OK: StillroomStatus = 0;
pub const STILLROOM_WRONG_PASSWORD: StillroomStatus = 1;
pub const STILLROOM_WRONG_RECOVERY_KEY: StillroomStatus = 2;
pub const STILLROOM_DAMAGED: StillroomStatus = 3;
pub const STILLROOM_FOLDER: StillroomStatus = 4;
pub const STILLROOM_HELLO_UNAVAILABLE: StillroomStatus = 5;
pub const STILLROOM_HELLO_CHANGED: StillroomStatus = 6;
pub const STILLROOM_NOT_THIS_COMPUTER: StillroomStatus = 7;
pub const STILLROOM_SAME_AS_OTHER: StillroomStatus = 8;
pub const STILLROOM_WRONG_KIT: StillroomStatus = 9;
pub const STILLROOM_NEWER_VAULT: StillroomStatus = 10;
pub const STILLROOM_TOO_SOON: StillroomStatus = 11;
pub const STILLROOM_KIT_MISTYPED: StillroomStatus = 20;
pub const STILLROOM_KIT_MIXED: StillroomStatus = 21;
pub const STILLROOM_KIT_NOT_ENOUGH: StillroomStatus = 22;
pub const STILLROOM_DISK: StillroomStatus = 30;
pub const STILLROOM_READ_ONLY: StillroomStatus = 31;
pub const STILLROOM_NOT_FOUND: StillroomStatus = 32;
pub const STILLROOM_FOLDER_EXISTS: StillroomStatus = 33;
pub const STILLROOM_FOLDER_INTO_ITSELF: StillroomStatus = 34;
pub const STILLROOM_NOT_A_BACKUP: StillroomStatus = 35;
pub const STILLROOM_NOT_AN_EXPORT: StillroomStatus = 36;
pub const STILLROOM_LOCKED_ELSEWHERE: StillroomStatus = 37;
pub const STILLROOM_NO_TPM: StillroomStatus = 38;
pub const STILLROOM_INVALID_ARGUMENT: StillroomStatus = 40;
pub const STILLROOM_PANICKED: StillroomStatus = 41;

/// What failed, with its code and words.
struct Failure {
    code: StillroomStatus,
    message: String,
}

impl From<Error> for Failure {
    fn from(error: Error) -> Failure {
        let code = match &error {
            Error::Vault(e) => match e {
                VaultError::WrongPassword => STILLROOM_WRONG_PASSWORD,
                VaultError::WrongRecoveryKey => STILLROOM_WRONG_RECOVERY_KEY,
                VaultError::Damaged => STILLROOM_DAMAGED,
                VaultError::Folder => STILLROOM_FOLDER,
                VaultError::HelloUnavailable => STILLROOM_HELLO_UNAVAILABLE,
                VaultError::HelloChanged => STILLROOM_HELLO_CHANGED,
                VaultError::NotThisComputer => STILLROOM_NOT_THIS_COMPUTER,
                VaultError::SameAsOther => STILLROOM_SAME_AS_OTHER,
                VaultError::WrongKit => STILLROOM_WRONG_KIT,
                VaultError::NewerVault => STILLROOM_NEWER_VAULT,
                VaultError::TooSoon => STILLROOM_TOO_SOON,
            },
            Error::Kit(KitProblem::Mistyped) => STILLROOM_KIT_MISTYPED,
            Error::Kit(KitProblem::Mixed) => STILLROOM_KIT_MIXED,
            Error::Kit(KitProblem::NotEnough(_)) => STILLROOM_KIT_NOT_ENOUGH,
            Error::Io(_) => STILLROOM_DISK,
            Error::ReadOnly => STILLROOM_READ_ONLY,
            Error::NotFound => STILLROOM_NOT_FOUND,
            Error::FolderExists(_) => STILLROOM_FOLDER_EXISTS,
            Error::FolderIntoItself => STILLROOM_FOLDER_INTO_ITSELF,
            Error::NotABackup => STILLROOM_NOT_A_BACKUP,
            Error::LockedElsewhere => STILLROOM_LOCKED_ELSEWHERE,
            Error::NoTpm => STILLROOM_NO_TPM,
        };
        Failure { code, message: error.to_string() }
    }
}

impl From<VaultError> for Failure {
    fn from(error: VaultError) -> Failure {
        Error::Vault(error).into()
    }
}

impl From<std::io::Error> for Failure {
    fn from(error: std::io::Error) -> Failure {
        Error::Io(error).into()
    }
}

fn invalid(message: impl Into<String>) -> Failure {
    Failure { code: STILLROOM_INVALID_ARGUMENT, message: message.into() }
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

/// Runs a call: its failure (or a panic) becomes a status and this thread's last error.
fn call(body: impl FnOnce() -> Result<(), Failure>) -> StillroomStatus {
    let failure = match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(())) => return STILLROOM_OK,
        Ok(Err(failure)) => failure,
        Err(_) => Failure { code: STILLROOM_PANICKED, message: "Something went wrong inside Stillroom.".into() },
    };
    LAST_ERROR.with(|last| *last.borrow_mut() = CString::new(failure.message.replace('\0', " ")).unwrap_or_default());
    failure.code
}

/// The words for the last failure on this thread. Valid until the next call on this thread.
#[no_mangle]
pub extern "C" fn stillroom_last_error() -> *const c_char {
    LAST_ERROR.with(|last| last.borrow().as_ptr())
}

#[no_mangle]
pub extern "C" fn stillroom_abi_version() -> u32 {
    STILLROOM_ABI_VERSION
}

// MARK: Taking arguments

fn text<'a>(value: *const c_char, what: &str) -> Result<&'a str, Failure> {
    if value.is_null() {
        return Err(invalid(format!("{what} is missing.")));
    }
    // SAFETY: the caller passes a NUL-terminated string that outlives the call.
    unsafe { CStr::from_ptr(value) }.to_str().map_err(|_| invalid(format!("{what} isn't UTF-8.")))
}

fn optional_text<'a>(value: *const c_char, what: &str) -> Result<Option<&'a str>, Failure> {
    if value.is_null() { Ok(None) } else { text(value, what).map(Some) }
}

fn bytes<'a>(data: *const u8, length: usize, what: &str) -> Result<&'a [u8], Failure> {
    if length == 0 {
        return Ok(&[]);
    }
    if data.is_null() {
        return Err(invalid(format!("{what} is missing.")));
    }
    // SAFETY: the caller passes `length` readable bytes that outlive the call.
    Ok(unsafe { std::slice::from_raw_parts(data, length) })
}

fn secret<'a>(data: *const u8, length: usize, what: &str) -> Result<&'a str, Failure> {
    std::str::from_utf8(bytes(data, length, what)?).map_err(|_| invalid(format!("{what} isn't UTF-8.")))
}

fn id(value: *const c_char) -> Result<Uuid, Failure> {
    text(value, "The item's id")?.parse().map_err(|_| invalid("That isn't an item's id."))
}

fn path(value: *const c_char, what: &str) -> Result<PathBuf, Failure> {
    text(value, what).map(PathBuf::from)
}

fn json_in<T: serde::de::DeserializeOwned>(value: *const c_char, what: &str) -> Result<T, Failure> {
    serde_json::from_str(text(value, what)?).map_err(|e| invalid(format!("{what} isn't the JSON expected: {e}")))
}

// MARK: Giving results

/// Bytes the engine hands out: contents of an item, an attachment. Freed (and wiped) with `stillroom_bytes_free`.
#[repr(C)]
pub struct StillroomBytes {
    pub data: *mut u8,
    pub length: usize,
}

fn out<T>(slot: *mut T, value: T) -> Result<(), Failure> {
    if slot.is_null() {
        return Err(invalid("A place for the result is missing."));
    }
    // SAFETY: the caller passes a writable place for the result.
    unsafe { slot.write(value) };
    Ok(())
}

/// A string handed out. Copied into a buffer of its exact size and the original wiped, so growing it for its NUL never
/// leaves a copy (a recovery key, kit pieces) behind.
fn give_string(slot: *mut *mut c_char, value: String) -> Result<(), Failure> {
    let mut value = Zeroizing::new(value);
    if value.as_bytes().contains(&0) {
        return Err(invalid("The result held a NUL character."));
    }
    let mut exact = Vec::with_capacity(value.len() + 1);
    exact.extend_from_slice(value.as_bytes());
    value.zeroize();
    // SAFETY: checked above that no byte is NUL.
    out(slot, unsafe { CString::from_vec_unchecked(exact) }.into_raw())
}

fn give_json(slot: *mut *mut c_char, value: &impl Serialize) -> Result<(), Failure> {
    give_string(slot, serde_json::to_string(value).map_err(|e| invalid(e.to_string()))?)
}

/// Bytes handed out, in a block of their exact size (copied, and the original wiped, when it had room to spare: shrinking
/// it in place could leave a copy of decrypted contents behind).
fn give_bytes(slot: *mut StillroomBytes, mut value: Vec<u8>) -> Result<(), Failure> {
    let mut boxed: Box<[u8]> = if value.capacity() == value.len() {
        value.into_boxed_slice()
    } else {
        let exact = value.as_slice().into();
        value.zeroize();
        exact
    };
    let length = boxed.len();
    let data = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    out(slot, StillroomBytes { data, length })
}

/// Wipes and frees a string the engine gave (a recovery key and kit pieces are among them). Null is fine.
#[no_mangle]
pub unsafe extern "C" fn stillroom_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    // SAFETY: `value` came from `CString::into_raw` in this file and is freed once.
    let text = unsafe { CString::from_raw(value) };
    let mut bytes = text.into_bytes_with_nul();
    bytes.zeroize();
}

/// Wipes and frees bytes the engine gave. An empty or null one is fine.
#[no_mangle]
pub unsafe extern "C" fn stillroom_bytes_free(value: StillroomBytes) {
    if value.data.is_null() {
        return;
    }
    // SAFETY: `data` and `length` came from `give_bytes` and are freed once.
    let mut boxed = unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(value.data, value.length)) };
    boxed.zeroize();
}

// MARK: The program

/// Whether every key is kept in locked memory, out of the page file. False means Windows refused: worth telling.
#[no_mangle]
pub extern "C" fn stillroom_keys_are_locked() -> bool {
    let status = secure::status();
    status.chunks == 0 || status.all_locked
}

/// Keeps this program out of Windows Error Reporting, so a crash never writes its memory to disk. Call once at start.
#[no_mangle]
pub extern "C" fn stillroom_exclude_from_crash_reports() -> StillroomStatus {
    call(|| secure::exclude_from_crash_reports(false).map_err(|code| invalid(format!("Windows said no ({code:#x})."))))
}

/// Turns on Windows' process protections (`platform.rs`): no extension DLLs (keyboard-hook injection; also IMEs, so
/// `block_extension_dlls` is a setting), no images from the network or low-integrity files, invalid handles fatal.
/// Can't be undone; call once, early. Gives what took, as bits: 1 extension DLLs, 2 image loads, 4 strict handles.
#[no_mangle]
pub unsafe extern "C" fn stillroom_harden_process(block_extension_dlls: bool, hardened: *mut u32) -> StillroomStatus {
    call(|| {
        let done = crate::platform::harden_process(block_extension_dlls);
        out(hardened, u32::from(done.extension_dlls_blocked) | u32::from(done.image_loads_restricted) << 1 | u32::from(done.strict_handles) << 2)
    })
}

/// A folder made (if need be) and readable by this account only, as the vault folder is: for Edit in Place's working
/// copies. Its permissions are replaced by one entry, this account's, inherited by everything inside.
#[no_mangle]
pub unsafe extern "C" fn stillroom_protect_folder(folder: *const c_char) -> StillroomStatus {
    call(|| Ok(crate::platform::protect_folder(&path(folder, "The folder")?)?))
}

/// Whether this PC has a TPM the vault can be locked to.
#[no_mangle]
pub extern "C" fn stillroom_tpm_available() -> bool {
    crate::tpm::available()
}

/// Asks for a secret on a desktop of its own, where other programs' keyboard hooks can't see it: the screen switches to
/// a small prompt and back. `multiline` for kit pieces (a piece per line, shown as typed); otherwise one line, hidden.
/// Gives what was typed (wipe it: free it with `stillroom_bytes_free`), or `cancelled` true (Cancel, Escape, or two
/// minutes untouched).
#[no_mangle]
pub unsafe extern "C" fn stillroom_secure_prompt(
    title: *const c_char,
    message: *const c_char,
    multiline: bool,
    typed: *mut StillroomBytes,
    cancelled: *mut bool,
) -> StillroomStatus {
    call(|| {
        let prompt = crate::desktop::Prompt { title: text(title, "The title")?, message: text(message, "The message")?, multiline };
        match crate::desktop::ask(&prompt)? {
            Some(answer) => {
                out(cancelled, false)?;
                give_bytes(typed, answer.as_bytes().to_vec())
            }
            None => {
                out(cancelled, true)?;
                out(typed, StillroomBytes { data: std::ptr::null_mut(), length: 0 })
            }
        }
    })
}

/// 32 random bytes for Windows Hello to sign, to turn it on (`stillroom_vault_turn_on_hello`).
#[no_mangle]
pub unsafe extern "C" fn stillroom_hello_new_challenge(result: *mut StillroomBytes) -> StillroomStatus {
    call(|| give_bytes(result, Vault::hello_new_challenge().to_vec()))
}

// MARK: Stores

/// A vault folder. Opaque to the app.
pub struct StillroomStore(Store);

fn store<'a>(handle: *const StillroomStore) -> Result<&'a Store, Failure> {
    if handle.is_null() {
        return Err(invalid("The store is missing."));
    }
    // SAFETY: the handle came from `stillroom_store_open` and hasn't been freed.
    Ok(unsafe { &(*handle).0 })
}

/// Opens the vault folder at `root` (UTF-8), or the usual one (%APPDATA%\Stillroom\Store) when it's null. Nothing is
/// read or made yet. `read_only` opens it only to take things out: nothing is tidied or written.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_open(root: *const c_char, read_only: bool, result: *mut *mut StillroomStore) -> StillroomStatus {
    call(|| {
        let root = match optional_text(root, "The folder")? {
            Some(root) => PathBuf::from(root),
            None => Store::default_root().ok_or_else(|| invalid("There's no %APPDATA% folder."))?,
        };
        let opened = if read_only { Store::at(root).read_only() } else { Store::at(root) };
        out(result, Box::into_raw(Box::new(StillroomStore(opened))))
    })
}

/// For tests only: passwords stretched at a low cost from now on in this store, as the Mac's tests lower it.
#[doc(hidden)]
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_lower_cost_for_tests(handle: *mut StillroomStore) -> StillroomStatus {
    call(|| {
        if handle.is_null() {
            return Err(invalid("The store is missing."));
        }
        // SAFETY: as in `store`, and `&mut` because the app holds the only handle.
        let store = unsafe { &mut (*handle).0 };
        *store = store.clone().with_cost(crate::crypto::PasswordCost { memory_kib: 64, passes: 1, lanes: 1 });
        Ok(())
    })
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_store_free(handle: *mut StillroomStore) {
    if !handle.is_null() {
        // SAFETY: the handle came from `stillroom_store_open` and is freed once.
        drop(unsafe { Box::from_raw(handle) });
    }
}

/// Whether a vault is there (both slots' password keys are).
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_exists(handle: *const StillroomStore, result: *mut bool) -> StillroomStatus {
    call(|| out(result, store(handle)?.exists()))
}

/// A folder from before format 4: never read, and nothing is written over it.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_is_old_format(handle: *const StillroomStore, result: *mut bool) -> StillroomStatus {
    call(|| out(result, store(handle)?.is_old_format()))
}

/// Locked to the Mac that made it: only the recovery key or the kit opens it here.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_is_locked_to_a_mac(handle: *const StillroomStore, result: *mut bool) -> StillroomStatus {
    call(|| out(result, store(handle)?.is_locked_to_a_mac()))
}

/// A new vault with this password. Gives the open vault and its recovery key, to be shown once.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_create(
    handle: *const StillroomStore,
    password: *const u8,
    password_length: usize,
    vault: *mut *mut StillroomVault,
    recovery_key: *mut *mut c_char,
) -> StillroomStatus {
    call(|| {
        let (opened, code) = store(handle)?.create(secret(password, password_length, "The password")?)?;
        give_string(recovery_key, code)?;
        give_vault(vault, opened)
    })
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_store_unlock_with_password(
    handle: *const StillroomStore,
    password: *const u8,
    password_length: usize,
    vault: *mut *mut StillroomVault,
) -> StillroomStatus {
    call(|| give_vault(vault, store(handle)?.unlock_with_password(secret(password, password_length, "The password")?)?))
}

/// Locked to a PC: here if this is the PC (the password opens it), elsewhere only the recovery key or the kit.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_is_locked_to_a_pc(handle: *const StillroomStore, result: *mut bool) -> StillroomStatus {
    call(|| out(result, store(handle)?.is_locked_to_a_pc()))
}

/// The challenge to ask Windows Hello to sign at the lock screen. `STILLROOM_NOT_FOUND` when Hello isn't on.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_hello_challenge(handle: *const StillroomStore, result: *mut StillroomBytes) -> StillroomStatus {
    call(|| give_bytes(result, store(handle)?.hello_challenge()?))
}

/// Windows Hello's signature of the challenge opens the vault that turned Hello on. `STILLROOM_HELLO_CHANGED` when it
/// opens nothing (Hello was set up again): use the password, then turn Hello on again.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_unlock_with_hello(
    handle: *const StillroomStore,
    signature: *const u8,
    signature_length: usize,
    vault: *mut *mut StillroomVault,
) -> StillroomStatus {
    call(|| give_vault(vault, store(handle)?.unlock_with_hello(bytes(signature, signature_length, "The signature")?)?))
}

/// Any case, with or without dashes and spaces. A new password must be set before anything else.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_unlock_with_recovery_key(
    handle: *const StillroomStore,
    recovery_key: *const u8,
    recovery_key_length: usize,
    vault: *mut *mut StillroomVault,
) -> StillroomStatus {
    call(|| {
        let typed = secret(recovery_key, recovery_key_length, "The recovery key")?;
        give_vault(vault, store(handle)?.unlock_with_recovery_key(typed)?)
    })
}

/// Kit pieces as typed, one per line. A new password must be set before anything else.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_unlock_with_kit(
    handle: *const StillroomStore,
    pieces: *const u8,
    pieces_length: usize,
    vault: *mut *mut StillroomVault,
) -> StillroomStatus {
    call(|| {
        let typed = secret(pieces, pieces_length, "The pieces")?;
        let lines: Vec<&str> = typed.lines().collect();
        give_vault(vault, store(handle)?.unlock_with_kit(&lines)?)
    })
}

/// A wrong try at the lock screen, for both slots' intruder logs: `kind` 0 for a password, 1 for a recovery key. What
/// was typed is never kept. `photo` (a JPEG) may be empty.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_record_intruder(
    handle: *const StillroomStore,
    kind: i32,
    photo: *const u8,
    photo_length: usize,
) -> StillroomStatus {
    call(|| {
        let kind = match kind {
            0 => intruder::Kind::WrongPassword,
            1 => intruder::Kind::WrongRecoveryKey,
            _ => return Err(invalid("The kind is 0 (password) or 1 (recovery key).")),
        };
        let photo = bytes(photo, photo_length, "The photo")?;
        Ok(store(handle)?.record_intruder(kind, (!photo.is_empty()).then_some(photo))?)
    })
}

/// Seconds to wait before the next try at the lock screen (0: now).
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_wait_before_next_try(handle: *const StillroomStore, seconds: *mut u64) -> StillroomStatus {
    call(|| out(seconds, store(handle)?.try_limit().wait_left()))
}

/// A wrong password, recovery key or kit at the lock screen (not a vault locked to a Mac, which isn't a guess).
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_count_wrong_try(handle: *const StillroomStore) -> StillroomStatus {
    call(|| {
        store(handle)?.try_limit().failed();
        Ok(())
    })
}

/// A good try at the lock screen: the wait goes.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_clear_wrong_tries(handle: *const StillroomStore) -> StillroomStatus {
    call(|| {
        store(handle)?.try_limit().succeeded();
        Ok(())
    })
}

/// A backup of the vault while it's locked, into one file at `to` (UTF-8 path).
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_backup(handle: *const StillroomStore, to: *const c_char) -> StillroomStatus {
    call(|| Ok(backup::make(store(handle)?, &path(to, "Where to")?)?))
}

/// Puts the vault back from a backup. Gives where the vault it replaced was set aside, or null when there was none.
/// Lock the vault (free its handle) first.
#[no_mangle]
pub unsafe extern "C" fn stillroom_store_restore(handle: *const StillroomStore, file: *const c_char, set_aside: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let aside = backup::restore(store(handle)?, &path(file, "The backup")?)?;
        give_optional_path(set_aside, aside)
    })
}

/// Whether a file is a Stillroom backup, without touching the vault.
#[no_mangle]
pub unsafe extern "C" fn stillroom_backup_check(file: *const c_char) -> StillroomStatus {
    call(|| Ok(backup::check(&path(file, "The backup")?)?))
}

fn give_optional_path(slot: *mut *mut c_char, value: Option<PathBuf>) -> Result<(), Failure> {
    match value {
        Some(value) => give_string(slot, value.to_string_lossy().into_owned()),
        None => out(slot, std::ptr::null_mut()),
    }
}

// MARK: Open vaults

/// One slot unlocked. Opaque to the app; freeing it is locking.
pub struct StillroomVault(Mutex<Vault>);

fn give_vault(slot: *mut *mut StillroomVault, opened: Vault) -> Result<(), Failure> {
    out(slot, Box::into_raw(Box::new(StillroomVault(Mutex::new(opened)))))
}

fn vault<'a>(handle: *const StillroomVault) -> Result<MutexGuard<'a, Vault>, Failure> {
    if handle.is_null() {
        return Err(invalid("The vault is missing."));
    }
    // SAFETY: the handle came from this file and hasn't been freed; the mutex makes calls on it take turns.
    Ok(unsafe { &(*handle).0 }.lock().unwrap_or_else(|poisoned| poisoned.into_inner()))
}

/// Takes the vault out of its handle, freeing the handle: for calls that end with it locked.
fn take_vault(handle: *mut StillroomVault) -> Result<Vault, Failure> {
    if handle.is_null() {
        return Err(invalid("The vault is missing."));
    }
    // SAFETY: the handle came from this file and is freed here, once.
    let boxed = unsafe { Box::from_raw(handle) };
    Ok(boxed.0.into_inner().unwrap_or_else(|poisoned| poisoned.into_inner()))
}

/// Locks: the keys and everything decrypted are wiped. Null is fine.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_lock(handle: *mut StillroomVault) {
    if !handle.is_null() {
        // SAFETY: as in `take_vault`.
        drop(unsafe { Box::from_raw(handle) });
    }
}

/// Everything the window shows, as JSON: `{"files": [item…], "folders": […], "tags": […], "showInCapture",
/// "hasKit", "kitMade", "mustSetPassword", "intruderWasReset", "intruders", "lockedToAPc", "helloIsMine"}`. An item is as the list keeps it
/// (`id`, `name`, `uti`, `size`, `addedAt`, `folder`, `modifiedAt`, `tags`, `entry`, `versions`, `chunked`, `created`,
/// `contentModified`…), never with a key. Dates are seconds since 2001.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_state(handle: *const StillroomVault, result: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let vault = vault(handle)?;
        give_json(result, &json!({
            "files": vault.files(),
            "folders": vault.folders(),
            "tags": vault.tags(),
            "showInCapture": vault.show_in_capture(),
            "hasKit": vault.has_kit(),
            "kitMade": vault.kit_made(),
            "mustSetPassword": vault.must_set_password(),
            "intruderWasReset": vault.intruder_was_reset(),
            "intruders": vault.intruder_entries().len(),
            "lockedToAPc": vault.is_locked_to_a_pc(),
            "helloIsMine": vault.hello_is_mine(),
        }))
    })
}

/// Adds files and folders (a JSON array of paths) into `folder` (or the top, when null). Gives JSON:
/// `{"items": [id…], "originals": {"files": […], "folders": […]}, "unchecked": [path…], "failed": [{"path",
/// "code", "message"}…], "skipped": n}`. Only `originals` may be deleted (`stillroom_delete_originals`).
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_add(handle: *const StillroomVault, paths: *const c_char, folder: *const c_char, result: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let paths: Vec<PathBuf> = json_in(paths, "The paths")?;
        let folder = optional_text(folder, "The folder")?;
        let added = vault(handle)?.add(&paths, folder);
        let failed: Vec<Value> = added
            .failed
            .into_iter()
            .map(|(path, error)| {
                let failure = Failure::from(error);
                json!({"path": path, "code": failure.code, "message": failure.message})
            })
            .collect();
        give_json(result, &json!({
            "items": added.items,
            "originals": {"files": added.originals.files, "folders": added.originals.folders},
            "unchecked": added.unchecked,
            "failed": failed,
            "skipped": added.skipped,
        }))
    })
}

/// Deletes for good the originals an add checked (`{"files": […], "folders": […]}` as `stillroom_vault_add` gave
/// them): folders whole only when everything in them went in. Gives a JSON array of the names that couldn't be.
#[no_mangle]
pub unsafe extern "C" fn stillroom_delete_originals(originals: *const c_char, result: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        #[derive(serde::Deserialize)]
        struct Given {
            files: Vec<PathBuf>,
            folders: Vec<PathBuf>,
        }
        let given: Given = json_in(originals, "The originals")?;
        give_json(result, &Originals { files: given.files, folders: given.folders }.delete())
    })
}

/// What deleting the originals would remove, as a JSON array of paths: folders whole only when everything in them
/// went in, else their checked files one by one. For moving them to the Recycle Bin instead, by the same rule.
#[no_mangle]
pub unsafe extern "C" fn stillroom_originals_removals(originals: *const c_char, result: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        #[derive(serde::Deserialize)]
        struct Given {
            files: Vec<PathBuf>,
            folders: Vec<PathBuf>,
        }
        let given: Given = json_in(originals, "The originals")?;
        give_json(result, &Originals { files: given.files, folders: given.folders }.removals())
    })
}

/// Bytes held only in memory (an email's attachment) sealed in as a file named `name`, in `folder` (or the top).
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_add_data(
    handle: *const StillroomVault,
    data: *const u8,
    length: usize,
    name: *const c_char,
    folder: *const c_char,
    result: *mut *mut c_char,
) -> StillroomStatus {
    call(|| {
        let id = vault(handle)?.add_data(bytes(data, length, "The data")?, text(name, "The name")?, optional_text(folder, "The folder")?)?;
        give_string(result, id.to_string())
    })
}

/// A new note (`kind` 0, Markdown) or secret (`kind` 1, JSON), in `folder` (or the top). Gives its id.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_new_entry(
    handle: *const StillroomVault,
    kind: i32,
    name: *const c_char,
    content: *const u8,
    content_length: usize,
    folder: *const c_char,
    result: *mut *mut c_char,
) -> StillroomStatus {
    call(|| {
        let kind = match kind {
            0 => Entry::Note,
            1 => Entry::Secret,
            _ => return Err(invalid("The kind is 0 (note) or 1 (secret).")),
        };
        let id = vault(handle)?.new_entry(kind, text(name, "The name")?, bytes(content, content_length, "The content")?, optional_text(folder, "The folder")?)?;
        give_string(result, id.to_string())
    })
}

/// An item's current contents, or (when `version` isn't null) one of its earlier versions.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_read(handle: *const StillroomVault, item: *const c_char, version: *const c_char, result: *mut StillroomBytes) -> StillroomStatus {
    call(|| {
        let item = id(item)?;
        let vault = vault(handle)?;
        let mut data = match optional_text(version, "The version")? {
            Some(version) => vault.read_version(&item, &version.parse().map_err(|_| invalid("That isn't a version's id."))?)?,
            None => vault.read(&item)?,
        };
        give_bytes(result, std::mem::take(&mut *data))
    })
}

/// An item written out to `to` (a copy the person saves, or a working copy), with its dates, marked as downloaded.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_export_item(handle: *const StillroomVault, item: *const c_char, to: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.export_item(&id(item)?, &path(to, "Where to")?)?))
}

/// Everything out, unencrypted, in a new folder "Stillroom Export <date>" inside `parent`. Gives JSON: `{"folder",
/// "taken", "failed": [{"path", "message"}…]}`.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_export_all(handle: *const StillroomVault, parent: *const c_char, result: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let vault = vault(handle)?;
        let (folder, report) = export::export_all(&vault, &path(parent, "Where to")?, |_| {})?;
        let failed: Vec<Value> = report.failed.iter().map(|(path, why)| json!({"path": path, "message": why.to_string()})).collect();
        give_json(result, &json!({"folder": folder, "taken": report.taken, "failed": failed}))
    })
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_delete(handle: *const StillroomVault, item: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.delete(&id(item)?)?))
}

/// New contents for an item, from memory, and a new name when `name` isn't null. What it held is kept as a version
/// when it hadn't changed for ten minutes.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_update(
    handle: *const StillroomVault,
    item: *const c_char,
    data: *const u8,
    length: usize,
    name: *const c_char,
) -> StillroomStatus {
    call(|| Ok(vault(handle)?.update(&id(item)?, Contents::Bytes(bytes(data, length, "The data")?), optional_text(name, "The name")?)?))
}

/// New contents for an item from a file on disk (a save from editing in place): big ones go in chunks.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_update_from_file(handle: *const StillroomVault, item: *const c_char, file: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.update(&id(item)?, Contents::File(&path(file, "The file")?), None)?))
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_restore_version(handle: *const StillroomVault, item: *const c_char, version: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.restore_version(&id(item)?, &id(version)?)?))
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_drop_version(handle: *const StillroomVault, item: *const c_char, version: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.drop_version(&id(item)?, &id(version)?)?))
}

/// Damaged current contents swapped for an earlier version that still opens.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_fall_back(handle: *const StillroomVault, item: *const c_char, version: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.fall_back(&id(item)?, &id(version)?)?))
}

/// Reads every item and version through. Gives a JSON array of what doesn't open: `[{"item", "version",
/// "fallback"}…]` (`version` null for current contents; `fallback` the newest version that still opens).
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_check(handle: *const StillroomVault, result: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let found = vault(handle)?.check(|_, _| {});
        let found: Vec<Value> = found.iter().map(|d| json!({"item": d.item, "version": d.version, "fallback": d.fallback})).collect();
        give_json(result, &found)
    })
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_rename(handle: *const StillroomVault, item: *const c_char, name: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.rename(&id(item)?, text(name, "The name")?)?))
}

/// `tags`: a JSON array of strings (empty: none).
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_set_tags(handle: *const StillroomVault, item: *const c_char, tags: *const c_char) -> StillroomStatus {
    call(|| {
        let tags: Vec<String> = json_in(tags, "The tags")?;
        Ok(vault(handle)?.set_tags(&id(item)?, &tags)?)
    })
}

/// A folder made in `parent` (or the top). A "/" typed in the name is kept as a look-alike.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_make_folder(handle: *const StillroomVault, name: *const c_char, parent: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.make_folder(text(name, "The name")?, optional_text(parent, "The parent")?)?))
}

/// Items (a JSON array of ids) into `folder` (or the top).
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_move_items(handle: *const StillroomVault, items: *const c_char, folder: *const c_char) -> StillroomStatus {
    call(|| {
        let items: Vec<Uuid> = json_in(items, "The items")?;
        Ok(vault(handle)?.move_items(&items, optional_text(folder, "The folder")?)?)
    })
}

/// Renames a folder, carrying everything inside it along. Gives its new path, or null when nothing changed.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_rename_folder(handle: *const StillroomVault, folder: *const c_char, name: *const c_char, result: *mut *mut c_char) -> StillroomStatus {
    call(|| match vault(handle)?.rename_folder(text(folder, "The folder")?, text(name, "The name")?)? {
        Some(path) => give_string(result, path),
        None => out(result, std::ptr::null_mut()),
    })
}

/// A folder, with everything in it, into another (or the top, when `into` is null).
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_move_folder(handle: *const StillroomVault, folder: *const c_char, into: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.move_folder(text(folder, "The folder")?, optional_text(into, "The folder to go into")?)?))
}

/// A folder and everything inside it, versions too, deleted.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_delete_folder(handle: *const StillroomVault, folder: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.delete_folder(text(folder, "The folder")?)?))
}

/// Shown in screenshots and screen sharing while open: kept sealed in the vault.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_set_show_in_capture(handle: *const StillroomVault, on: bool) -> StillroomStatus {
    call(|| Ok(vault(handle)?.set_show_in_capture(on)?))
}

// MARK: Keys

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_change_password(
    handle: *const StillroomVault,
    current: *const u8,
    current_length: usize,
    new: *const u8,
    new_length: usize,
) -> StillroomStatus {
    call(|| {
        let (current, new) = (secret(current, current_length, "The password")?, secret(new, new_length, "The new password")?);
        Ok(vault(handle)?.change_password(current, new)?)
    })
}

/// After a recovery key or the kit: the new password.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_set_password_after_recovery(handle: *const StillroomVault, new: *const u8, new_length: usize) -> StillroomStatus {
    call(|| Ok(vault(handle)?.set_password_after_recovery(secret(new, new_length, "The new password")?)?))
}

/// A decoy password: the other slot becomes a new, empty vault it opens. Gives that vault's recovery key, to be shown
/// once.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_set_other_slot(handle: *const StillroomVault, password: *const u8, password_length: usize, recovery_key: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let code = vault(handle)?.set_other_slot(secret(password, password_length, "The password")?)?;
        give_string(recovery_key, code)
    })
}

/// No decoy: the other slot becomes one whose passwords nobody knows.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_reset_other_slot(handle: *const StillroomVault) -> StillroomStatus {
    call(|| Ok(vault(handle)?.reset_other_slot()?))
}

/// A new recovery key for the open vault, to be shown once; the old one stops working.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_new_recovery_key(handle: *const StillroomVault, recovery_key: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let code = vault(handle)?.new_recovery_key()?;
        give_string(recovery_key, code)
    })
}

/// A new emergency kit: `count` pieces, any `threshold` of which open this vault. Gives the pieces as a JSON array of
/// strings, to be printed once. Any earlier kit stops working.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_make_kit(handle: *const StillroomVault, threshold: u8, count: u8, pieces: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let made = Zeroizing::new(vault(handle)?.make_kit(threshold, count)?);
        give_json(pieces, &*made)
    })
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_remove_kit(handle: *const StillroomVault) -> StillroomStatus {
    call(|| Ok(vault(handle)?.remove_kit()?))
}

/// Whether to say, now, that the kit is a year old (it's then remembered as said).
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_kit_reminder_due(handle: *const StillroomVault, result: *mut bool) -> StillroomStatus {
    call(|| out(result, vault(handle)?.kit_reminder_due()?))
}

/// Locks both vaults' password keys to this PC's TPM. Gives a new recovery key for this vault, to be shown once (null
/// when it was already locked). `STILLROOM_LOCKED_ELSEWHERE` when it's locked to a Mac; `STILLROOM_NO_TPM` without one.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_lock_to_this_pc(handle: *const StillroomVault, recovery_key: *mut *mut c_char) -> StillroomStatus {
    call(|| match vault(handle)?.lock_to_this_pc()? {
        Some(code) => give_string(recovery_key, code),
        None => out(recovery_key, std::ptr::null_mut()),
    })
}

/// The lock off: both password keys back as they were, and the TPM key deleted.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_unlock_from_this_pc(handle: *const StillroomVault) -> StillroomStatus {
    call(|| Ok(vault(handle)?.unlock_from_this_pc()?))
}

/// Windows Hello opens this vault from now on: the challenge (from `stillroom_hello_new_challenge`), Windows Hello's
/// signature of it, and the credential's public key. Wipe the signature afterwards: it opens the vault.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_turn_on_hello(
    handle: *const StillroomVault,
    challenge: *const u8,
    challenge_length: usize,
    signature: *const u8,
    signature_length: usize,
    public_key: *const u8,
    public_key_length: usize,
) -> StillroomStatus {
    call(|| {
        let challenge = bytes(challenge, challenge_length, "The challenge")?;
        let signature = bytes(signature, signature_length, "The signature")?;
        let public_key = bytes(public_key, public_key_length, "The public key")?;
        Ok(vault(handle)?.turn_on_hello(challenge, signature, public_key)?)
    })
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_turn_off_hello(handle: *const StillroomVault) -> StillroomStatus {
    call(|| Ok(vault(handle)?.turn_off_hello()?))
}

// MARK: Intruders

/// The intruder log, newest first, as JSON: `[{"id", "date", "kind": "wrongPassword"|"wrongRecoveryKey", "photo":
/// base64 JPEG or null}…]`.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_intruders(handle: *const StillroomVault, result: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let entries: Vec<Value> = vault(handle)?
            .intruder_entries()
            .iter()
            .map(|e| json!({
                "id": e.id,
                "date": e.date,
                "kind": e.kind,
                "photo": e.photo.as_ref().map(|p| base64::engine::general_purpose::STANDARD.encode(p)),
            }))
            .collect();
        give_json(result, &entries)
    })
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_delete_intruder(handle: *const StillroomVault, entry: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.delete_intruder(&id(entry)?)?))
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_clear_intruders(handle: *const StillroomVault) -> StillroomStatus {
    call(|| Ok(vault(handle)?.clear_intruders()?))
}

// MARK: Search

/// Reads the text of what only the app can (a PDF, the words in a picture): given the item (JSON) and its contents,
/// returns UTF-8 text, or null for none. What it returns must stay valid until it's called again or the refresh ends.
pub type StillroomReadText = Option<extern "C" fn(context: *mut c_void, item: *const c_char, data: *const u8, length: usize) -> *const c_char>;

/// Reads every item whose words aren't known or have changed, and seals the index. `read_text` (may be null) reads
/// PDFs and pictures. Gives whether anything changed.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_refresh_search(
    handle: *const StillroomVault,
    read_text: StillroomReadText,
    context: *mut c_void,
    changed: *mut bool,
) -> StillroomStatus {
    call(|| {
        let mut vault = vault(handle)?;
        let extra = read_text.map(|read| {
            move |item: &Item, data: &[u8]| -> Option<String> {
                let item = CString::new(serde_json::to_string(item).ok()?).ok()?;
                let text = read(context, item.as_ptr(), data.as_ptr(), data.len());
                if text.is_null() {
                    return None;
                }
                // SAFETY: the app returns a NUL-terminated string valid until its next call.
                Some(unsafe { CStr::from_ptr(text) }.to_string_lossy().into_owned())
            }
        });
        let result = vault.refresh_search(extra.as_ref().map(|f| f as &dyn Fn(&Item, &[u8]) -> Option<String>))?;
        out(changed, result)
    })
}

/// Items whose name, tags or words hold `query`: a JSON array of ids.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_search(handle: *const StillroomVault, query: *const c_char, result: *mut *mut c_char) -> StillroomStatus {
    call(|| give_json(result, &vault(handle)?.search(text(query, "The query")?)))
}

/// A piece of an item's words around `query`, or null.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_snippet(handle: *const StillroomVault, item: *const c_char, query: *const c_char, result: *mut *mut c_char) -> StillroomStatus {
    call(|| match vault(handle)?.snippet(&id(item)?, text(query, "The query")?) {
        Some(snippet) => give_string(result, snippet),
        None => out(result, std::ptr::null_mut()),
    })
}

// MARK: Importing passwords

/// Accounts from a password export (CSV bytes), each a Login secret in "Imported". Gives JSON `{"added", "skipped"}`.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_import_logins(handle: *const StillroomVault, csv: *const u8, csv_length: usize, result: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let logins = import::logins(bytes(csv, csv_length, "The export")?)
            .map_err(|e| Failure { code: STILLROOM_NOT_AN_EXPORT, message: e.to_string() })?;
        let (added, skipped) = vault(handle)?.import_logins(&logins)?;
        give_json(result, &json!({"added": added, "skipped": skipped}))
    })
}

// MARK: Backups and endings

/// A backup of the open vault into one file at `to`. No save can land while it's made.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_backup(handle: *const StillroomVault, to: *const c_char) -> StillroomStatus {
    call(|| Ok(vault(handle)?.backup(&path(to, "Where to")?)?))
}

/// Puts the vault back from a backup. The vault is locked first, so its handle is freed whatever happens. Gives where
/// the vault it replaced was set aside, or null.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_restore_backup(handle: *mut StillroomVault, file: *const c_char, set_aside: *mut *mut c_char) -> StillroomStatus {
    call(|| {
        let opened = take_vault(handle)?;
        let file = path(file, "The backup")?;
        give_optional_path(set_aside, opened.restore_backup(&file)?)
    })
}

/// The vault and every file in it, for good. Its handle is freed whatever happens.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_wipe(handle: *mut StillroomVault) -> StillroomStatus {
    call(|| Ok(take_vault(handle)?.wipe()?))
}

// MARK: Playing audio and video

/// A chunked item read a range at a time, straight from its sealed file, for a player. Holds its own copy of the
/// item's key (in locked memory) until freed.
pub struct StillroomReader(ChunkedReader);

/// A reader for an item sealed in chunks (all audio and video, and anything over 8 MiB). Gives its real size.
#[no_mangle]
pub unsafe extern "C" fn stillroom_vault_open_reader(handle: *const StillroomVault, item: *const c_char, reader: *mut *mut StillroomReader, size: *mut u64) -> StillroomStatus {
    call(|| {
        let vault = vault(handle)?;
        let item = vault.item(&id(item)?).ok_or(Error::NotFound)?;
        if !item.is_chunked() {
            return Err(invalid("That item isn't sealed in chunks: read it whole."));
        }
        let sealed_as = item.sealed_as.ok_or(VaultError::Damaged)?;
        let key = vault.item_key(&sealed_as).ok_or(VaultError::Damaged)?;
        let opened = ChunkedReader::open(&vault.store().blob(&sealed_as), key, &sealed_as, item.size)?;
        out(size, opened.plain_size())?;
        out(reader, Box::into_raw(Box::new(StillroomReader(opened))))
    })
}

/// Up to `capacity` bytes from `offset` into `buffer`; gives how many (fewer at the end, 0 past it).
#[no_mangle]
pub unsafe extern "C" fn stillroom_reader_read(reader: *const StillroomReader, offset: u64, buffer: *mut u8, capacity: usize, read: *mut usize) -> StillroomStatus {
    call(|| {
        if reader.is_null() || (buffer.is_null() && capacity > 0) {
            return Err(invalid("The reader or the buffer is missing."));
        }
        // SAFETY: the reader came from `stillroom_vault_open_reader` and isn't freed; the buffer holds `capacity`.
        let reader = unsafe { &(*reader).0 };
        let data = reader.read(offset..offset.saturating_add(capacity as u64))?;
        // SAFETY: data.len() <= capacity, as the range asked for is that long at most.
        unsafe { std::ptr::copy_nonoverlapping(data.as_ptr(), buffer, data.len()) };
        out(read, data.len())
    })
}

#[no_mangle]
pub unsafe extern "C" fn stillroom_reader_free(reader: *mut StillroomReader) {
    if !reader.is_null() {
        // SAFETY: the reader came from `stillroom_vault_open_reader` and is freed once.
        drop(unsafe { Box::from_raw(reader) });
    }
}

// MARK: Without a vault

/// How many bits a guesser would need for this password, roughly; 50 is enough.
#[no_mangle]
pub unsafe extern "C" fn stillroom_password_strength(password: *const u8, password_length: usize, bits: *mut f64, enough: *mut bool) -> StillroomStatus {
    call(|| {
        let password = secret(password, password_length, "The password")?;
        let found = strength::bits(password);
        out(bits, found)?;
        out(enough, found >= strength::ENOUGH)
    })
}

/// The two-factor code a secret's field shows (an otpauth link, or a setup key under a label that says so), at
/// `unix_seconds`. Gives null when the field holds none.
#[no_mangle]
pub unsafe extern "C" fn stillroom_one_time_code(
    label: *const c_char,
    value: *const u8,
    value_length: usize,
    unix_seconds: f64,
    code: *mut *mut c_char,
    seconds_left: *mut u64,
) -> StillroomStatus {
    call(|| match otp::in_field(text(label, "The label")?, secret(value, value_length, "The value")?) {
        Some(found) => {
            out(seconds_left, found.seconds_left(unix_seconds))?;
            give_string(code, found.code(unix_seconds))
        }
        None => out(code, std::ptr::null_mut()),
    })
}

/// The UTI a file named `name` gets (as the Mac names kinds).
#[no_mangle]
pub unsafe extern "C" fn stillroom_uti_for_name(name: *const c_char, result: *mut *mut c_char) -> StillroomStatus {
    call(|| give_string(result, kinds::uti_for_name(text(name, "The name")?).to_owned()))
}

/// How a kind looks, for its symbol and its shelf: 0 other, 1 picture, 2 audio, 3 video, 4 PDF, 5 text, 6 document
/// (office files), 7 archive. Pictures go on Images; audio and video on Audio & Video; PDFs, text and documents on
/// Documents; the rest on Other.
#[no_mangle]
pub unsafe extern "C" fn stillroom_look(uti: *const c_char, result: *mut u8) -> StillroomStatus {
    call(|| out(result, kinds::look(text(uti, "The kind")?) as u8))
}

/// Whether an item may be opened in another app: documents, pictures, PDFs, audio and video only.
#[no_mangle]
pub unsafe extern "C" fn stillroom_can_edit(uti: *const c_char, name: *const c_char, is_file: bool, result: *mut bool) -> StillroomStatus {
    call(|| out(result, kinds::can_edit(text(uti, "The kind")?, text(name, "The name")?, is_file)))
}

/// An email (.eml or .emlx bytes) read into JSON: `{"from", "to", "cc", "subject", "date", "page", "text",
/// "attachments": [{"name", "kind", "size"}…]}`. `page` is the HTML to show; nothing in it may be fetched. Gives null
/// when the bytes aren't an email.
#[no_mangle]
pub unsafe extern "C" fn stillroom_email_read(data: *const u8, length: usize, result: *mut *mut c_char) -> StillroomStatus {
    call(|| match email::parse(bytes(data, length, "The email")?) {
        Some(found) => {
            let attachments: Vec<Value> =
                found.attachments.iter().map(|a| json!({"name": a.name, "kind": a.kind, "size": a.data.len()})).collect();
            give_json(result, &json!({
                "from": found.from, "to": found.to, "cc": found.cc, "subject": found.subject, "date": found.date,
                "page": found.page(), "text": found.text, "attachments": attachments,
            }))
        }
        None => out(result, std::ptr::null_mut()),
    })
}

/// One of an email's attachments, by its place in `attachments`.
#[no_mangle]
pub unsafe extern "C" fn stillroom_email_attachment(data: *const u8, length: usize, index: usize, result: *mut StillroomBytes) -> StillroomStatus {
    call(|| {
        let found = email::parse(bytes(data, length, "The email")?).ok_or_else(|| invalid("That isn't an email."))?;
        let attachment = found.attachments.into_iter().nth(index).ok_or(Error::NotFound)?;
        give_bytes(result, attachment.data)
    })
}
