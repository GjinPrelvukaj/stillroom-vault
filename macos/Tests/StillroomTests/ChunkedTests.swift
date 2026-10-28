import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// Every test here works in a temp folder of its own.
struct ChunkedTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ChunkedTests-\(UUID().uuidString)")
    let key = SymmetricKey(size: .bits256)
    let id = UUID()
    static let cs = Chunked.chunkSize
    static let sizes = [0, 1, cs - 1, cs, cs + 1, 3 * cs + 5]

    init() throws { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

    private func random(_ count: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &g) })
    }

    private func path(_ name: String) -> URL { folder.appending(path: name) }

    /// A blob of several chunks, sealed from Data, for the tamper tests.
    private func sealedSample(chunks: Int = 3) throws -> (URL, Data) {
        let plain = random(chunks * Self.cs + 5)
        let blob = path("sample.stillroom")
        try Chunked.seal(plain, to: blob, key: key, fileID: id)
        return (blob, plain)
    }

    @Test(arguments: sizes) func roundTripsFromAFile(size: Int) throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = random(size)
        try plain.write(to: path("in"))
        let blob = path("out.stillroom")
        #expect(try Chunked.seal(from: path("in"), to: blob, key: key, fileID: id) == size)
        try Chunked.unseal(blob, to: path("back"), key: key, fileID: id, plainSize: size)
        #expect(try Data(contentsOf: path("back")) == plain)
        #expect(try Chunked.read(blob, key: key, fileID: id, plainSize: size) == plain)
        // Padded like the old format, plus a header and each chunk's nonce and tag.
        let chunks = Chunked.chunkCount(plainSize: size, chunkSize: Self.cs)
        let blobSize = try FileManager.default.attributesOfItem(atPath: blob.path)[.size] as! Int
        #expect(blobSize == 8 + chunks * 28 + paddedLength(size))
        // Nothing left behind beside it but what was asked for.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["back", "in", "out.stillroom"])
    }

    @Test(arguments: sizes) func roundTripsFromData(size: Int) throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = random(size)
        let blob = path("out.stillroom")
        try Chunked.seal(plain, to: blob, key: key, fileID: id)
        #expect(try Chunked.read(blob, key: key, fileID: id, plainSize: size) == plain)
        // A slice that doesn't start at zero seals the same as a copy of it.
        let sliced = (Data([9, 9]) + plain).dropFirst(2)
        try Chunked.seal(sliced, to: blob, key: key, fileID: id)
        #expect(try Chunked.read(blob, key: key, fileID: id, plainSize: size) == plain)
    }

    @Test func randomRangesMatchThePlaintext() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (blob, plain) = try sealedSample()
        let reader = try ChunkedReader(url: blob, key: key, fileID: id, plainSize: plain.count)
        var ranges = [0..<0, 0..<1, 0..<plain.count, Self.cs - 1..<Self.cs + 1, plain.count - 1..<plain.count]
        for _ in 0..<200 {
            let a = Int.random(in: 0...plain.count), b = Int.random(in: 0...plain.count)
            ranges.append(min(a, b)..<max(a, b))
        }
        for range in ranges { #expect(try reader.read(range) == plain[range]) }
        // A player may ask past the end: it gets what there is.
        #expect(try reader.read(plain.count - 3..<plain.count + 100) == plain.suffix(3))
    }

    @Test func aFlippedByteFails() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (blob, plain) = try sealedSample()
        var bytes = try Data(contentsOf: blob)
        bytes[8 + Self.cs + 28 + 100] ^= 1
        try bytes.write(to: blob)
        #expect(throws: VaultError.damaged) { try Chunked.read(blob, key: self.key, fileID: self.id, plainSize: plain.count) }
        // Only the chunk it's in fails: the first is still whole.
        let reader = try ChunkedReader(url: blob, key: key, fileID: id, plainSize: plain.count)
        #expect(try reader.read(0..<10) == plain.prefix(10))
        #expect(throws: VaultError.damaged) { try reader.read(Self.cs..<Self.cs + 10) }
    }

    @Test func swappedChunksFail() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (blob, plain) = try sealedSample()
        let bytes = try Data(contentsOf: blob)
        let n = Self.cs + 28
        let swapped = bytes.prefix(8) + bytes[8 + n..<8 + 2 * n] + bytes[8..<8 + n] + bytes[(8 + 2 * n)...]
        try swapped.write(to: blob)
        #expect(throws: VaultError.damaged) { try Chunked.read(blob, key: self.key, fileID: self.id, plainSize: plain.count) }
        let reader = try ChunkedReader(url: blob, key: key, fileID: id, plainSize: plain.count)
        #expect(throws: VaultError.damaged) { try reader.read(0..<1) }
    }

    @Test func aDroppedLastChunkFails() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (blob, plain) = try sealedSample()
        let bytes = try Data(contentsOf: blob)
        let lastStart = 8 + 3 * (Self.cs + 28)
        try bytes.prefix(lastStart).write(to: blob)
        #expect(throws: VaultError.damaged) { try ChunkedReader(url: blob, key: self.key, fileID: self.id, plainSize: plain.count) }
        #expect(throws: VaultError.damaged) {
            try Chunked.unseal(blob, to: self.path("back"), key: self.key, fileID: self.id, plainSize: plain.count)
        }
        // A failed unseal leaves nothing half-written behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["sample.stillroom"])
        // Even told the shorter size, the chunk that's now last wasn't sealed as the last.
        let shorter = try ChunkedReader(url: blob, key: key, fileID: id, plainSize: 3 * Self.cs)
        #expect(throws: VaultError.damaged) { try shorter.read(3 * Self.cs - 1..<3 * Self.cs) }
    }

    @Test func anotherFilesBlobFails() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (blob, plain) = try sealedSample()
        #expect(throws: VaultError.damaged) { try Chunked.read(blob, key: self.key, fileID: UUID(), plainSize: plain.count) }
        #expect(throws: VaultError.damaged) {
            try Chunked.read(blob, key: SymmetricKey(size: .bits256), fileID: self.id, plainSize: plain.count)
        }
    }

    /// The player's loader end to end, on a real movie when this Mac has one: AVFoundation reads it from the sealed
    /// blob alone, finds the same length and tracks, and can pull a frame from the middle (a seek).
    static let movie = URL(filePath: "/System/Library/Wallpapers/.default/Golden Gate.mov")
    @Test(.enabled(if: FileManager.default.fileExists(atPath: movie.path)))
    func aSealedMoviePlaysThroughTheLoader() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let blob = path("movie.stillroom")
        let size = try Chunked.seal(from: Self.movie, to: blob, key: key, fileID: id)
        let loader = VaultStreamLoader(reader: try ChunkedReader(url: blob, key: key, fileID: id, plainSize: size),
                                       uti: "com.apple.quicktime-movie")
        let original = AVURLAsset(url: Self.movie)
        let (duration, playable, tracks) = try await loader.asset.load(.duration, .isPlayable, .tracks)
        #expect(playable)
        #expect(duration == (try await original.load(.duration)))
        #expect(tracks.count == (try await original.load(.tracks)).count)
        let frames = AVAssetImageGenerator(asset: loader.asset)
        let half = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
        let (image, _) = try await frames.image(at: half)
        #expect(image.width > 0)
    }
}

/// Found by fuzzing: an impossible size (the list says Int.max) is refused, not an arithmetic-overflow crash.
@Test func anImpossibleSizeIsRefused() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "huge-\(UUID().uuidString).stillroom")
    defer { try? FileManager.default.removeItem(at: url) }
    try Chunked.seal(Data("small".utf8), to: url, key: .init(size: .bits256), fileID: UUID())
    for size in [Int.max, Int.max / 2, 1 << 62] {
        #expect(throws: VaultError.damaged) { try ChunkedReader(url: url, key: .init(size: .bits256), fileID: UUID(), plainSize: size) }
    }
}
