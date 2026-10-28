import Foundation
import UniformTypeIdentifiers

/// One thing in the vault, as its list remembers it: a file, a note or a secret. The list itself is sealed, so even
/// names don't show on disk.
struct VaultFile: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Its kind as the Mac names kinds (public.jpeg, com.adobe.pdf).
    let uti: String
    /// Bytes before sealing.
    var size: Int
    var addedAt = Date()
    /// The folder it sits in ("Taxes/2025"); nil at the top.
    var folder: String?
    var modifiedAt: Date?
    var tags: [String]?
    /// Set for a note or a secret; nil for a file.
    var entry: Entry?
    /// Earlier contents, oldest first, each sealed in a file of its own.
    var versions: [Version]?
    /// Sealed in the streaming format (big files, audio and video), rather than in one piece.
    var chunked: Bool?
    /// The id this sealing is tied to: a fresh one each time it's sealed, so nothing from one version (or a whole
    /// older version) can be passed off as another. It also names the blob on disk. Always set in a saved list.
    var sealedAs: UUID?
    /// This sealing's own key, base64, on disk only: the list is read into `AppState.itemKeys` and this is cleared, so
    /// no copy of a `VaultFile` held anywhere can open anything once the vault locks. nil in memory.
    var key: String?
    /// When the file was made and last changed on disk before it came in, so a 2019 photo still says 2019, and
    /// copies taken out get those dates back.
    var created: Date?
    var contentModified: Date?

    enum Entry: String, Codable, Sendable { case note, secret }

    struct Version: Identifiable, Codable, Hashable, Sendable {
        var id = UUID()
        var date: Date
        var size: Int
        var chunked: Bool?
        var sealedAs: UUID?
        /// As `VaultFile.key`.
        var key: String?
    }

    var type: UTType? { UTType(uti) }
    var kind: Shelf {
        switch entry {
        case .note: .notes
        case .secret: .secrets
        case nil: Shelf.of(type)
        }
    }
    var isFile: Bool { entry == nil }
    /// "PDF document", "JPEG image": the Finder's own words.
    var kindName: String {
        switch entry {
        case .note: "Note"
        case .secret: "Secret"
        case nil: type?.localizedDescription?.capitalizedFirst ?? "File"
        }
    }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
    var changedAt: Date { modifiedAt ?? addedAt }
    /// The date shown for it: last changed in the vault, else last changed before it came in, else when it came in.
    var shownDate: Date { modifiedAt ?? contentModified ?? addedAt }
    var tagList: [String] { tags ?? [] }
    var streamed: Bool { chunked == true }
    /// Audio or video: played inside Stillroom from the sealed file.
    var playable: Bool { isFile && type?.conforms(to: .audiovisualContent) == true }

    var symbol: String {
        if entry == .note { return "note.text" }
        if entry == .secret { return "key.horizontal" }
        guard let type else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "play.rectangle" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "archivebox" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    /// Whether it's in `folder` or anywhere below it.
    func isInside(_ folder: String) -> Bool {
        guard let mine = self.folder else { return false }
        return mine == folder || mine.hasPrefix(folder + "/")
    }
}

/// The sealed list: everything in a vault, and the folders made in it (a folder with nothing in it yet has to be
/// remembered somewhere).
struct VaultIndex: Codable, Sendable {
    var files: [VaultFile] = []
    var folders: [String] = []
    /// Shown in screenshots and screen sharing once open. Kept here, sealed with the vault, rather than in the app's
    /// preferences, where any program on the Mac could switch the protection off unseen.
    var showInCapture = false
    /// The slot's intruder private key, base64: entries recorded while locked are sealed to its public half.
    var intruder = ""
    /// The public key in the touchid.key this slot made, base64, or zeros: Touch ID is this slot's when they match.
    var touchID = VaultIndex.noTouchID
    /// When the kit was made and last reminded about, whole seconds since 2001, 12 digits ("000000000000": none).
    /// Fixed width, so an empty list is the same size however its slot was made.
    var kitMade = VaultIndex.never
    var kitReminded = VaultIndex.never

    static let noTouchID = Data(count: 64).base64EncodedString()
    static let never = String(repeating: "0", count: 12)
    static func stamp(_ date: Date) -> String { String(format: "%012d", Int(date.timeIntervalSinceReferenceDate)) }
    static func date(_ stamp: String) -> Date? {
        stamp == never ? nil : Int(stamp).map { Date(timeIntervalSinceReferenceDate: TimeInterval($0)) }
    }
}

/// What the sidebar shows: everything, notes, secrets, or one kind of file.
enum Shelf: Hashable, CaseIterable {
    case all, notes, secrets, images, documents, media, other

    static let library: [Shelf] = [.all, .notes, .secrets]
    static let kinds: [Shelf] = [.images, .documents, .media, .other]

    static func of(_ type: UTType?) -> Shelf {
        guard let type else { return .other }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .audiovisualContent) { return .media }
        if [UTType.pdf, .text, .compositeContent, .presentation, .spreadsheet].contains(where: { type.conforms(to: $0) }) {
            return .documents
        }
        return .other
    }

    /// Whether an item belongs on this shelf. All Files holds files only; notes and secrets have their own.
    func holds(_ file: VaultFile) -> Bool {
        self == .all ? file.isFile : file.kind == self
    }

    var title: String {
        switch self {
        case .all: "All Files"
        case .notes: "Notes"
        case .secrets: "Secrets"
        case .images: "Images"
        case .documents: "Documents"
        case .media: "Audio & Video"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.stack"
        case .notes: "note.text"
        case .secrets: "key.horizontal"
        case .images: "photo"
        case .documents: "doc.text"
        case .media: "play.rectangle"
        case .other: "shippingbox"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension String {
    /// A folder's name as people see it. "/" divides folder paths, so a "/" typed in a name (26/10/26) is kept as a
    /// look-alike character; it's drawn as a real "/" again here.
    var shownName: String { replacingOccurrences(of: "\u{2215}", with: "/") }
    /// A whole folder path as people see it: "Archive › 24/10/26".
    var shownPath: String { split(separator: "/").map { String($0).shownName }.joined(separator: " › ") }
    /// The last folder in a path, as people see it.
    var shownLast: String { (split(separator: "/").last.map(String.init) ?? self).shownName }
}
