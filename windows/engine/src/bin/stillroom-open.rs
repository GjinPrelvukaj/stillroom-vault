//! stillroom-open: take everything out of a Stillroom vault, without the Stillroom app. The Windows build of
//! tools/stillroom-open.py, on the engine the Windows app uses.
//!
//!     stillroom-open STORE_FOLDER OUT_FOLDER              asks for the password
//!     stillroom-open STORE_FOLDER OUT_FOLDER --recovery   asks for the recovery key
//!     stillroom-open STORE_FOLDER OUT_FOLDER --kit        asks for kit pieces
//!
//! Everything comes out unencrypted into OUT_FOLDER. The format is described in docs/FORMAT.md.

use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use stillroom_core::export::take_out;
use stillroom_core::kit;
use stillroom_core::vault::Store;
use zeroize::Zeroizing;

const USAGE: &str = "\
Takes everything out of a Stillroom vault, unencrypted.

    stillroom-open STORE_FOLDER OUT_FOLDER              asks for the password
    stillroom-open STORE_FOLDER OUT_FOLDER --recovery   asks for the recovery key
    stillroom-open STORE_FOLDER OUT_FOLDER --kit        asks for kit pieces";

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("{message}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let paths: Vec<&String> = args.iter().filter(|a| !a.starts_with("--")).collect();
    let flag = |name: &str| args.iter().any(|a| a == name);
    let [root, out] = paths.as_slice() else { return Err(USAGE.into()) };
    // Read only: taking a vault out leaves it exactly as it was, nothing tidied or rewritten.
    let (store, out) = (Store::at(root.as_str()).read_only(), PathBuf::from(out.as_str()));
    if !store.exists() {
        return Err(format!("No vault in {root}: it should hold a\\ and b\\, each with password.key."));
    }

    let open = if flag("--recovery") {
        let typed = Zeroizing::new(ask_hidden("Recovery key: ")?);
        store.unlock_with_recovery_key(&typed).map_err(cant_open)?
    } else if flag("--kit") {
        let mut pieces = vec![ask("Piece 1: ")?];
        let first = kit::piece(&pieces[0]).map_err(cant_open)?;
        while pieces.len() < usize::from(first.threshold) {
            pieces.push(ask(&format!("Piece {}: ", pieces.len() + 1))?);
        }
        let typed: Vec<&str> = pieces.iter().map(|p| p.as_str()).collect();
        store.unlock_with_kit(&typed).map_err(cant_open)?
    } else {
        if store.is_locked_to_a_mac() {
            return Err("This vault is locked to the Mac that made it, so its password only works there.\n\
                        Use --recovery or --kit instead."
                .into());
        }
        let password = Zeroizing::new(ask_hidden("Password: ")?);
        store.unlock_with_password(&password).map_err(cant_open)?
    };

    let report = take_out(&open, &out, |p| match p.result {
        Ok(()) => println!("  {}/{}  {}", p.number, p.of, p.path.display()),
        Err(why) => println!("  {}/{}  NOT TAKEN OUT: {} ({why})", p.number, p.of, p.path.display()),
    })
    .map_err(|e| format!("Couldn't write to {}: {e}", out.display()))?;
    if !report.failed.is_empty() {
        let names: Vec<String> = report.failed.iter().map(|(path, _)| path.display().to_string()).collect();
        println!("{} not taken out: {}", report.failed.len(), names.join(", "));
    }
    println!("Done: {} items, unencrypted, in {}", report.taken, out.display());
    Ok(())
}

fn cant_open(error: impl std::fmt::Display) -> String {
    format!("Can't open it: {error}")
}

fn ask_hidden(prompt: &str) -> Result<String, String> {
    rpassword::prompt_password(prompt).map_err(|e| format!("Couldn't read it: {e}"))
}

/// A line as typed, trimmed. Both the line and the trimmed copy are wiped when dropped (a kit piece is a secret).
fn ask(prompt: &str) -> Result<Zeroizing<String>, String> {
    print!("{prompt}");
    io::stdout().flush().ok();
    let mut line = Zeroizing::new(String::with_capacity(256));
    io::stdin().lock().read_line(&mut line).map_err(|e| format!("Couldn't read it: {e}"))?;
    Ok(Zeroizing::new(line.trim().to_owned()))
}
