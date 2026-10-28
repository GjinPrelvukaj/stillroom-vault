//! The sealed list: everything in a slot, as `Models/VaultFile.swift` writes it (docs/FORMAT.md, "The list of files").
//! Fields keep the Swift names on disk; values that are nil in Swift are left out, as Swift's encoder leaves them out;
//! ids are written in capitals, as Swift writes UUIDs. Dates are seconds since 1 January 2001, UTC.

use std::fmt;

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zeroize::Zeroize;

/// One slot's list. Every field is required when read, as the Swift decoder requires them.
#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultList {
    pub files: Vec<Item>,
    pub folders: Vec<String>,
    pub show_in_capture: bool,
    /// The slot's intruder private key, base64. Wiped when the list is dropped.
    pub intruder: String,
    /// The public key in the touchid.key this slot made, base64, or zeros.
    #[serde(rename = "touchID")]
    pub touch_id: String,
    /// When the kit was made and last reminded about: whole seconds since 2001, 12 digits, zeros for none.
    pub kit_made: String,
    pub kit_reminded: String,
    /// The SHA-256 of the Windows Hello credential in the hello.key this slot made, base64, or zeros (`hello.rs`).
    /// Windows' own field: a list the Mac wrote has none (read as zeros), and the Mac doesn't keep it yet when it saves.
    #[serde(default = "crate::hello::none")]
    pub hello: String,
}

pub const NEVER: &str = "000000000000";

impl VaultList {
    /// An empty list, as a new slot has: every field at the length it always has.
    pub fn new(intruder: String) -> VaultList {
        VaultList {
            files: Vec::new(),
            folders: Vec::new(),
            show_in_capture: false,
            intruder,
            touch_id: no_touch_id(),
            kit_made: NEVER.into(),
            kit_reminded: NEVER.into(),
            hello: crate::hello::none(),
        }
    }
}

/// 64 zero bytes, base64: no Touch ID.
pub fn no_touch_id() -> String {
    use base64::Engine as _;
    base64::engine::general_purpose::STANDARD.encode([0u8; 64])
}

/// A date as the kit fields keep it: whole seconds since 2001, 12 digits.
pub fn stamp(apple_seconds: f64) -> String {
    format!("{:012}", apple_seconds.max(0.0) as i64)
}

/// A kit field's date, or None for none.
pub fn stamped(text: &str) -> Option<f64> {
    if text == NEVER { None } else { text.parse::<i64>().ok().map(|s| s as f64) }
}

impl Drop for VaultList {
    fn drop(&mut self) {
        self.intruder.zeroize();
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Entry {
    Note,
    Secret,
}

/// A file, a note or a secret.
#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Item {
    #[serde(with = "upper")]
    pub id: Uuid,
    pub name: String,
    /// Its kind as the Mac names kinds (public.jpeg, com.adobe.pdf).
    pub uti: String,
    /// Bytes before sealing.
    pub size: u64,
    pub added_at: f64,
    /// The folder it sits in ("Taxes/2025"); None at the top.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub folder: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub modified_at: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    /// Set for a note or a secret; None for a file.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entry: Option<Entry>,
    /// Earlier contents, oldest first.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub versions: Option<Vec<Version>>,
    /// Sealed in chunks (big files, audio and video), rather than in one piece.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub chunked: Option<bool>,
    /// The id this sealing is tied to. It also names the blob in Files/.
    #[serde(with = "upper_option", default, skip_serializing_if = "Option::is_none")]
    pub sealed_as: Option<Uuid>,
    /// This sealing's own key, base64: written into the list on save and taken out (and wiped) as it's read, so an
    /// `Item` in memory never carries one.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) key: Option<String>,
    /// When the file was made and last changed on disk before it came in.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_modified: Option<f64>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Version {
    #[serde(with = "upper")]
    pub id: Uuid,
    pub date: f64,
    pub size: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub chunked: Option<bool>,
    #[serde(with = "upper_option", default, skip_serializing_if = "Option::is_none")]
    pub sealed_as: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) key: Option<String>,
}

impl Item {
    /// A new item with nothing sealed yet.
    pub fn new(name: &str, uti: &str, size: u64, now: f64) -> Item {
        Item {
            id: Uuid::new_v4(),
            name: name.to_owned(),
            uti: uti.to_owned(),
            size,
            added_at: now,
            folder: None,
            modified_at: None,
            tags: None,
            entry: None,
            versions: None,
            chunked: None,
            sealed_as: None,
            key: None,
            created: None,
            content_modified: None,
        }
    }

    pub fn is_chunked(&self) -> bool {
        self.chunked == Some(true)
    }

    pub fn is_file(&self) -> bool {
        self.entry.is_none()
    }

    /// When it last changed in the vault: edited, else added.
    pub fn changed_at(&self) -> f64 {
        self.modified_at.unwrap_or(self.added_at)
    }

    /// The date shown for it: last changed in the vault, else last changed before it came in, else when it came in.
    pub fn shown_date(&self) -> f64 {
        self.modified_at.or(self.content_modified).unwrap_or(self.added_at)
    }

    /// Whether it's in `folder` or anywhere below it.
    pub fn is_inside(&self, folder: &str) -> bool {
        self.folder.as_deref().is_some_and(|mine| mine == folder || mine.starts_with(&format!("{folder}/")))
    }

    pub fn tag_list(&self) -> &[String] {
        self.tags.as_deref().unwrap_or(&[])
    }

    /// Every sealing it uses: its current contents and each earlier version.
    pub fn blobs(&self) -> Vec<Uuid> {
        self.sealed_as.into_iter().chain(self.versions.iter().flatten().filter_map(|v| v.sealed_as)).collect()
    }
}

impl Version {
    pub fn is_chunked(&self) -> bool {
        self.chunked == Some(true)
    }
}

/// A secret (`Models/Secret.swift`): a few labelled fields, sealed like any file.
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
pub struct Secret {
    /// Always written. Read leniently, as tools/stillroom-open.py reads secrets: one without it is still taken out.
    #[serde(default)]
    pub template: Template,
    pub fields: Vec<SecretField>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Template {
    Login,
    Card,
    Wifi,
    Identity,
    #[default]
    Other,
}

#[derive(Clone, PartialEq, Deserialize, Serialize)]
pub struct SecretField {
    #[serde(with = "upper", default = "Uuid::new_v4")]
    pub id: Uuid,
    pub label: String,
    #[serde(default)]
    pub value: String,
    #[serde(default)]
    pub concealed: bool,
}

impl SecretField {
    pub fn new(label: &str, concealed: bool) -> SecretField {
        SecretField { id: Uuid::new_v4(), label: label.into(), value: String::new(), concealed }
    }
}

impl Drop for SecretField {
    fn drop(&mut self) {
        self.value.zeroize();
    }
}

impl Secret {
    /// A new secret of this kind, with the fields it starts with.
    pub fn new(template: Template) -> Secret {
        let f = SecretField::new;
        let fields = match template {
            Template::Login => vec![f("Website", false), f("Username", false), f("Password", true)],
            Template::Card => vec![f("Name on card", false), f("Number", true), f("Expires", false), f("Security code", true), f("PIN", true)],
            Template::Wifi => vec![f("Network", false), f("Password", true)],
            Template::Identity => vec![f("Full name", false), f("Document", false), f("Number", true), f("Expires", false)],
            Template::Other => vec![f("Secret", true)],
        };
        Secret { template, fields }
    }

    pub fn field(&self, label: &str) -> Option<&str> {
        self.fields.iter().find(|f| f.label == label).map(|f| f.value.as_str())
    }
}

/// UUIDs as Swift writes them: capitals.
mod upper {
    use serde::{Deserialize, Deserializer, Serializer};
    use uuid::Uuid;

    pub fn serialize<S: Serializer>(id: &Uuid, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(id.hyphenated().encode_upper(&mut Uuid::encode_buffer()))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Uuid, D::Error> {
        Uuid::deserialize(d)
    }
}

mod upper_option {
    use serde::{Deserialize, Deserializer, Serializer};
    use uuid::Uuid;

    pub fn serialize<S: Serializer>(id: &Option<Uuid>, s: S) -> Result<S::Ok, S::Error> {
        match id {
            Some(id) => super::upper::serialize(id, s),
            None => s.serialize_none(),
        }
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Option<Uuid>, D::Error> {
        Option::<Uuid>::deserialize(d)
    }
}

// MARK: Printing and wiping. Nothing that opens anything is ever printed, and an item key still in the list (one that
// stopped loading partway, or a list being written) is wiped with it.

impl Drop for Item {
    fn drop(&mut self) {
        self.key.zeroize();
    }
}

impl Drop for Version {
    fn drop(&mut self) {
        self.key.zeroize();
    }
}

/// Printed without the intruder key.
impl fmt::Debug for VaultList {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("VaultList")
            .field("files", &self.files)
            .field("folders", &self.folders)
            .field("show_in_capture", &self.show_in_capture)
            .field("touch_id", &self.touch_id)
            .field("kit_made", &self.kit_made)
            .field("kit_reminded", &self.kit_reminded)
            .field("hello", &self.hello)
            .finish_non_exhaustive()
    }
}

/// Printed without its key.
impl fmt::Debug for Item {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Item")
            .field("id", &self.id)
            .field("name", &self.name)
            .field("uti", &self.uti)
            .field("size", &self.size)
            .field("added_at", &self.added_at)
            .field("folder", &self.folder)
            .field("modified_at", &self.modified_at)
            .field("tags", &self.tags)
            .field("entry", &self.entry)
            .field("versions", &self.versions)
            .field("chunked", &self.chunked)
            .field("sealed_as", &self.sealed_as)
            .field("created", &self.created)
            .field("content_modified", &self.content_modified)
            .finish_non_exhaustive()
    }
}

impl fmt::Debug for Version {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Version")
            .field("id", &self.id)
            .field("date", &self.date)
            .field("size", &self.size)
            .field("chunked", &self.chunked)
            .field("sealed_as", &self.sealed_as)
            .finish_non_exhaustive()
    }
}

/// Printed without its value.
impl fmt::Debug for SecretField {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SecretField").field("label", &self.label).field("concealed", &self.concealed).finish_non_exhaustive()
    }
}
