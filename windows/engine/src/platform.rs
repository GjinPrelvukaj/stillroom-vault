//! Windows' own protections for the app's process and the vault's folder (windows/PORT.md, "Security parity plan").
//!
//! **Process hardening.** The Mac app runs with the hardened runtime and library validation. A .NET app can't take
//! Windows' strictest equivalents: "Microsoft-signed DLLs only" would refuse the app's own code, and "no dynamic code"
//! would stop .NET's JIT. What it can take, and what's here:
//! - **No extension DLLs** (`ProcessExtensionPointDisablePolicy`): Windows won't load the DLLs it injects into other
//!   processes for keyboard and message hooks (`SetWindowsHookEx`), AppInit_DLLs or Winsock layered providers, so a
//!   keylogger that works by injecting itself can't. It also turns off input method editors (IMEs), which people
//!   typing Chinese, Japanese or Korean need, so it's a setting: on unless someone needs an IME.
//! - **No images from the network or from low-integrity files**, and system DLLs preferred over same-named ones beside
//!   the app (`ProcessImageLoadPolicy`), against DLL planting.
//! - **Invalid handles are fatal** (`ProcessStrictHandleCheckPolicy`), so a handle bug can't be turned into using
//!   someone else's handle.
//!
//! These can't be undone for the process's lifetime: call `harden_process` once, early.
//!
//! **The vault's folder** is readable by the current account only (the Mac's 0700): its permissions are replaced by one
//! entry giving the account full control, inherited by everything inside, and none inherited from above.

use std::path::Path;

/// What `harden_process` turned on.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Hardened {
    pub extension_dlls_blocked: bool,
    pub image_loads_restricted: bool,
    pub strict_handles: bool,
}

/// Turns on the process protections above. `block_extension_dlls` is the setting: false for someone who types with an
/// IME. Each protection is tried on its own; what Windows refused is false in the result.
pub fn harden_process(block_extension_dlls: bool) -> Hardened {
    windows::harden_process(block_extension_dlls)
}

/// The vault folder made readable by this account only. Made first if it isn't there.
pub fn protect_folder(folder: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(folder)?;
    windows::protect_folder(folder)
}

#[cfg(windows)]
mod windows {
    use std::ffi::c_void;
    use std::os::windows::ffi::OsStrExt;
    use std::path::Path;

    use windows_sys::Win32::Foundation::{CloseHandle, LocalFree, ERROR_SUCCESS, HANDLE};
    use windows_sys::Win32::Security::Authorization::{
        SetEntriesInAclW, SetNamedSecurityInfoW, EXPLICIT_ACCESS_W, NO_MULTIPLE_TRUSTEE, SET_ACCESS, SE_FILE_OBJECT,
        TRUSTEE_IS_SID, TRUSTEE_IS_USER, TRUSTEE_W,
    };
    use windows_sys::Win32::Security::{
        GetTokenInformation, TokenUser, ACL, DACL_SECURITY_INFORMATION, PROTECTED_DACL_SECURITY_INFORMATION,
        SUB_CONTAINERS_AND_OBJECTS_INHERIT, TOKEN_QUERY, TOKEN_USER,
    };
    use windows_sys::Win32::System::Threading::{
        GetCurrentProcess, OpenProcessToken, ProcessExtensionPointDisablePolicy, ProcessImageLoadPolicy,
        ProcessStrictHandleCheckPolicy, SetProcessMitigationPolicy,
    };

    use super::Hardened;

    /// Full control of a file or folder, said specifically (GENERIC_ALL would be stored as two entries).
    const FILE_ALL_ACCESS: u32 = 0x001F_01FF;

    fn set_policy(policy: i32, flags: u32) -> bool {
        // SAFETY: each of these policies is a 4-byte flags word, passed with its size.
        unsafe { SetProcessMitigationPolicy(policy, (&flags as *const u32).cast(), 4) != 0 }
    }

    pub fn harden_process(block_extension_dlls: bool) -> Hardened {
        Hardened {
            // DisableExtensionPoints.
            extension_dlls_blocked: block_extension_dlls && set_policy(ProcessExtensionPointDisablePolicy, 0b1),
            // NoRemoteImages | NoLowMandatoryLabelImages | PreferSystem32Images.
            image_loads_restricted: set_policy(ProcessImageLoadPolicy, 0b111),
            // RaiseExceptionOnInvalidHandleReference | HandleExceptionsPermanentlyEnabled.
            strict_handles: set_policy(ProcessStrictHandleCheckPolicy, 0b11),
        }
    }

    /// The current account's SID, in a buffer that holds it.
    fn current_user() -> std::io::Result<Vec<u8>> {
        // SAFETY: the token is closed below; the buffer is sized by Windows' own first answer.
        unsafe {
            let mut token: HANDLE = std::ptr::null_mut();
            if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) == 0 {
                return Err(std::io::Error::last_os_error());
            }
            let mut needed = 0u32;
            GetTokenInformation(token, TokenUser, std::ptr::null_mut(), 0, &mut needed);
            let mut buffer = vec![0u8; needed as usize];
            let ok = GetTokenInformation(token, TokenUser, buffer.as_mut_ptr().cast(), needed, &mut needed);
            CloseHandle(token);
            if ok == 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(buffer)
        }
    }

    pub fn protect_folder(folder: &Path) -> std::io::Result<()> {
        let user = current_user()?;
        // SAFETY: `user` holds a TOKEN_USER whose SID points inside the same buffer, which outlives these calls; the
        // ACL Windows allocates is freed with LocalFree.
        unsafe {
            let sid = (*(user.as_ptr() as *const TOKEN_USER)).User.Sid;
            let access = EXPLICIT_ACCESS_W {
                grfAccessPermissions: FILE_ALL_ACCESS,
                grfAccessMode: SET_ACCESS,
                grfInheritance: SUB_CONTAINERS_AND_OBJECTS_INHERIT,
                Trustee: TRUSTEE_W {
                    pMultipleTrustee: std::ptr::null_mut(),
                    MultipleTrusteeOperation: NO_MULTIPLE_TRUSTEE,
                    TrusteeForm: TRUSTEE_IS_SID,
                    TrusteeType: TRUSTEE_IS_USER,
                    ptstrName: sid as *mut u16,
                },
            };
            let mut acl: *mut ACL = std::ptr::null_mut();
            let made = SetEntriesInAclW(1, &access, std::ptr::null(), &mut acl);
            if made != ERROR_SUCCESS {
                return Err(std::io::Error::from_raw_os_error(made as i32));
            }
            let mut path: Vec<u16> = folder.as_os_str().encode_wide().collect();
            path.push(0);
            let set = SetNamedSecurityInfoW(
                path.as_ptr(),
                SE_FILE_OBJECT,
                DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                acl,
                std::ptr::null(),
            );
            LocalFree(acl as *mut c_void);
            if set != ERROR_SUCCESS {
                return Err(std::io::Error::from_raw_os_error(set as i32));
            }
            Ok(())
        }
    }
}

#[cfg(not(windows))]
mod windows {
    use super::Hardened;

    pub fn harden_process(_block_extension_dlls: bool) -> Hardened {
        Hardened::default()
    }

    pub fn protect_folder(_folder: &std::path::Path) -> std::io::Result<()> {
        Ok(())
    }
}
