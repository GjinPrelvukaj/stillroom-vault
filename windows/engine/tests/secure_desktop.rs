//! The prompt for secrets on a desktop of its own, made for real but without switching the screen to it (a test
//! mustn't take the screen): the test types into it, and checks it was on the other desktop and gives back exactly what
//! was typed. `cargo run --example secure_prompt` shows the real thing, screen switch and all.

#![cfg(windows)]

use stillroom_core::desktop::{ask_unseen_for_tests, Prompt};

const PASSWORD: Prompt = Prompt { title: "Stillroom", message: "Password for your vault", multiline: false };

#[test]
fn what_is_typed_comes_back_from_a_desktop_of_its_own() {
    let (typed, on_own_desktop) = ask_unseen_for_tests(&PASSWORD, Some("pässwörd 🔐 with spaces")).unwrap();
    assert!(on_own_desktop, "the prompt was on its own desktop");
    assert_eq!(typed.as_deref().map(String::as_str), Some("pässwörd 🔐 with spaces"));
}

#[test]
fn cancel_gives_nothing() {
    let (typed, _) = ask_unseen_for_tests(&PASSWORD, None).unwrap();
    assert!(typed.is_none());
}

#[test]
fn kit_pieces_are_typed_a_piece_per_line() {
    let pieces = Prompt { title: "Stillroom", message: "Your emergency kit pieces, one per line", multiline: true };
    let (typed, _) = ask_unseen_for_tests(&pieces, Some("VK-0410-2Z2V\r\nVK-0410-4FV4")).unwrap();
    assert_eq!(typed.unwrap().lines().collect::<Vec<_>>(), ["VK-0410-2Z2V", "VK-0410-4FV4"]);
}

#[test]
fn prompts_one_after_another_each_get_their_own_desktop() {
    for n in 0..3 {
        let (typed, on_own_desktop) = ask_unseen_for_tests(&PASSWORD, Some(&format!("try {n}"))).unwrap();
        assert!(on_own_desktop);
        assert_eq!(typed.unwrap().as_str(), format!("try {n}"));
    }
}
