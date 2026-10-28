//! include/stillroom.h is generated from src/ffi.rs, and must say what the code does: this fails when they've drifted.
//! To write it again: `STILLROOM_WRITE_HEADER=1 cargo test --test header`.

use std::path::Path;

fn generated() -> String {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let config = cbindgen::Config {
        language: cbindgen::Language::C,
        include_guard: Some("STILLROOM_H".into()),
        header: Some(
            "/* Stillroom's vault engine for Windows: the C interface. Generated from src/ffi.rs by tests/header.rs;\n   \
             don't edit by hand. Every call returns a StillroomStatus (0: done); stillroom_last_error() says why not. */"
                .into(),
        ),
        sys_includes: vec!["stdbool.h".into(), "stddef.h".into(), "stdint.h".into()],
        no_includes: true,
        documentation: true,
        cpp_compat: true,
        usize_is_size_t: true,
        ..Default::default()
    };
    let mut header = Vec::new();
    cbindgen::Builder::new()
        .with_config(config)
        .with_src(root.join("src").join("ffi.rs"))
        .generate()
        .expect("src/ffi.rs reads as a C interface")
        .write(&mut header);
    String::from_utf8(header).unwrap().replace("\r\n", "\n")
}

#[test]
fn the_header_says_what_the_code_does() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("include").join("stillroom.h");
    let header = generated();
    if std::env::var_os("STILLROOM_WRITE_HEADER").is_some() {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, &header).unwrap();
    }
    let committed = std::fs::read_to_string(&path).unwrap_or_default().replace("\r\n", "\n");
    assert!(committed == header, "include/stillroom.h is out of date: STILLROOM_WRITE_HEADER=1 cargo test --test header");
}
