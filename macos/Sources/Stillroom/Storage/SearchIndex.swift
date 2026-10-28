import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Searching inside things: the words in notes, secrets (labels and visible fields, never concealed ones), text
/// files, PDFs, and pictures (read with the Mac's own text recognition). The words are kept in a sealed index per
/// vault, so the next unlock needn't read everything again; nothing about it is in the open.
enum SearchIndex {
    struct Entry: Codable, Sendable {
        /// What the item was when read, so a changed item is read again.
        var changed: Date
        var size: Int
        var text: String
    }

    /// The biggest item read for search: past this it's skipped (videos, archives and huge scans aren't searched).
    static let largest = 50 << 20
    /// The most text kept per item.
    static let longest = 200_000

    static func load(using key: SymmetricKey, slot: VaultStore.Slot, cover: SymmetricKey) -> [UUID: Entry] {
        guard let sealed = VaultStore.readCovered(.search, slot, cover: cover),
              let json = try? unseal(sealed, with: key, binding: Bound.search),
              let index = try? JSONDecoder().decode([UUID: Entry].self, from: json) else { return [:] }
        return index
    }

    /// The index sealed with the slot key, padded the way lists are.
    static func sealed(_ index: [UUID: Entry], using key: SymmetricKey) throws -> Data {
        var json = try JSONEncoder().encode(index)
        json.append(Data(repeating: 0x20, count: paddedLength(json.count) - json.count))
        return try seal(json, with: key, binding: Bound.search)
    }

    static func save(_ index: [UUID: Entry], using key: SymmetricKey, slot: VaultStore.Slot, cover: SymmetricKey) {
        guard let sealed = try? sealed(index, using: key) else { return }
        try? VaultStore.writeCovered(sealed, .search, slot, cover: cover)
    }

    /// Whether an item is worth reading for words.
    static func reads(_ file: VaultFile) -> Bool {
        guard file.size <= largest, !file.streamed else { return false }
        if file.entry != nil || Email.isEmail(file) { return true }
        guard let type = file.type else { return false }
        return type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .image)
    }

    /// The words in an item's contents, or nil when there are none to find.
    static func words(in file: VaultFile, _ data: Data) -> String? {
        let text: String?
        switch file.entry {
        case .note:
            text = String(data: data, encoding: .utf8)
        case .secret:
            let secret = try? JSONDecoder().decode(Secret.self, from: data)
            // Concealed values and two-factor setups stay out of the index: a search box mustn't become a way to read them.
            text = secret?.fields.map { $0.concealed || $0.oneTimeCode != nil ? $0.label : "\($0.label) \($0.value)" }
                .joined(separator: "\n")
        case nil:
            let type = file.type
            if Email.isEmail(file) {
                text = Email.parse(data)?.words ?? String(data: data, encoding: .utf8)
            } else if type?.conforms(to: .pdf) == true {
                text = PDFDocument(data: data)?.string
            } else if type?.conforms(to: .image) == true {
                text = recognized(data)
            } else {
                text = String(data: data, encoding: .utf8)
            }
        }
        guard let text, !text.isEmpty else { return nil }
        return String(text.prefix(longest))
    }

    /// The text in a picture, by the Mac's own recognition, on this Mac only.
    private static func recognized(_ data: Data) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard (try? VNImageRequestHandler(data: data).perform([request])) != nil else { return nil }
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// A short piece of `text` around the first place `query` appears, for a search result's row.
    static func snippet(_ text: String, around query: String) -> String? {
        guard let hit = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = text.index(hit.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(hit.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
        let piece = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > text.startIndex ? "…" : "") + piece + (end < text.endIndex ? "…" : "")
    }
}
