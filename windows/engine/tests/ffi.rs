//! The C interface (src/ffi.rs), called as the Windows app calls it: through handles, status codes and buffers only.

use std::ffi::{c_char, CStr, CString};
use std::ptr::{null, null_mut};

use serde_json::Value;
use stillroom_core::ffi::*;

/// What a call left in a string the engine gave, freed.
fn take(value: *mut c_char) -> String {
    assert!(!value.is_null());
    // SAFETY: the engine gave this string, and it's freed once, here.
    unsafe {
        let text = CStr::from_ptr(value).to_string_lossy().into_owned();
        stillroom_string_free(value);
        text
    }
}

fn take_json(value: *mut c_char) -> Value {
    serde_json::from_str(&take(value)).unwrap()
}

fn last_error() -> String {
    // SAFETY: valid until the next call on this thread.
    unsafe { CStr::from_ptr(stillroom_last_error()) }.to_string_lossy().into_owned()
}

fn c(text: &str) -> CString {
    CString::new(text).unwrap()
}

#[track_caller]
fn ok(status: StillroomStatus) {
    assert_eq!(status, STILLROOM_OK, "{}", last_error());
}

struct Opened {
    _dir: tempfile::TempDir,
    store: *mut StillroomStore,
    vault: *mut StillroomVault,
    recovery: String,
}

fn opened() -> Opened { unsafe {
    let dir = tempfile::tempdir().unwrap();
    let root = c(&dir.path().join("Store").to_string_lossy());
    let mut store = null_mut();
    ok(stillroom_store_open(root.as_ptr(), false, &mut store));
    ok(stillroom_store_lower_cost_for_tests(store));
    let (mut vault, mut recovery) = (null_mut(), null_mut());
    let password = b"real password 123";
    ok(stillroom_store_create(store, password.as_ptr(), password.len(), &mut vault, &mut recovery));
    Opened { _dir: dir, store, vault, recovery: take(recovery) }
}}

impl Drop for Opened {
    fn drop(&mut self) { unsafe {
        stillroom_vault_lock(self.vault);
        stillroom_store_free(self.store);
    }}
}

#[test]
fn a_vault_made_used_locked_and_opened_again_through_handles() { unsafe {
    let mut o = opened();
    assert_eq!(stillroom_abi_version(), STILLROOM_ABI_VERSION);
    assert_eq!(o.recovery.len(), 29);

    // A note in, read back.
    let (mut id, name) = (null_mut(), c("Plans"));
    ok(stillroom_vault_new_entry(o.vault, 0, name.as_ptr(), b"first".as_ptr(), 5, null(), &mut id));
    let id = c(&take(id));
    let mut contents = StillroomBytes { data: null_mut(), length: 0 };
    ok(stillroom_vault_read(o.vault, id.as_ptr(), null(), &mut contents));
    assert_eq!(std::slice::from_raw_parts(contents.data, contents.length), b"first");
    stillroom_bytes_free(contents);

    // What the window shows: the item, as JSON, without its key.
    let mut state = null_mut();
    ok(stillroom_vault_state(o.vault, &mut state));
    let state = take_json(state);
    assert_eq!(state["files"][0]["name"], "Plans");
    assert_eq!(state["files"][0]["entry"], "note");
    assert!(state["files"][0].get("key").is_none() && state["files"][0].get("sealedAs").is_some());
    assert_eq!(state["mustSetPassword"], false);

    // Locked (the handle freed), then opened again with the password.
    stillroom_vault_lock(o.vault);
    o.vault = null_mut();
    let password = b"real password 123";
    ok(stillroom_store_unlock_with_password(o.store, password.as_ptr(), password.len(), &mut o.vault));
    let mut state = null_mut();
    ok(stillroom_vault_state(o.vault, &mut state));
    assert_eq!(take_json(state)["files"].as_array().unwrap().len(), 1);
}}

#[test]
fn failures_come_back_as_codes_with_words() { unsafe {
    let o = opened();
    let mut vault = null_mut();
    let wrong = b"not the password";
    assert_eq!(stillroom_store_unlock_with_password(o.store, wrong.as_ptr(), wrong.len(), &mut vault), STILLROOM_WRONG_PASSWORD);
    assert_eq!(last_error(), "That password doesn't open this vault.");
    assert!(vault.is_null());

    let pieces = b"VK-0000\nVK-1111";
    assert_eq!(stillroom_store_unlock_with_kit(o.store, pieces.as_ptr(), pieces.len(), &mut vault), STILLROOM_KIT_MISTYPED);

    let missing = c(&uuid::Uuid::new_v4().to_string());
    assert_eq!(stillroom_vault_delete(o.vault, missing.as_ptr()), STILLROOM_NOT_FOUND);
    let not_an_id = c("nope");
    assert_eq!(stillroom_vault_delete(o.vault, not_an_id.as_ptr()), STILLROOM_INVALID_ARGUMENT);
    assert_eq!(last_error(), "That isn't an item's id.");
    // Nothing given where something must be: refused, not a crash.
    assert_eq!(stillroom_vault_delete(null(), not_an_id.as_ptr()), STILLROOM_INVALID_ARGUMENT);
    assert_eq!(stillroom_vault_delete(o.vault, null()), STILLROOM_INVALID_ARGUMENT);
    assert_eq!(stillroom_vault_state(o.vault, null_mut()), STILLROOM_INVALID_ARGUMENT);
    let bad_json = c("[not json");
    assert_eq!(stillroom_vault_move_items(o.vault, bad_json.as_ptr(), null()), STILLROOM_INVALID_ARGUMENT);
    // A password that isn't UTF-8.
    let mut other = null_mut();
    assert_eq!(stillroom_vault_set_other_slot(o.vault, [0xFFu8, 0xFE].as_ptr(), 2, &mut other), STILLROOM_INVALID_ARGUMENT);
    // Freeing nothing is fine.
    stillroom_string_free(null_mut());
    stillroom_bytes_free(StillroomBytes { data: null_mut(), length: 0 });
    stillroom_vault_lock(null_mut());
    stillroom_store_free(null_mut());
    stillroom_reader_free(null_mut());
}}

#[test]
fn the_recovery_key_the_decoy_and_the_kit() { unsafe {
    let mut o = opened();
    let (mut decoy_code, decoy) = (null_mut(), b"decoy password 456");
    ok(stillroom_vault_set_other_slot(o.vault, decoy.as_ptr(), decoy.len(), &mut decoy_code));
    assert_eq!(take(decoy_code).len(), 29);
    let mut pieces = null_mut();
    ok(stillroom_vault_make_kit(o.vault, 2, 3, &mut pieces));
    let pieces: Vec<String> = serde_json::from_value(take_json(pieces)).unwrap();
    stillroom_vault_lock(o.vault);

    let typed = format!("{}\n{}", pieces[2].to_lowercase(), pieces[0]);
    ok(stillroom_store_unlock_with_kit(o.store, typed.as_ptr(), typed.len(), &mut o.vault));
    let mut state = null_mut();
    ok(stillroom_vault_state(o.vault, &mut state));
    assert_eq!(take_json(state)["mustSetPassword"], true);
    let new = b"a brand new password";
    ok(stillroom_vault_set_password_after_recovery(o.vault, new.as_ptr(), new.len()));
    stillroom_vault_lock(o.vault);

    let code = o.recovery.clone();
    ok(stillroom_store_unlock_with_recovery_key(o.store, code.as_ptr(), code.len(), &mut o.vault));
    stillroom_vault_lock(o.vault);
    ok(stillroom_store_unlock_with_password(o.store, new.as_ptr(), new.len(), &mut o.vault));
}}

#[test]
fn files_added_by_path_searched_and_played_in_ranges() { unsafe {
    let o = opened();
    let folder = o._dir.path().join("in");
    std::fs::create_dir_all(&folder).unwrap();
    let clip: Vec<u8> = (0..(3u32 << 20) + 5).map(|i| (i * 7) as u8).collect();
    std::fs::write(folder.join("clip.mp3"), &clip).unwrap();
    std::fs::write(folder.join("notes.txt"), b"the treasure is under the oak").unwrap();
    let paths = c(&serde_json::to_string(&[folder.join("clip.mp3"), folder.join("notes.txt")]).unwrap());
    let mut added = null_mut();
    ok(stillroom_vault_add(o.vault, paths.as_ptr(), null(), &mut added));
    let added = take_json(added);
    assert_eq!(added["items"].as_array().unwrap().len(), 2);
    assert_eq!(added["originals"]["files"].as_array().unwrap().len(), 2);
    let clip_id = c(added["items"][0].as_str().unwrap());

    // Played from the sealed file a range at a time.
    let (mut reader, mut size) = (null_mut(), 0u64);
    ok(stillroom_vault_open_reader(o.vault, clip_id.as_ptr(), &mut reader, &mut size));
    assert_eq!(size, clip.len() as u64);
    let mut buffer = vec![0u8; 100_000];
    let mut read = 0usize;
    ok(stillroom_reader_read(reader, (1 << 20) - 10, buffer.as_mut_ptr(), buffer.len(), &mut read));
    assert_eq!(&buffer[..read], &clip[(1 << 20) - 10..(1 << 20) - 10 + 100_000]);
    ok(stillroom_reader_read(reader, size - 3, buffer.as_mut_ptr(), buffer.len(), &mut read));
    assert_eq!(read, 3);
    stillroom_reader_free(reader);

    // Searched, with a snippet.
    let mut changed = false;
    ok(stillroom_vault_refresh_search(o.vault, None, null_mut(), &mut changed));
    assert!(changed);
    let (query, mut found) = (c("TREASURE"), null_mut());
    ok(stillroom_vault_search(o.vault, query.as_ptr(), &mut found));
    let found = take_json(found);
    assert_eq!(found.as_array().unwrap().len(), 1);
    let (notes, mut snippet) = (c(found[0].as_str().unwrap()), null_mut());
    ok(stillroom_vault_snippet(o.vault, notes.as_ptr(), query.as_ptr(), &mut snippet));
    assert!(take(snippet).contains("treasure is under"));

    // The originals deleted, now their copies have checked out.
    let originals = c(&added["originals"].to_string());
    let mut kept = null_mut();
    ok(stillroom_delete_originals(originals.as_ptr(), &mut kept));
    assert_eq!(take_json(kept), serde_json::json!([]));
    assert!(!folder.join("notes.txt").exists());
}}

/// The app reads PDFs and pictures for search through a callback.
#[test]
fn search_reads_pictures_through_the_apps_callback() { unsafe {
    extern "C" fn read_text(context: *mut std::ffi::c_void, item: *const c_char, _data: *const u8, _length: usize) -> *const c_char {
        let item = unsafe { CStr::from_ptr(item) }.to_string_lossy();
        assert!(item.contains("public.png"));
        let calls = unsafe { &mut *(context as *mut u32) };
        *calls += 1;
        c"a receipt for the oak table".as_ptr()
    }
    let o = opened();
    let (name, mut id) = (c("receipt.png"), null_mut());
    ok(stillroom_vault_add_data(o.vault, [0x89, b'P', b'N', b'G'].as_ptr(), 4, name.as_ptr(), null(), &mut id));
    stillroom_string_free(id);
    let (mut calls, mut changed) = (0u32, false);
    ok(stillroom_vault_refresh_search(o.vault, Some(read_text), (&mut calls as *mut u32).cast(), &mut changed));
    assert_eq!(calls, 1);
    let (query, mut found) = (c("oak table"), null_mut());
    ok(stillroom_vault_search(o.vault, query.as_ptr(), &mut found));
    assert_eq!(take_json(found).as_array().unwrap().len(), 1);
}}

#[test]
fn backup_restore_and_wipe_free_the_vault_handle() { unsafe {
    let mut o = opened();
    let file = c(&o._dir.path().join("b.stillroombackup").to_string_lossy());
    ok(stillroom_vault_backup(o.vault, file.as_ptr()));
    ok(stillroom_backup_check(file.as_ptr()));
    let mut aside = null_mut();
    ok(stillroom_vault_restore_backup(o.vault, file.as_ptr(), &mut aside));
    assert!(take(aside).contains("Store-before-restore-"));
    let password = b"real password 123";
    ok(stillroom_store_unlock_with_password(o.store, password.as_ptr(), password.len(), &mut o.vault));
    ok(stillroom_vault_wipe(o.vault));
    o.vault = null_mut();
    let mut exists = true;
    ok(stillroom_store_exists(o.store, &mut exists));
    assert!(!exists);
}}

#[test]
fn the_helpers_that_need_no_vault() { unsafe {
    let (mut bits, mut enough) = (0.0, false);
    let password = b"correct horse battery staple";
    ok(stillroom_password_strength(password.as_ptr(), password.len(), &mut bits, &mut enough));
    assert!(enough && bits >= 50.0);

    let (label, key) = (c("Two-factor setup"), b"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
    let (mut code, mut left) = (null_mut(), 0u64);
    ok(stillroom_one_time_code(label.as_ptr(), key.as_ptr(), key.len(), 59.0, &mut code, &mut left));
    assert_eq!((take(code), left), ("287082".to_string(), 1));
    let password_label = c("Password");
    ok(stillroom_one_time_code(password_label.as_ptr(), key.as_ptr(), key.len(), 59.0, &mut code, &mut left));
    assert!(code.is_null());

    let (name, mut uti) = (c("w2.pdf"), null_mut());
    ok(stillroom_uti_for_name(name.as_ptr(), &mut uti));
    assert_eq!(take(uti), "com.adobe.pdf");
    let (html, page, mut can) = (c("public.html"), c("page.html"), true);
    ok(stillroom_can_edit(html.as_ptr(), page.as_ptr(), true, &mut can));
    assert!(!can);

    let mail = b"From: a@example.com\r\nSubject: Hi\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nContent-Type: text/plain\r\n\r\nBody\r\n--b\r\nContent-Type: application/pdf; name=\"x.pdf\"\r\n\r\n%PDF\r\n--b--\r\n";
    let mut read = null_mut();
    ok(stillroom_email_read(mail.as_ptr(), mail.len(), &mut read));
    let read = take_json(read);
    assert_eq!((read["subject"].as_str(), read["attachments"][0]["name"].as_str()), (Some("Hi"), Some("x.pdf")));
    let mut attachment = StillroomBytes { data: null_mut(), length: 0 };
    ok(stillroom_email_attachment(mail.as_ptr(), mail.len(), 0, &mut attachment));
    assert_eq!(std::slice::from_raw_parts(attachment.data, attachment.length), b"%PDF");
    stillroom_bytes_free(attachment);
    let mut none = null_mut();
    ok(stillroom_email_read([0u8, 0xFF].as_ptr(), 2, &mut none));
    assert!(none.is_null());

    assert!(stillroom_keys_are_locked());
}}

/// Two threads on one vault handle: their calls take turns, and every change lands.
#[test]
fn a_vault_handle_is_safe_from_several_threads() { unsafe {
    let o = opened();
    let vault = o.vault as usize;
    let threads: Vec<_> = (0..4)
        .map(|t| {
            std::thread::spawn(move || {
                for n in 0..5 {
                    let (name, mut id) = (c(&format!("note {t}-{n}")), null_mut());
                    ok(stillroom_vault_new_entry(vault as *mut StillroomVault, 0, name.as_ptr(), b"x".as_ptr(), 1, null(), &mut id));
                    stillroom_string_free(id);
                }
            })
        })
        .collect();
    for thread in threads {
        thread.join().unwrap();
    }
    let mut state = null_mut();
    ok(stillroom_vault_state(o.vault, &mut state));
    assert_eq!(take_json(state)["files"].as_array().unwrap().len(), 20);
}}
