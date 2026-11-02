//! Whether a file of Stillroom's is still signed by Stillroom's maker: the Mac's `SelfCheck`, by Authenticode. A copy
//! someone changed, a crack among them, has to be signed again by someone else, or not at all, and fails. It protects
//! people who downloaded a doctored Stillroom, not the licence: whoever changes the app can take this out too.
//!
//! Windows checks the signature (`WinVerifyTrust`, Authenticode's policy: the file's hash, a code-signing certificate,
//! a chain to a root this PC trusts), and then the signer has to be `PUBLISHER`. Offline: revocation isn't checked
//! and nothing is fetched (`WTD_CACHE_ONLY_URL_RETRIEVAL`), so a chain needing a download fails rather than going
//! online. A release signature is timestamped, so it stays good after the certificate expires.
//!
//! There's no certificate yet, so `PUBLISHER` is unset and every file reads `Signed::NotSetUp`: nothing to warn about.
//! Development builds can try it with a self-signed certificate: `STILLROOM_SIGNER_TEST` names its subject, and a root
//! this PC doesn't trust is then accepted (`windows/sign.ps1 -Test` makes one).

use std::path::Path;

/// The signing certificate's subject name (its CN) once Stillroom has one. A name rather than one certificate's
/// thumbprint, so renewing it (or a service that issues a new one every few days) doesn't change the app, as the Mac
/// checks its team rather than one certificate.
pub const PUBLISHER: Option<&str> = None;

/// What `check` found.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum Signed {
    /// Signed by `PUBLISHER`, unchanged since.
    ByUs = 0,
    /// No signature at all.
    NotSigned = 1,
    /// Signed, but changed since: the hash doesn't match.
    Changed = 2,
    /// Signed by someone else, or by a certificate this PC doesn't trust.
    SomeoneElse = 3,
    /// Nothing to check against: no publisher is set (no certificate yet).
    NotSetUp = 4,
}

/// Checks `file` against the publisher: `PUBLISHER`, or in a development build `STILLROOM_SIGNER_TEST`.
pub fn check(file: &Path) -> Signed {
    #[cfg(debug_assertions)]
    if let Ok(test) = std::env::var("STILLROOM_SIGNER_TEST") {
        if !test.is_empty() {
            return check_against(file, &test, true);
        }
    }
    match PUBLISHER {
        Some(publisher) => check_against(file, publisher, false),
        None => Signed::NotSetUp,
    }
}

/// Checks `file` is signed by a certificate named `publisher`, unchanged; `untrusted_root` accepts a chain ending in a
/// root this PC doesn't trust (a self-signed test certificate), never in a release.
pub fn check_against(file: &Path, publisher: &str, untrusted_root: bool) -> Signed {
    match windows::verify(file) {
        Verified::Unsigned => Signed::NotSigned,
        Verified::BadHash => Signed::Changed,
        Verified::Untrusted(Some(name)) if untrusted_root && name == publisher => Signed::ByUs,
        Verified::Untrusted(_) => Signed::SomeoneElse,
        Verified::Trusted(name) if name == publisher => Signed::ByUs,
        Verified::Trusted(_) => Signed::SomeoneElse,
    }
}

enum Verified {
    Unsigned,
    BadHash,
    /// Signed and unchanged, by this subject, chained to a trusted root.
    Trusted(String),
    /// Signed but not trusted (the name, when the chain got as far as a signer: a self-signed certificate does).
    Untrusted(Option<String>),
}

#[cfg(windows)]
mod windows {
    use std::os::windows::ffi::OsStrExt;
    use std::path::Path;
    use std::ptr::null_mut;

    use windows_sys::Win32::Foundation::{CERT_E_UNTRUSTEDROOT, TRUST_E_BAD_DIGEST, TRUST_E_NOSIGNATURE, TRUST_E_SUBJECT_FORM_UNKNOWN};
    use windows_sys::Win32::Security::Cryptography::{CertGetNameStringW, CERT_NAME_SIMPLE_DISPLAY_TYPE};
    use windows_sys::Win32::Security::WinTrust::{
        WTHelperGetProvSignerFromChain, WTHelperProvDataFromStateData, WinVerifyTrust, WINTRUST_ACTION_GENERIC_VERIFY_V2,
        WINTRUST_DATA, WINTRUST_DATA_0, WINTRUST_FILE_INFO, WTD_CACHE_ONLY_URL_RETRIEVAL, WTD_CHOICE_FILE,
        WTD_REVOKE_NONE, WTD_STATEACTION_CLOSE, WTD_STATEACTION_VERIFY, WTD_UI_NONE,
    };

    use super::Verified;

    /// The signature changed, or its signing doesn't verify.
    const TRUST_E_NO_SIGNER_CERT: i32 = 0x8009_6002_u32 as i32;
    const TRUST_E_CERT_SIGNATURE: i32 = 0x8009_6004_u32 as i32;
    const CRYPT_E_SECURITY_SETTINGS: i32 = 0x8009_2026_u32 as i32;

    pub(super) fn verify(file: &Path) -> Verified {
        let path: Vec<u16> = file.as_os_str().encode_wide().chain(Some(0)).collect();
        let mut info = WINTRUST_FILE_INFO {
            cbStruct: size_of::<WINTRUST_FILE_INFO>() as u32,
            pcwszFilePath: path.as_ptr(),
            hFile: null_mut(),
            pgKnownSubject: null_mut(),
        };
        // SAFETY: zero is a valid WINTRUST_DATA before the fields below are set.
        let mut data: WINTRUST_DATA = unsafe { std::mem::zeroed() };
        data.cbStruct = size_of::<WINTRUST_DATA>() as u32;
        data.dwUIChoice = WTD_UI_NONE;
        data.fdwRevocationChecks = WTD_REVOKE_NONE;
        data.dwUnionChoice = WTD_CHOICE_FILE;
        data.Anonymous = WINTRUST_DATA_0 { pFile: &mut info };
        data.dwStateAction = WTD_STATEACTION_VERIFY;
        data.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;
        let mut action = WINTRUST_ACTION_GENERIC_VERIFY_V2;

        // SAFETY: `data` and `info` (and the path they point to) outlive both calls; the state is closed below.
        let result = unsafe { WinVerifyTrust(-1isize as _, &mut action, &mut data as *mut _ as *mut _) };
        let verified = match result {
            0 => Verified::Trusted(signer(&data).unwrap_or_default()),
            TRUST_E_NOSIGNATURE | TRUST_E_SUBJECT_FORM_UNKNOWN => Verified::Unsigned,
            TRUST_E_BAD_DIGEST | TRUST_E_CERT_SIGNATURE | TRUST_E_NO_SIGNER_CERT | CRYPT_E_SECURITY_SETTINGS => Verified::BadHash,
            CERT_E_UNTRUSTEDROOT => Verified::Untrusted(signer(&data)),
            _ => Verified::Untrusted(None),
        };
        data.dwStateAction = WTD_STATEACTION_CLOSE;
        // SAFETY: closes the state the call above opened.
        unsafe { WinVerifyTrust(-1isize as _, &mut action, &mut data as *mut _ as *mut _) };
        verified
    }

    /// The signing certificate's simple name (its CN), from the state a verify left open.
    fn signer(data: &WINTRUST_DATA) -> Option<String> {
        // SAFETY: the state is open (closed only after this returns); each pointer is checked before it's followed.
        unsafe {
            let provider = WTHelperProvDataFromStateData(data.hWVTStateData);
            if provider.is_null() {
                return None;
            }
            let signer = WTHelperGetProvSignerFromChain(provider, 0, 0, 0);
            if signer.is_null() || (*signer).csCertChain == 0 || (*signer).pasCertChain.is_null() {
                return None;
            }
            let cert = (*(*signer).pasCertChain).pCert;
            if cert.is_null() {
                return None;
            }
            let mut name = [0u16; 512];
            let length = CertGetNameStringW(cert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, null_mut(), name.as_mut_ptr(), name.len() as u32);
            (length > 1).then(|| String::from_utf16_lossy(&name[..length as usize - 1]))
        }
    }
}

#[cfg(not(windows))]
mod windows {
    pub(super) fn verify(_: &std::path::Path) -> super::Verified {
        super::Verified::Unsigned
    }
}
