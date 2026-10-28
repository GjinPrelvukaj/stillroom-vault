//! "Lock to this PC" (the Windows counterpart of `Crypto/MacLock.swift`): a key made inside this PC's TPM, which can't
//! be copied off the chip, wraps a random 32-byte outer key; every slot's password key is sealed again with that outer
//! key. A copy of the vault folder then opens on no other PC, even with the password; the recovery key and the kit
//! still open it anywhere.
//!
//! The TPM key is a 2048-bit RSA key in Windows' Platform Crypto Provider, non-exportable, kept in this account's key
//! store under a name of its own. The outer key is wrapped with RSA-OAEP (SHA-256). Only Windows ever reads `pc.key`:
//!
//! ```text
//! pc.key   {"key": "<the TPM key's name>", "wrapped": "<base64 of the outer key, RSA-OAEP-wrapped>"}
//! ```

use base64::Engine as _;
use serde::{Deserialize, Serialize};

use crate::crypto::Key;
use crate::VaultError;

#[derive(Serialize, Deserialize)]
pub struct PcKey {
    /// The TPM key's name in this account's key store.
    pub key: String,
    /// The outer key, wrapped by the TPM key.
    pub wrapped: String,
}

/// Whether this PC has a TPM Windows lets the app use.
pub fn available() -> bool {
    platform::available()
}

/// A new TPM key and outer key: gives the file's contents and the outer key.
pub fn make() -> Result<(PcKey, Key), VaultError> {
    let name = format!("Stillroom vault lock {}", uuid::Uuid::new_v4().hyphenated());
    let outer = Key::random();
    let wrapped = platform::make_and_wrap(&name, outer.as_bytes())?;
    Ok((PcKey { key: name, wrapped: base64::engine::general_purpose::STANDARD.encode(wrapped) }, outer))
}

/// The outer key, unwrapped by this PC's TPM. `NotThisComputer` when the TPM key isn't here (another PC, or removed).
pub fn unwrap(file: &PcKey) -> Result<Key, VaultError> {
    let wrapped = base64::engine::general_purpose::STANDARD.decode(&file.wrapped).map_err(|_| VaultError::Damaged)?;
    let outer = platform::unwrap(&file.key, &wrapped)?;
    Key::from_slice(&outer)
}

/// The TPM key deleted from this account's key store. Missing is fine.
pub fn delete(file: &PcKey) {
    platform::delete(&file.key);
}

#[cfg(windows)]
mod platform {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;

    use windows_sys::Win32::Security::Cryptography::{
        NCryptCreatePersistedKey, NCryptDecrypt, NCryptDeleteKey, NCryptEncrypt, NCryptFinalizeKey, NCryptFreeObject,
        NCryptOpenKey, NCryptOpenStorageProvider, NCryptSetProperty, BCRYPT_OAEP_PADDING_INFO, BCRYPT_RSA_ALGORITHM,
        BCRYPT_SHA256_ALGORITHM, MS_PLATFORM_CRYPTO_PROVIDER, NCRYPT_KEY_HANDLE, NCRYPT_LENGTH_PROPERTY,
        NCRYPT_PAD_OAEP_FLAG, NCRYPT_PROV_HANDLE, NCRYPT_SILENT_FLAG,
    };
    use zeroize::Zeroizing;

    use crate::VaultError;

    fn wide(text: &str) -> Vec<u16> {
        OsStr::new(text).encode_wide().chain(Some(0)).collect()
    }

    /// The Platform Crypto Provider, freed when dropped.
    struct Provider(NCRYPT_PROV_HANDLE);

    impl Provider {
        fn open() -> Option<Provider> {
            let mut handle = 0;
            // SAFETY: a plain call with an out handle, freed in Drop.
            (unsafe { NCryptOpenStorageProvider(&mut handle, MS_PLATFORM_CRYPTO_PROVIDER, 0) } >= 0).then_some(Provider(handle))
        }
    }

    impl Drop for Provider {
        fn drop(&mut self) {
            // SAFETY: the handle came from NCryptOpenStorageProvider.
            unsafe { NCryptFreeObject(self.0) };
        }
    }

    /// A key handle, freed when dropped (unless deleted, which frees it).
    struct KeyHandle(NCRYPT_KEY_HANDLE);

    impl Drop for KeyHandle {
        fn drop(&mut self) {
            if self.0 != 0 {
                // SAFETY: the handle came from NCrypt and wasn't freed by a delete.
                unsafe { NCryptFreeObject(self.0) };
            }
        }
    }

    fn open_key(provider: &Provider, name: &str) -> Option<KeyHandle> {
        let mut key = 0;
        let name = wide(name);
        // SAFETY: the name is NUL-terminated; the handle is freed in Drop.
        (unsafe { NCryptOpenKey(provider.0, &mut key, name.as_ptr(), 0, NCRYPT_SILENT_FLAG) } >= 0).then_some(KeyHandle(key))
    }

    fn padding() -> BCRYPT_OAEP_PADDING_INFO {
        BCRYPT_OAEP_PADDING_INFO { pszAlgId: BCRYPT_SHA256_ALGORITHM, pbLabel: std::ptr::null_mut(), cbLabel: 0 }
    }

    pub fn available() -> bool {
        Provider::open().is_some()
    }

    pub fn make_and_wrap(name: &str, secret: &[u8; 32]) -> Result<Vec<u8>, VaultError> {
        let provider = Provider::open().ok_or(VaultError::HelloUnavailable)?;
        let wide_name = wide(name);
        let mut key = KeyHandle(0);
        // SAFETY: plain NCrypt calls on handles owned here; every buffer is as long as said.
        unsafe {
            if NCryptCreatePersistedKey(provider.0, &mut key.0, BCRYPT_RSA_ALGORITHM, wide_name.as_ptr(), 0, 0) < 0 {
                return Err(VaultError::HelloUnavailable);
            }
            let bits: u32 = 2048;
            NCryptSetProperty(key.0, NCRYPT_LENGTH_PROPERTY, (&bits as *const u32).cast(), 4, 0);
            if NCryptFinalizeKey(key.0, NCRYPT_SILENT_FLAG) < 0 {
                return Err(VaultError::HelloUnavailable);
            }
            let padding = padding();
            let mut length = 0u32;
            let info = (&padding as *const BCRYPT_OAEP_PADDING_INFO).cast();
            if NCryptEncrypt(key.0, secret.as_ptr(), 32, info, std::ptr::null_mut(), 0, &mut length, NCRYPT_PAD_OAEP_FLAG) < 0 {
                delete_handle(&mut key);
                return Err(VaultError::HelloUnavailable);
            }
            let mut wrapped = vec![0u8; length as usize];
            if NCryptEncrypt(key.0, secret.as_ptr(), 32, info, wrapped.as_mut_ptr(), length, &mut length, NCRYPT_PAD_OAEP_FLAG) < 0 {
                delete_handle(&mut key);
                return Err(VaultError::HelloUnavailable);
            }
            wrapped.truncate(length as usize);
            Ok(wrapped)
        }
    }

    pub fn unwrap(name: &str, wrapped: &[u8]) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        let provider = Provider::open().ok_or(VaultError::NotThisComputer)?;
        let key = open_key(&provider, name).ok_or(VaultError::NotThisComputer)?;
        let padding = padding();
        let info = (&padding as *const BCRYPT_OAEP_PADDING_INFO).cast();
        let mut outer = Zeroizing::new(vec![0u8; wrapped.len()]);
        let mut length = 0u32;
        // SAFETY: the output buffer is as long as the input, more than RSA-OAEP's plaintext can be.
        let status = unsafe {
            NCryptDecrypt(key.0, wrapped.as_ptr(), wrapped.len() as u32, info, outer.as_mut_ptr(), outer.len() as u32, &mut length, NCRYPT_PAD_OAEP_FLAG | NCRYPT_SILENT_FLAG)
        };
        if status < 0 {
            return Err(VaultError::NotThisComputer);
        }
        outer.truncate(length as usize);
        Ok(outer)
    }

    fn delete_handle(key: &mut KeyHandle) {
        // No flags: the Platform Crypto Provider refuses NCRYPT_SILENT_FLAG on a delete (NTE_BAD_FLAGS), and a delete
        // shows no UI anyway. Deleting frees the handle, so it's cleared and not freed again.
        // SAFETY: the handle came from NCrypt.
        unsafe { NCryptDeleteKey(key.0, 0) };
        key.0 = 0;
    }

    pub fn delete(name: &str) {
        let Some(provider) = Provider::open() else { return };
        if let Some(mut key) = open_key(&provider, name) {
            delete_handle(&mut key);
        }
    }
}

#[cfg(not(windows))]
mod platform {
    use zeroize::Zeroizing;

    use crate::VaultError;

    pub fn available() -> bool {
        false
    }

    pub fn make_and_wrap(_name: &str, _secret: &[u8; 32]) -> Result<Vec<u8>, VaultError> {
        Err(VaultError::HelloUnavailable)
    }

    pub fn unwrap(_name: &str, _wrapped: &[u8]) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        Err(VaultError::NotThisComputer)
    }

    pub fn delete(_name: &str) {}
}
