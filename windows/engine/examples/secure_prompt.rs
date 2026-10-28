//! The prompt for secrets, for real: the screen switches to a desktop of its own, you type, and it switches back.
//! Shows how many characters came back, never the text. Escape or Cancel gives nothing; after two minutes it gives up.
//!
//!     cargo run --example secure_prompt
//!     cargo run --example secure_prompt -- --kit      (several lines, as for kit pieces)

use stillroom_core::desktop::{ask, Prompt};

fn main() {
    let kit = std::env::args().any(|a| a == "--kit");
    let prompt = if kit {
        Prompt { title: "Stillroom", message: "Your emergency kit pieces, one per line", multiline: true }
    } else {
        Prompt { title: "Stillroom", message: "Password for your vault", multiline: false }
    };
    match ask(&prompt) {
        Ok(Some(typed)) => println!("typed {} characters on the secure desktop", typed.chars().count()),
        Ok(None) => println!("cancelled"),
        Err(error) => println!("couldn't ask: {error}"),
    }
}
