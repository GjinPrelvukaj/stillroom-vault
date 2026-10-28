import CryptoKit
import Foundation

/// A sealed file in pieces, so a file of any size goes in and comes out without ever being in memory whole, and a
/// video can be played from the middle without opening the rest.
///
///     "VLT2" | chunk size (UInt32, big-endian) | chunk 0 | chunk 1 | ... | last chunk
///     each chunk: nonce (12) | ciphertext | tag (16), sealed with AES-256-GCM
///
/// Each chunk is bound to its file, its place and whether it's the last (the authenticated data), so chunks can't
/// be moved, swapped in from another file, dropped, or the file cut short without the seal failing. Every chunk is
/// full except the last; the plaintext is padded with zeros to `paddedLength`, so the size gives little away.
enum Chunked {
    static let chunkSize = 1 << 20
    static let magic = Data("VLT2".utf8)
    static let headerSize = 8
    /// What sealing adds to each chunk: the nonce and the tag.
    static let overhead = 28

    /// Seals a file from disk chunk by chunk (never the whole file in memory), padding the plaintext to
    /// `paddedLength(size)` with zeros at the end. Returns the real plaintext size.
    @discardableResult
    static func seal(from source: URL, to destination: URL, key: SymmetricKey, fileID: UUID) throws -> Int {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let size = Int(try input.seekToEnd())
        try input.seek(toOffset: 0)
        try write(to: destination, key: key, fileID: fileID, size: size) { count in
            try input.read(upToCount: count) ?? Data()
        }
        return size
    }

    /// Seals bytes already in memory the same way (for small edits).
    static func seal(_ data: Data, to destination: URL, key: SymmetricKey, fileID: UUID) throws {
        var offset = data.startIndex
        try write(to: destination, key: key, fileID: fileID, size: data.count) { count in
            defer { offset += count }
            return data[offset..<offset + count]
        }
    }

    /// Decrypts to a plaintext file, streaming, truncated to plainSize. Every chunk is checked, padding too, so a
    /// cut-short blob fails here rather than coming out short.
    static func unseal(_ url: URL, to destination: URL, key: SymmetricKey, fileID: UUID, plainSize: Int) throws {
        let reader = try ChunkedReader(url: url, key: key, fileID: fileID, plainSize: plainSize)
        try atomically(to: destination) { output in
            for index in 0..<reader.count {
                try autoreleasepool {
                    let chunk = try reader.chunk(index)
                    let start = index * reader.chunkSize
                    let real = max(0, min(chunk.count, plainSize - start))
                    if real > 0 { try output.write(contentsOf: chunk.prefix(real)) }
                }
            }
        }
    }

    /// Whole contents in memory (for small files / previews).
    static func read(_ url: URL, key: SymmetricKey, fileID: UUID, plainSize: Int) throws -> Data {
        let reader = try ChunkedReader(url: url, key: key, fileID: fileID, plainSize: plainSize)
        // The chunks past the real size are padding, but still opened, so a cut-short blob is caught here too.
        var data = Data(capacity: plainSize)
        for index in 0..<reader.count { data.append(try reader.chunk(index)) }
        return data.prefix(plainSize)
    }

    /// What each chunk's seal is bound to: the file, the chunk's place, and whether it's the last.
    static func authenticated(_ fileID: UUID, _ index: Int, last: Bool) -> Data {
        var data = withUnsafeBytes(of: fileID.uuid) { Data($0) }
        withUnsafeBytes(of: UInt64(index).bigEndian) { data.append(contentsOf: $0) }
        data.append(last ? 1 : 0)
        return data
    }

    /// How many chunks a file of this real size seals into: at least one, so even an empty file has a last chunk
    /// to show it wasn't cut short.
    static func chunkCount(plainSize: Int, chunkSize: Int) -> Int {
        max(1, (paddedLength(plainSize) + chunkSize - 1) / chunkSize)
    }

    /// The sealing loop both seals share. `next(n)` gives the next n real bytes; zeros pad after them.
    private static func write(to destination: URL, key: SymmetricKey, fileID: UUID, size: Int,
                              next: (Int) throws -> Data) throws {
        let padded = paddedLength(size)
        let count = chunkCount(plainSize: size, chunkSize: chunkSize)
        try atomically(to: destination) { output in
            var header = magic
            withUnsafeBytes(of: UInt32(chunkSize).bigEndian) { header.append(contentsOf: $0) }
            try output.write(contentsOf: header)
            for index in 0..<count {
                try autoreleasepool {
                    let start = index * chunkSize
                    let length = min(chunkSize, padded - start)
                    let real = max(0, min(length, size - start))
                    var chunk = real > 0 ? try next(real) : Data()
                    // A file that shrank while being read would otherwise go in with zeros where its end was.
                    guard chunk.count == real else { throw VaultError.damaged }
                    chunk.append(Data(count: length - real))
                    let sealed = try AES.GCM.seal(chunk, using: key,
                                                  authenticating: authenticated(fileID, index, last: index == count - 1))
                    try output.write(contentsOf: sealed.combined!)
                }
            }
        }
    }

    /// Writes to a file beside the destination, then moves it into place in one step: a crash midway leaves the
    /// old file (or none), never half of one.
    private static func atomically(to destination: URL, _ body: (FileHandle) throws -> Void) throws {
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let temp = folder.appending(path: ".\(UUID().uuidString).partial")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        do {
            let output = try FileHandle(forWritingTo: temp)
            do { try body(output); try output.synchronize(); try output.close() } catch { try? output.close(); throw error }
            // rename(2) replaces whatever is there in one step; FileManager's move refuses if the file exists.
            guard rename(temp.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}

/// Reads any range of a chunked blob, opening only the chunks the range touches. Safe to use from several threads.
final class ChunkedReader: @unchecked Sendable {
    let chunkSize: Int
    let count: Int
    let plainSize: Int
    private let handle: FileHandle
    private let key: SymmetricKey
    private let fileID: UUID
    private let paddedSize: Int
    private let lock = NSLock()
    // ponytail: one chunk cached, enough for a player reading forward; a small LRU if seeking back and forth thrashes.
    private var cached: (index: Int, data: Data)?

    init(url: URL, key: SymmetricKey, fileID: UUID, plainSize: Int) throws {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            let header = try handle.read(upToCount: Chunked.headerSize) ?? Data()
            guard header.count == Chunked.headerSize, header.prefix(4) == Chunked.magic else { throw VaultError.damaged }
            let size = header.dropFirst(4).reduce(0) { $0 << 8 | Int($1) }
            // A sane chunk size only: a changed header can't make one chunk the size of the disk.
            // A size past 1 PiB can't be real and would overflow the length sums below.
            guard (1...64 << 20).contains(size), (0...1 << 50).contains(plainSize) else { throw VaultError.damaged }
            chunkSize = size
            paddedSize = paddedLength(plainSize)
            count = Chunked.chunkCount(plainSize: plainSize, chunkSize: size)
            // The real size comes from the sealed list, so the blob must be exactly as long as that size seals to:
            // a dropped or added chunk fails here, before any range is read.
            let expected = Chunked.headerSize + count * Chunked.overhead + paddedSize
            guard try handle.seekToEnd() == UInt64(expected) else { throw VaultError.damaged }
        } catch {
            try? handle.close()
            throw error
        }
        self.handle = handle
        self.key = key
        self.fileID = fileID
        self.plainSize = plainSize
    }

    deinit { try? handle.close() }

    /// The bytes in `range`, clamped to the real size (a player may ask past the end).
    func read(_ range: Range<Int>) throws -> Data {
        let range = range.clamped(to: 0..<plainSize)
        guard !range.isEmpty else { return Data() }
        var data = Data(capacity: range.count)
        for index in range.lowerBound / chunkSize...(range.upperBound - 1) / chunkSize {
            let chunk = try chunk(index)
            let start = index * chunkSize
            data.append(chunk[max(range.lowerBound, start) - start..<min(range.upperBound, start + chunk.count) - start])
        }
        return data
    }

    /// One chunk opened, padding included.
    func chunk(_ index: Int) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.index == index { return cached.data }
        guard (0..<count).contains(index) else { throw VaultError.damaged }
        let length = min(chunkSize, paddedSize - index * chunkSize) + Chunked.overhead
        try handle.seek(toOffset: UInt64(Chunked.headerSize + index * (chunkSize + Chunked.overhead)))
        guard let sealed = try handle.read(upToCount: length), sealed.count == length,
              let data = try? AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key,
                                           authenticating: Chunked.authenticated(fileID, index, last: index == count - 1))
        else { throw VaultError.damaged }
        cached = (index, data)
        return data
    }
}
