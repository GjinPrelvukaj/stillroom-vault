//! Searching inside things (`Storage/SearchIndex.swift`): the words in notes, secrets (labels and visible fields, never
//! concealed ones or two-factor setups), text files and emails, kept in a sealed index per slot so the next unlock
//! needn't read everything again. PDFs and pictures are read by the platform (`extra`), as the Mac reads them with
//! PDFKit and its own text recognition.
//!
//! On disk the index is `[UUID: Entry]` as Swift's JSONEncoder writes a dictionary with UUID keys: a flat array,
//! `["UUID", {"changed", "size", "text"}, "UUID", {…}, …]`, sealed with the slot key (binding "Vault search 3"),
//! padded with spaces, inside the slot's search cover.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

use crate::crypto::{bound, seal, unseal, Key};
use crate::kinds;
use crate::list::{Entry as Kind, Item, Secret};
use crate::otp;
use crate::vault::{Covered, Slot, Store};
use crate::VaultError;

/// What an item said when it was last read.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    /// When the item was last changed when read (seconds since 2001), so a changed item is read again.
    pub changed: f64,
    pub size: u64,
    pub text: String,
}

pub type Index = HashMap<Uuid, Entry>;

/// What the platform reads that the engine can't: the text of a PDF, or in a picture.
pub type Extra<'a> = &'a dyn Fn(&Item, &[u8]) -> Option<String>;

/// The biggest item read for search: past this it's skipped.
pub const LARGEST: u64 = 50 << 20;
/// The most text kept per item, in characters.
pub const LONGEST: usize = 200_000;

pub fn load(store: &Store, key: &Key, slot: Slot, cover: &Key) -> Index {
    let Some(sealed) = store.read_covered(Covered::Search, slot, cover) else { return Index::new() };
    let Ok(json) = unseal(&sealed, key, Some(bound::SEARCH)) else { return Index::new() };
    decode(&json).unwrap_or_default()
}

fn decode(json: &[u8]) -> Option<Index> {
    let Value::Array(flat) = serde_json::from_slice(json).ok()? else { return None };
    if flat.len() % 2 != 0 {
        return None;
    }
    flat.chunks(2)
        .map(|pair| Some((pair[0].as_str()?.parse().ok()?, serde_json::from_value(pair[1].clone()).ok()?)))
        .collect()
}

/// The index as JSON, in the Mac's flat-array form.
pub fn encode(index: &Index) -> Vec<u8> {
    let mut flat = Vec::with_capacity(index.len() * 2);
    for (id, entry) in index {
        flat.push(Value::String(id.hyphenated().encode_upper(&mut Uuid::encode_buffer()).to_owned()));
        flat.push(serde_json::to_value(entry).expect("an entry is plain data"));
    }
    serde_json::to_vec(&flat).expect("plain data")
}

/// The index sealed with the slot key, padded the way lists are.
pub fn sealed(index: &Index, key: &Key) -> Result<Vec<u8>, VaultError> {
    let mut json = encode(index);
    json.resize(crate::crypto::padded_size(json.len())?, b' ');
    seal(&json, key, Some(bound::SEARCH))
}

/// Whether an item is worth reading for words.
pub fn reads(item: &Item) -> bool {
    if item.size > LARGEST || item.is_chunked() {
        return false;
    }
    item.entry.is_some()
        || kinds::is_email(&item.uti, &item.name)
        || kinds::is_text(&item.uti)
        || kinds::is_pdf(&item.uti)
        || kinds::is_image(&item.uti)
}

/// The words in an item's contents, or None when there are none to find. `extra` reads what only the platform can
/// (PDFs, the text in pictures).
pub fn words(item: &Item, data: &[u8], extra: Option<Extra>) -> Option<String> {
    let text = match item.entry {
        Some(Kind::Note) => String::from_utf8(data.to_vec()).ok(),
        Some(Kind::Secret) => serde_json::from_slice::<Secret>(data).ok().map(|secret| {
            secret
                .fields
                .iter()
                .map(|f| {
                    // Concealed values and two-factor setups stay out of the index: a search box mustn't become a way to
                    // read them.
                    if f.concealed || otp::in_field(&f.label, &f.value).is_some() {
                        f.label.clone()
                    } else {
                        format!("{} {}", f.label, f.value)
                    }
                })
                .collect::<Vec<_>>()
                .join("\n")
        }),
        None if kinds::is_email(&item.uti, &item.name) => {
            crate::email::parse(data).map(|e| e.words()).or_else(|| String::from_utf8(data.to_vec()).ok())
        }
        None if kinds::is_pdf(&item.uti) || kinds::is_image(&item.uti) => extra.and_then(|read| read(item, data)),
        None => String::from_utf8(data.to_vec()).ok(),
    }?;
    if text.is_empty() {
        return None;
    }
    Some(text.chars().take(LONGEST).collect())
}

/// Case-insensitive: whether `query` is in `text`, and where (in characters).
fn find(text: &[char], query: &[char]) -> Option<usize> {
    let fold = |c: &char| c.to_lowercase().collect::<String>();
    let query: Vec<String> = query.iter().map(fold).collect();
    if query.is_empty() {
        return None;
    }
    (0..=text.len().checked_sub(query.len())?).find(|&i| text[i..i + query.len()].iter().map(fold).eq(query.iter().cloned()))
}

pub fn contains(text: &str, query: &str) -> bool {
    find(&text.chars().collect::<Vec<_>>(), &query.chars().collect::<Vec<_>>()).is_some()
}

/// A short piece of `text` around the first place `query` appears, for a search result's row.
pub fn snippet(text: &str, query: &str) -> Option<String> {
    let chars: Vec<char> = text.chars().collect();
    let query: Vec<char> = query.chars().collect();
    let hit = find(&chars, &query)?;
    let start = hit.saturating_sub(30);
    let end = (hit + query.len() + 50).min(chars.len());
    let piece: String = chars[start..end].iter().map(|&c| if c == '\n' { ' ' } else { c }).collect();
    Some(format!("{}{}{}", if start > 0 { "…" } else { "" }, piece, if end < chars.len() { "…" } else { "" }))
}
