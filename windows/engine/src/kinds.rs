//! Kinds of file as the Mac names them (UTIs, "public.jpeg"), which the list keeps for every item. Windows goes by a
//! name's extension, so an item added here gets the UTI the Mac would give it, and the Mac shows it as the same kind.
//! The engine asks of a kind only what the Mac app asks of it: is it text, a picture, a PDF, audio or video.

/// Extension (lowercase, no dot) → UTI, for the kinds people keep. Anything else is "public.data".
const TABLE: &[(&str, &str)] = &[
    // Text
    ("txt", "public.plain-text"),
    ("text", "public.plain-text"),
    ("md", "net.daringfireball.markdown"),
    ("markdown", "net.daringfireball.markdown"),
    ("csv", "public.comma-separated-values-text"),
    ("tsv", "public.tab-separated-values-text"),
    ("rtf", "public.rtf"),
    ("html", "public.html"),
    ("htm", "public.html"),
    ("xml", "public.xml"),
    ("json", "public.json"),
    ("log", "com.apple.log"),
    ("eml", "com.apple.mail.email"),
    ("emlx", "com.apple.mail.emlx"),
    ("vcf", "public.vcard"),
    ("ics", "com.apple.ical.ics"),
    // Documents
    ("pdf", "com.adobe.pdf"),
    ("doc", "com.microsoft.word.doc"),
    ("docx", "org.openxmlformats.wordprocessingml.document"),
    ("xls", "com.microsoft.excel.xls"),
    ("xlsx", "org.openxmlformats.spreadsheetml.sheet"),
    ("ppt", "com.microsoft.powerpoint.ppt"),
    ("pptx", "org.openxmlformats.presentationml.presentation"),
    ("odt", "org.oasis-open.opendocument.text"),
    ("ods", "org.oasis-open.opendocument.spreadsheet"),
    ("pages", "com.apple.iwork.pages.sffpages"),
    ("numbers", "com.apple.iwork.numbers.sffnumbers"),
    ("key", "com.apple.iwork.keynote.sffkey"),
    // Pictures
    ("jpg", "public.jpeg"),
    ("jpeg", "public.jpeg"),
    ("png", "public.png"),
    ("gif", "com.compuserve.gif"),
    ("heic", "public.heic"),
    ("heif", "public.heif"),
    ("tif", "public.tiff"),
    ("tiff", "public.tiff"),
    ("bmp", "com.microsoft.bmp"),
    ("webp", "org.webmproject.webp"),
    ("svg", "public.svg-image"),
    ("ico", "com.microsoft.ico"),
    ("dng", "com.adobe.raw-image"),
    // Audio and video
    ("mp3", "public.mp3"),
    ("m4a", "com.apple.m4a-audio"),
    ("aac", "public.aac-audio"),
    ("wav", "com.microsoft.waveform-audio"),
    ("aif", "public.aiff-audio"),
    ("aiff", "public.aiff-audio"),
    ("flac", "org.xiph.flac"),
    ("ogg", "org.xiph.ogg-audio"),
    ("mp4", "public.mpeg-4"),
    ("m4v", "com.apple.m4v-video"),
    ("mov", "com.apple.quicktime-movie"),
    ("avi", "public.avi"),
    ("mkv", "org.matroska.mkv"),
    ("webm", "org.webmproject.webm"),
    ("wmv", "com.microsoft.windows-media-wmv"),
    ("3gp", "public.3gpp"),
    // Archives
    ("zip", "public.zip-archive"),
    ("7z", "org.7-zip.7-zip-archive"),
    ("rar", "com.rarlab.rar-archive"),
    ("gz", "org.gnu.gnu-zip-archive"),
    ("tar", "public.tar-archive"),
];

/// The UTI for a file name, from its extension; "public.data" when unknown.
pub fn uti_for_name(name: &str) -> &'static str {
    let extension = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    TABLE.iter().find(|(e, _)| *e == extension).map(|(_, uti)| *uti).unwrap_or("public.data")
}

fn any_of(uti: &str, list: &[&str]) -> bool {
    list.contains(&uti)
}

/// Plain text of any sort (what the Mac's `.text` conforms to): readable as UTF-8.
pub fn is_text(uti: &str) -> bool {
    uti.ends_with("-text")
        || uti.ends_with(".plain-text")
        || any_of(uti, &[
            "public.text", "public.plain-text", "public.utf8-plain-text", "net.daringfireball.markdown", "public.rtf",
            "public.html", "public.xml", "public.json", "com.apple.log", "public.vcard", "com.apple.ical.ics",
            "public.source-code", "public.script", "public.shell-script", "public.python-script",
            "com.netscape.javascript-source", "public.swift-source", "public.c-source", "public.yaml",
        ])
}

pub fn is_pdf(uti: &str) -> bool {
    uti == "com.adobe.pdf"
}

pub fn is_image(uti: &str) -> bool {
    uti.ends_with("-image")
        || any_of(uti, &[
            "public.image", "public.jpeg", "public.png", "com.compuserve.gif", "public.heic", "public.heif", "public.tiff",
            "com.microsoft.bmp", "org.webmproject.webp", "public.svg-image", "com.microsoft.ico", "com.adobe.raw-image",
            "public.camera-raw-image", "public.jpeg-2000",
        ])
}

/// Audio or video: always sealed in chunks, so it plays from the sealed file.
pub fn is_audiovisual(uti: &str) -> bool {
    uti.ends_with("-audio")
        || uti.ends_with("-movie")
        || uti.ends_with("-video")
        || any_of(uti, &[
            "public.audio", "public.movie", "public.video", "public.audiovisual-content", "public.mp3", "public.mpeg-4",
            "public.mpeg", "public.mpeg-2-video", "com.apple.quicktime-movie", "public.avi", "org.matroska.mkv",
            "org.webmproject.webm", "com.microsoft.windows-media-wmv", "public.3gpp", "public.3gpp2", "org.xiph.flac",
            "com.apple.m4a-audio", "com.apple.m4v-video", "public.aac-audio", "com.microsoft.waveform-audio",
            "public.aiff-audio", "org.xiph.ogg-audio",
        ])
}

/// An email file (.eml, or Apple Mail's .emlx).
pub fn is_email(uti: &str, name: &str) -> bool {
    let name = name.to_ascii_lowercase();
    any_of(uti, &["com.apple.mail.email", "com.apple.mail.emlx", "public.email-message"])
        || name.ends_with(".eml")
        || name.ends_with(".emlx")
}

/// Documents that are neither text nor pictures: office files, rich text, fonts.
fn is_other_document(uti: &str) -> bool {
    any_of(uti, &[
        "com.microsoft.word.doc", "org.openxmlformats.wordprocessingml.document", "com.microsoft.excel.xls",
        "org.openxmlformats.spreadsheetml.sheet", "com.microsoft.powerpoint.ppt", "org.openxmlformats.presentationml.presentation",
        "org.oasis-open.opendocument.text", "org.oasis-open.opendocument.spreadsheet", "com.apple.iwork.pages.sffpages",
        "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.keynote.sffkey", "public.rtf", "com.apple.rtfd", "public.font",
        "public.truetype-ttf-font", "public.opentype-font",
    ])
}

/// Things that run, or open in a browser that runs their scripts and loads from the network: never opened outside.
fn runs(uti: &str) -> bool {
    uti.ends_with("-script")
        || uti.ends_with("-source")
        || any_of(uti, &[
            "public.executable", "public.script", "public.shell-script", "public.source-code", "public.unix-executable",
            "com.apple.application", "com.apple.application-bundle", "com.apple.package", "public.disk-image",
            "com.apple.installer-package-archive", "com.microsoft.windows-executable", "com.microsoft.windows-installer",
            // Web pages count as text, but would load from the network: the email viewer's lockdown would mean nothing.
            "public.html", "public.xhtml", "public.xml", "public.svg-image", "com.apple.webarchive",
            "com.apple.web-internet-location", "com.apple.internet-location", "com.microsoft.internet-shortcut",
        ])
}

/// Whether an item may be opened in another app (`AppState.canEdit`): only documents, pictures, PDFs, audio and video,
/// judged both by the kind recorded and by the name's extension (which is what Windows goes by when it opens the copy),
/// so a renamed program can't slip through. Notes, secrets and anything without an extension never open outside.
pub fn can_edit(uti: &str, name: &str, is_file: bool) -> bool {
    let has_extension = name.rsplit_once('.').is_some_and(|(stem, e)| !stem.is_empty() && !e.is_empty());
    if !is_file || !has_extension {
        return false;
    }
    [uti, uti_for_name(name)].iter().all(|kind| {
        (is_text(kind) || is_image(kind) || is_pdf(kind) || is_audiovisual(kind) || is_other_document(kind)) && !runs(kind)
    })
}

/// How a kind looks in the window, as the Mac's `VaultFile.symbol` and `Shelf.of` decide it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Look {
    Other = 0,
    Picture = 1,
    Audio = 2,
    Video = 3,
    Pdf = 4,
    Text = 5,
    /// Office files and the like (the Mac's composite content, presentations, spreadsheets).
    Document = 6,
    Archive = 7,
}

impl Look {
    /// The shelf it goes on in the sidebar: pictures, documents (PDFs, text and office files), audio and video, or
    /// other (archives included), as `Shelf.of`.
    pub fn shelf(self) -> &'static str {
        match self {
            Look::Picture => "images",
            Look::Audio | Look::Video => "media",
            Look::Pdf | Look::Text | Look::Document => "documents",
            Look::Archive | Look::Other => "other",
        }
    }
}

/// A kind's look, checked in the Mac's order: a picture before text (an SVG is both), audio before video.
pub fn look(uti: &str) -> Look {
    let audio = uti.ends_with("-audio") || any_of(uti, &["public.audio", "public.mp3", "org.xiph.flac"]);
    if is_image(uti) {
        Look::Picture
    } else if audio {
        Look::Audio
    } else if is_audiovisual(uti) {
        Look::Video
    } else if is_pdf(uti) {
        Look::Pdf
    } else if uti.ends_with("-archive") || any_of(uti, &["public.archive", "public.zip-archive", "com.rarlab.rar-archive"]) {
        Look::Archive
    } else if is_text(uti) {
        Look::Text
    } else if is_other_document(uti) && !uti.contains("font") {
        Look::Document
    } else {
        Look::Other
    }
}

/// Whether something this big, of this kind, is sealed in chunks (`VaultStore.streams`): over 8 MiB, or audio or video.
pub fn streams(size: u64, uti: &str) -> bool {
    size > 8 << 20 || is_audiovisual(uti)
}
