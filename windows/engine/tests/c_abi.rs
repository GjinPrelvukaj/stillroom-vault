//! The C interface from C: tests/c/smoke.c built with the C compiler Cargo's own builds use (MSVC here) against
//! include/stillroom.h and the engine's DLL, then run. A header that drifted from the DLL fails to compile or link.

#![cfg(windows)]

use std::path::Path;
use std::process::Command;

#[test]
fn a_c_program_uses_the_engine_through_the_header() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    // The DLL and its import library, built as the app gets them (cargo test builds only the Rust library).
    let built = Command::new(env!("CARGO")).args(["build", "--lib", "--quiet"]).current_dir(root).status().unwrap();
    assert!(built.success());
    let debug = root.join("target").join("debug");

    let work = tempfile::tempdir().unwrap();
    let exe = work.path().join("smoke.exe");
    let compiler = cc::Build::new()
        .target("x86_64-pc-windows-msvc")
        .host("x86_64-pc-windows-msvc")
        .opt_level(0)
        .cargo_metadata(false)
        .get_compiler();
    let compiled = compiler
        .to_command()
        .args(["/nologo", "/W4", "/WX"])
        .arg(format!("/I{}", root.join("include").display()))
        .arg(root.join("tests").join("c").join("smoke.c"))
        .arg(debug.join("stillroom_core.dll.lib"))
        .arg(format!("/Fe{}", exe.display()))
        .arg(format!("/Fo{}\\", work.path().display()))
        .output()
        .unwrap();
    assert!(compiled.status.success(), "{}", String::from_utf8_lossy(&compiled.stdout));
    std::fs::copy(debug.join("stillroom_core.dll"), work.path().join("stillroom_core.dll")).unwrap();

    let ran = Command::new(&exe).arg(work.path().join("Store")).output().unwrap();
    let said = String::from_utf8_lossy(&ran.stdout);
    assert!(ran.status.success() && said.trim() == "ok", "{said}");
}
