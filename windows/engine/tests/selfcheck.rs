//! The tamper check (`selfcheck.rs`, the Mac's `SelfCheck`), on real signatures: a copy of a program of this crate
//! unsigned, signed by `windows/sign.ps1 -Test`'s throwaway certificate, changed after signing, and signed by someone
//! else; and .NET's own dotnet.exe, which Microsoft signed and this PC trusts. The Mac's test was the same three
//! copies against `codesign -v -R`. Skipped where the Windows SDK's signtool isn't installed.

#![cfg(windows)]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use stillroom_core::selfcheck::{self, check_against, Signed};

const TEST_NAME: &str = "Stillroom Test Signing";

fn signtool_installed() -> bool {
    let kits = PathBuf::from(std::env::var("ProgramFiles(x86)").unwrap_or_default()).join("Windows Kits\\10\\bin");
    fs::read_dir(kits)
        .map(|versions| versions.flatten().any(|v| v.path().join("x64\\signtool.exe").exists()))
        .unwrap_or(false)
}

fn sign_for_test(file: &Path) {
    let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("..\\sign.ps1");
    let done = Command::new("powershell")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(script)
        .args(["-Test", "-Files"])
        .arg(file)
        .output()
        .expect("powershell runs");
    assert!(done.status.success(), "sign.ps1 -Test failed: {}", String::from_utf8_lossy(&done.stderr));
}

#[test]
fn only_an_unchanged_copy_signed_by_the_publisher_passes() {
    if !signtool_installed() {
        eprintln!("skipped: no signtool (the Windows SDK)");
        return;
    }
    let dir = tempfile::tempdir().unwrap();
    let program = dir.path().join("stillroom-open.exe");
    fs::copy(env!("CARGO_BIN_EXE_stillroom-open"), &program).unwrap();

    assert_eq!(check_against(&program, TEST_NAME, true), Signed::NotSigned);

    sign_for_test(&program);
    assert_eq!(check_against(&program, TEST_NAME, true), Signed::ByUs);
    // A release never accepts a root this PC doesn't trust, so the test certificate is someone else's there.
    assert_eq!(check_against(&program, TEST_NAME, false), Signed::SomeoneElse);
    assert_eq!(check_against(&program, "Someone Else", true), Signed::SomeoneElse);

    // One byte changed in the code, after signing.
    let mut bytes = fs::read(&program).unwrap();
    let at = bytes.len() / 3;
    bytes[at] ^= 0x01;
    let changed = dir.path().join("changed.exe");
    fs::write(&changed, &bytes).unwrap();
    assert_eq!(check_against(&changed, TEST_NAME, true), Signed::Changed);

    // Changed, then signed again by someone else: what a crack has to do.
    let resigned = dir.path().join("resigned.exe");
    fs::write(&resigned, &bytes).unwrap();
    sign_for_test(&resigned);
    assert_eq!(check_against(&resigned, "Gjin Prelvukaj", true), Signed::SomeoneElse);
}

#[test]
fn a_file_microsoft_signed_checks_out_against_a_trusted_root() {
    let dotnet = PathBuf::from(std::env::var("ProgramFiles").unwrap_or_default()).join("dotnet\\dotnet.exe");
    if !dotnet.exists() {
        eprintln!("skipped: no dotnet.exe");
        return;
    }
    // Microsoft signs .NET with a certificate named ".NET" (O=Microsoft Corporation).
    assert_eq!(check_against(&dotnet, ".NET", false), Signed::ByUs);
    assert_eq!(check_against(&dotnet, TEST_NAME, false), Signed::SomeoneElse);
}

#[test]
fn without_a_certificate_there_is_nothing_to_check_against() {
    assert_eq!(selfcheck::PUBLISHER, None, "once there's a certificate, this test changes with it");
    if std::env::var_os("STILLROOM_SIGNER_TEST").is_none() {
        assert_eq!(selfcheck::check(Path::new(env!("CARGO_BIN_EXE_stillroom-open"))), Signed::NotSetUp);
    }
}
