//! How hard a password is to guess, roughly, in bits (`Security/PasswordStrength.swift`): what a guessing program that
//! knows the usual tricks (common words, 1234, qwerty, years, aaaa, p@ssw0rd) would need to try. Not exact; meant to
//! stop the guessable ones while letting long random passwords and a few random words through.

/// Enough that, at Argon2id's cost per guess, a big guessing rig would still need centuries.
pub const ENOUGH: f64 = 50.0;

/// Said under the field while it isn't enough.
pub const ADVICE: &str = "Too easy to guess. Skip common words, years and runs like 1234; a few random words work well.";

pub fn is_enough(password: &str) -> bool {
    bits(password) >= ENOUGH
}

pub fn bits(password: &str) -> f64 {
    let chars: Vec<char> = password.chars().collect();
    // Words are looked for in a plain copy: lowercase, look-alike digits and symbols turned back into letters.
    let plain: Vec<char> = chars
        .iter()
        .map(|c| {
            let lower = lower(*c);
            lookalike(lower).unwrap_or(lower)
        })
        .collect();
    let mut total = 0.0;
    let mut i = 0;
    while i < chars.len() {
        if let Some(word) = longest_word(&plain, i) {
            // A known word costs a guesser a pick from a short list, plus a little for capitals.
            total += 7.0 + if chars[i..i + word].iter().any(|c| c.is_uppercase()) { 1.0 } else { 0.0 };
            i += word;
        } else if let Some(run) = run(&chars, i) {
            total += 4.0;
            i += run;
        } else if year(&chars, i) {
            total += 6.0;
            i += 4;
        } else {
            total += pool(chars[i]).log2();
            i += 1;
        }
    }
    total
}

fn lower(c: char) -> char {
    let mut lowered = c.to_lowercase();
    match (lowered.next(), lowered.next()) {
        (Some(single), None) => single,
        _ => c,
    }
}

fn lookalike(c: char) -> Option<char> {
    Some(match c {
        '0' => 'o',
        '1' => 'i',
        '3' => 'e',
        '4' => 'a',
        '@' => 'a',
        '5' => 's',
        '$' => 's',
        '7' => 't',
        '!' => 'i',
        _ => return None,
    })
}

/// The words people put in passwords most, from the leaked-password lists everyone's guessers start with.
const WORDS: &[&str] = &[
    "password", "passwort", "qwerty", "letmein", "welcome", "admin", "login", "iloveyou", "love", "monkey", "dragon",
    "master", "shadow", "sunshine", "princess", "football", "baseball", "soccer", "basketball", "superman", "batman",
    "trustno", "hello", "freedom", "whatever", "secret", "vault", "test", "guest", "summer", "winter", "spring", "autumn",
    "michael", "jordan", "charlie", "jessica", "ashley", "daniel", "thomas", "hunter", "ranger", "buster", "tigger",
    "pepper", "ginger", "cookie", "chocolate", "flower", "money", "starwars", "pokemon", "minecraft", "computer",
    "internet", "apple", "google", "samsung", "iphone", "mother", "father", "family", "friend", "baby", "angel", "lucky",
    "happy", "killer", "blink", "matrix", "access", "pass", "word", "user", "root", "changeme", "default", "secure",
    "private", "mypassword", "abc", "qwertz", "azerty", "asdf", "zxcv", "kosovo", "prishtina",
];

fn longest_word(plain: &[char], i: usize) -> Option<usize> {
    let longest_known = WORDS.iter().map(|w| w.chars().count()).max().unwrap_or(0);
    let longest = longest_known.min(plain.len() - i);
    if longest < 3 {
        return None;
    }
    (3..=longest).rev().find(|&length| {
        let candidate: String = plain[i..i + length].iter().collect();
        WORDS.contains(&candidate.as_str())
    })
}

const ROWS: &[&str] = &["qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890", "qwertzuiop", "yxcvbnm", "azertyuiop"];

/// Three or more of the same character, or in a row: abcd, 4321, qwerty, asdf.
fn run(chars: &[char], i: usize) -> Option<usize> {
    let lower: Vec<char> = chars.iter().map(|c| lower(*c)).collect();
    // The same character over and over.
    let mut length = 1;
    while i + length < lower.len() && lower[i + length] == lower[i] {
        length += 1;
    }
    if length >= 3 {
        return Some(length);
    }
    // Up or down by one: abc, 987.
    for step in [1i32, -1] {
        length = 1;
        while i + length < lower.len()
            && lower[i + length - 1].is_ascii()
            && lower[i + length].is_ascii()
            && lower[i + length] as i32 - lower[i + length - 1] as i32 == step
        {
            length += 1;
        }
        if length >= 3 {
            return Some(length);
        }
    }
    // Along a keyboard row, either way.
    for row in ROWS {
        for line in [row.chars().collect::<Vec<_>>(), row.chars().rev().collect()] {
            let Some(start) = line.iter().position(|&c| c == lower[i]) else { continue };
            length = 0;
            while i + length < lower.len() && start + length < line.len() && lower[i + length] == line[start + length] {
                length += 1;
            }
            if length >= 3 {
                return Some(length);
            }
        }
    }
    None
}

/// A year from 1900 to 2099: birthdays and anniversaries.
fn year(chars: &[char], i: usize) -> bool {
    i + 4 <= chars.len()
        && chars[i..i + 4].iter().all(|c| c.is_ascii_digit())
        && chars[i..i + 4].iter().collect::<String>().parse::<u32>().is_ok_and(|n| (1900..=2099).contains(&n))
}

/// How many characters of this kind there are to pick from.
fn pool(c: char) -> f64 {
    if c.is_lowercase() || c.is_uppercase() {
        26.0
    } else if c.is_numeric() {
        10.0
    } else if c.is_ascii() {
        33.0
    } else {
        100.0
    }
}
