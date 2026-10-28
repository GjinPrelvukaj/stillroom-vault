//! Argon2id (RFC 9106, version 0x13), by the reference C in `macos/Sources/CArgon2`: the port of `Crypto/Argon2.swift`. A
//! password stretched through `memory_kib` of memory, so every guess costs an attacker that much RAM as well as time.
//! The library wipes its memory, and the copies of the password and secret made here, before returning.

use core::ffi::c_int;
use core::ptr;
use std::sync::atomic::{AtomicU64, Ordering};
use zeroize::Zeroizing;

use crate::VaultError;

#[doc(hidden)]
/// How many stretches this process has run: for tests that check every try costs the same, by count rather than by
/// timing. Nothing else reads it.
pub static STRETCHES: AtomicU64 = AtomicU64::new(0);

/// `argon2_context` from argon2.h, field for field.
#[repr(C)]
struct Argon2Context {
    out: *mut u8,
    outlen: u32,
    pwd: *mut u8,
    pwdlen: u32,
    salt: *mut u8,
    saltlen: u32,
    secret: *mut u8,
    secretlen: u32,
    ad: *mut u8,
    adlen: u32,
    t_cost: u32,
    m_cost: u32,
    lanes: u32,
    threads: u32,
    version: u32,
    allocate_cbk: Option<unsafe extern "C" fn(*mut *mut u8, usize) -> c_int>,
    free_cbk: Option<unsafe extern "C" fn(*mut u8, usize)>,
    flags: u32,
}

extern "C" {
    fn argon2_ctx(context: *mut Argon2Context, kind: c_int) -> c_int;
}

const ARGON2_OK: c_int = 0;
const ARGON2_ID: c_int = 2;
const ARGON2_VERSION_13: u32 = 0x13;
/// ARGON2_FLAG_CLEAR_PASSWORD | ARGON2_FLAG_CLEAR_SECRET.
const CLEAR_PASSWORD_AND_SECRET: u32 = 1 << 0 | 1 << 1;

/// The tag of `length` bytes for this password and salt. Fails with `Damaged` on parameters the C refuses or memory
/// it can't get: only a damaged or doctored key file asks for either.
#[allow(clippy::too_many_arguments)]
pub fn argon2id(
    password: &[u8],
    salt: &[u8],
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
    length: usize,
    secret: &[u8],
    associated_data: &[u8],
) -> Result<Zeroizing<Vec<u8>>, VaultError> {
    // The C wipes the password and secret it's given, so it gets copies; they're wiped here too in case it fails early.
    let mut pwd = Zeroizing::new(password.to_vec());
    let mut key = Zeroizing::new(secret.to_vec());
    let mut salt = salt.to_vec();
    let mut ad = associated_data.to_vec();
    let mut out = Zeroizing::new(vec![0u8; length]);

    // Empty inputs go in as null, as the Swift wrapper passes them.
    fn ptr_of(bytes: &mut [u8]) -> *mut u8 {
        if bytes.is_empty() { ptr::null_mut() } else { bytes.as_mut_ptr() }
    }
    fn len(bytes: &[u8]) -> Result<u32, VaultError> {
        u32::try_from(bytes.len()).map_err(|_| VaultError::Damaged)
    }

    let mut context = Argon2Context {
        out: ptr_of(&mut out),
        outlen: len(&out)?,
        pwd: ptr_of(&mut pwd),
        pwdlen: len(&pwd)?,
        salt: ptr_of(&mut salt),
        saltlen: len(&salt)?,
        secret: ptr_of(&mut key),
        secretlen: len(&key)?,
        ad: ptr_of(&mut ad),
        adlen: len(&ad)?,
        t_cost: iterations,
        m_cost: memory_kib,
        lanes: parallelism,
        threads: parallelism,
        version: ARGON2_VERSION_13,
        allocate_cbk: None,
        free_cbk: None,
        flags: CLEAR_PASSWORD_AND_SECRET,
    };
    // SAFETY: every pointer refers to a live buffer of the length beside it (or is null with length 0), and all of
    // them outlive the call.
    let status = unsafe { argon2_ctx(&mut context, ARGON2_ID) };
    STRETCHES.fetch_add(1, Ordering::Relaxed);
    if status != ARGON2_OK {
        return Err(VaultError::Damaged);
    }
    Ok(out)
}
