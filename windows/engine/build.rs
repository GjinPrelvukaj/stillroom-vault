//! Builds the Argon2 reference C from `macos/Sources/CArgon2`, unchanged and shared with the Mac app. It's optimized even
//! in debug builds, where an unoptimized stretch takes many seconds per unlock (the same choice as Package.swift).

use std::path::PathBuf;

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../macos/Sources/CArgon2");
    let files = ["argon2.c", "core.c", "encoding.c", "ref.c", "thread.c", "blake2/blake2b.c"];

    let mut build = cc::Build::new();
    build.include(root.join("include")).include(&root).opt_level(3).warnings(false);
    for file in files {
        build.file(root.join(file));
    }
    build.compile("argon2");

    println!("cargo:rerun-if-changed={}", root.display());
}
