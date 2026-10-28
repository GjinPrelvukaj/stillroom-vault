import Foundation

/// Argon2id written in Swift from RFC 9106: what Stillroom used before the reference C, kept as a second, independent
/// implementation the C is checked against (`Argon2Tests`).
func swiftArgon2id(password: Data, salt: Data, memoryKiB: UInt32, iterations: UInt32, parallelism: UInt32, length: Int,
              secret: Data = Data(), associatedData: Data = Data()) -> Data {
    precondition(parallelism >= 1 && iterations >= 1 && length >= 4 && memoryKiB >= 8 * parallelism)
    let lanes = Int(parallelism)
    // Memory rounds down to whole segments: 4 per lane.
    let laneLength = Int(memoryKiB) / (4 * lanes) * 4
    let blocks = laneLength * lanes

    var h0Input = [UInt8]()
    for n in [parallelism, UInt32(length), memoryKiB, iterations, 0x13, 2] { h0Input.appendLE32(n) }
    for part in [password, salt, secret, associatedData] {
        h0Input.appendLE32(UInt32(part.count))
        h0Input += part
    }
    var h0 = blake2b(h0Input, length: 64)
    // The password itself, and what's made straight from it, go too.
    defer { wipe(&h0Input); wipe(&h0) }

    let base = UnsafeMutablePointer<UInt64>.allocate(capacity: blocks * 128)
    // The blocks are all derived from the password, so they are wiped before the memory goes back.
    defer {
        memset_s(base, blocks * 1024, 0, blocks * 1024)
        base.deallocate()
    }
    let memory = Memory(base: base, lanes: lanes, laneLength: laneLength, passes: Int(iterations))

    for lane in 0..<lanes {
        for i in 0..<2 {
            var input = h0
            input.appendLE32(UInt32(i))
            input.appendLE32(UInt32(lane))
            memory.store(hPrime(input, length: 1024), at: lane * laneLength + i)
        }
    }

    // Lanes only reach into other lanes' finished slices, so within a slice they can all be filled at once.
    for pass in 0..<Int(iterations) {
        for slice in 0..<4 {
            DispatchQueue.concurrentPerform(iterations: lanes) { lane in
                memory.fill(pass: pass, slice: slice, lane: lane)
            }
        }
    }

    var last = [UInt64](repeating: 0, count: 128)
    for lane in 0..<lanes {
        let block = base + (lane * laneLength + laneLength - 1) * 128
        for k in 0..<128 { last[k] ^= block[k] }
    }
    var lastBytes = [UInt8]()
    lastBytes.reserveCapacity(1024)
    for word in last { lastBytes.appendLE64(word) }
    defer { wipe(&last); wipe(&lastBytes) }
    return Data(hPrime(lastBytes, length: length))
}

/// Zeroes an array in place, in a way the compiler can't drop as a dead store.
// ponytail: copies Swift made along the way (and the password String in the UI) aren't reached; that's the ceiling.
private func wipe<T>(_ array: inout [T]) {
    array.withUnsafeMutableBytes { if let base = $0.baseAddress { _ = memset_s(base, $0.count, 0, $0.count) } }
}

/// The Argon2 memory: `lanes` rows of `laneLength` 1 KiB blocks, each block 128 words.
// ponytail: unchecked Sendable because lanes write disjoint blocks within a slice; that is the whole safety argument.
private struct Memory: @unchecked Sendable {
    let base: UnsafeMutablePointer<UInt64>
    let lanes: Int
    let laneLength: Int
    let passes: Int
    var segment: Int { laneLength / 4 }

    func store(_ bytes: [UInt8], at index: Int) {
        let block = base + index * 128
        bytes.withUnsafeBytes { raw in
            for k in 0..<128 { block[k] = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: k * 8, as: UInt64.self)) }
        }
    }

    func fill(pass: Int, slice: Int, lane: Int) {
        // Argon2id: the first half of the first pass picks blocks from a counter, not the password, so its memory
        // access pattern leaks nothing to a side channel; the rest picks from the data, which is harder to trade off.
        let independent = pass == 0 && slice < 2
        let scratch = UnsafeMutablePointer<UInt64>.allocate(capacity: 128 * 4)
        scratch.initialize(repeating: 0, count: 128 * 4)
        defer {
            memset_s(scratch, 128 * 4 * 8, 0, 128 * 4 * 8)
            scratch.deallocate()
        }
        let q = scratch, zero = scratch + 128, input = scratch + 256, address = scratch + 384

        func nextAddresses() {
            input[6] &+= 1
            compress(zero, input, into: address, xor: false, q)
            compress(zero, address, into: address, xor: false, q)
        }

        let start = pass == 0 && slice == 0 ? 2 : 0
        if independent {
            for (k, v) in [pass, lane, slice, laneLength * lanes, passes, 2].enumerated() { input[k] = UInt64(v) }
            if start == 2 { nextAddresses() }
        }

        var current = lane * laneLength + slice * segment + start
        for i in start..<segment {
            let previous = current % laneLength == 0 ? current + laneLength - 1 : current - 1
            let random: UInt64
            if independent {
                if i % 128 == 0 { nextAddresses() }
                random = address[i % 128]
            } else {
                random = base[previous * 128]
            }
            let refLane = pass == 0 && slice == 0 ? lane : Int((random >> 32) % UInt64(lanes))
            let refIndex = referenceIndex(pass: pass, slice: slice, index: i, random: random & 0xffff_ffff,
                                          sameLane: refLane == lane)
            compress(base + previous * 128, base + (refLane * laneLength + refIndex) * 128,
                     into: base + current * 128, xor: pass > 0, q)
            current += 1
        }
    }

    /// Which block of the reference lane to mix in: any finished block except the one just written, skewed
    /// toward recent ones (RFC 9106 section 3.4.2).
    private func referenceIndex(pass: Int, slice: Int, index: Int, random: UInt64, sameLane: Bool) -> Int {
        var area: Int
        var start = 0
        if pass == 0 {
            if slice == 0 {
                area = index - 1
            } else {
                area = slice * segment + (sameLane ? index - 1 : (index == 0 ? -1 : 0))
            }
        } else {
            start = slice == 3 ? 0 : (slice + 1) * segment
            area = laneLength - segment + (sameLane ? index - 1 : (index == 0 ? -1 : 0))
        }
        let x = (random &* random) >> 32
        let relative = UInt64(area) - 1 - ((UInt64(area) &* x) >> 32)
        return (start + Int(relative)) % laneLength
    }
}

/// Argon2's G: `out = P(x ^ y) ^ (x ^ y)`, further XORed into `out` on later passes. `q` is 128 words of scratch.
/// `out` may be `y`: x ^ y is read before `out` is written.
@inline(__always)
private func compress(_ x: UnsafeMutablePointer<UInt64>, _ y: UnsafeMutablePointer<UInt64>,
                      into out: UnsafeMutablePointer<UInt64>, xor: Bool, _ q: UnsafeMutablePointer<UInt64>) {
    if xor {
        for k in 0..<128 { let r = x[k] ^ y[k]; q[k] = r; out[k] ^= r }
    } else {
        for k in 0..<128 { let r = x[k] ^ y[k]; q[k] = r; out[k] = r }
    }
    for i in 0..<8 { permute(q + 16 * i, 2) }   // rows: 16 words in a row
    for i in 0..<8 { permute(q + 2 * i, 16) }   // columns: word pairs 16 apart
    for k in 0..<128 { out[k] ^= q[k] }
}

/// The BLAKE2b round on 16 words, the j-th at `p[(j / 2) * s + j % 2]`, with BlaMka's multiply in each step.
@inline(__always)
private func permute(_ p: UnsafeMutablePointer<UInt64>, _ s: Int) {
    var v0 = p[0], v1 = p[1], v2 = p[s], v3 = p[s + 1]
    var v4 = p[2 * s], v5 = p[2 * s + 1], v6 = p[3 * s], v7 = p[3 * s + 1]
    var v8 = p[4 * s], v9 = p[4 * s + 1], v10 = p[5 * s], v11 = p[5 * s + 1]
    var v12 = p[6 * s], v13 = p[6 * s + 1], v14 = p[7 * s], v15 = p[7 * s + 1]
    blamka(&v0, &v4, &v8, &v12); blamka(&v1, &v5, &v9, &v13)
    blamka(&v2, &v6, &v10, &v14); blamka(&v3, &v7, &v11, &v15)
    blamka(&v0, &v5, &v10, &v15); blamka(&v1, &v6, &v11, &v12)
    blamka(&v2, &v7, &v8, &v13); blamka(&v3, &v4, &v9, &v14)
    p[0] = v0; p[1] = v1; p[s] = v2; p[s + 1] = v3
    p[2 * s] = v4; p[2 * s + 1] = v5; p[3 * s] = v6; p[3 * s + 1] = v7
    p[4 * s] = v8; p[4 * s + 1] = v9; p[5 * s] = v10; p[5 * s + 1] = v11
    p[6 * s] = v12; p[6 * s + 1] = v13; p[7 * s] = v14; p[7 * s + 1] = v15
}

@inline(__always)
private func blamka(_ a: inout UInt64, _ b: inout UInt64, _ c: inout UInt64, _ d: inout UInt64) {
    a = a &+ b &+ 2 &* (a & 0xffff_ffff) &* (b & 0xffff_ffff); d = rotr(d ^ a, 32)
    c = c &+ d &+ 2 &* (c & 0xffff_ffff) &* (d & 0xffff_ffff); b = rotr(b ^ c, 24)
    a = a &+ b &+ 2 &* (a & 0xffff_ffff) &* (b & 0xffff_ffff); d = rotr(d ^ a, 16)
    c = c &+ d &+ 2 &* (c & 0xffff_ffff) &* (d & 0xffff_ffff); b = rotr(b ^ c, 63)
}

@inline(__always)
private func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x &>> n) | (x &<< (64 &- n)) }

/// Argon2's H': BLAKE2b stretched to any length by chaining 64-byte hashes and keeping half of each.
private func hPrime(_ x: [UInt8], length: Int) -> [UInt8] {
    var input = [UInt8]()
    input.appendLE32(UInt32(length))
    input += x
    guard length > 64 else { return blake2b(input, length: length) }
    var v = blake2b(input, length: 64)
    var out = Array(v[0..<32])
    var remaining = length - 32
    while remaining > 64 {
        v = blake2b(v, length: 64)
        out += v[0..<32]
        remaining -= 32
    }
    return out + blake2b(v, length: remaining)
}

// MARK: - BLAKE2b (RFC 7693), unkeyed, 1 to 64 bytes out

private let blake2bIV: [UInt64] = [
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
]

private let sigma: [[Int]] = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
]

// ponytail: plain arrays, not pointers; Argon2 only hashes a few KiB through this, the blocks go through `compress`.
func blake2b(_ input: [UInt8], length: Int) -> [UInt8] {
    precondition(1...64 ~= length)
    var h = blake2bIV
    h[0] ^= 0x0101_0000 ^ UInt64(length)
    var offset = 0
    var counter: UInt64 = 0
    while input.count - offset > 128 {
        counter += 128
        blake2bCompress(&h, Array(input[offset..<offset + 128]), counter: counter, last: false)
        offset += 128
    }
    var block = Array(input[offset...])
    counter += UInt64(block.count)
    block += [UInt8](repeating: 0, count: 128 - block.count)
    blake2bCompress(&h, block, counter: counter, last: true)

    var out = [UInt8]()
    for word in h { out.appendLE64(word) }
    return Array(out[0..<length])
}

private func blake2bCompress(_ h: inout [UInt64], _ block: [UInt8], counter: UInt64, last: Bool) {
    let m = block.withUnsafeBytes { raw in
        (0..<16).map { UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self)) }
    }
    var v = h + blake2bIV
    v[12] ^= counter
    if last { v[14] = ~v[14] }

    func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
        v[a] = v[a] &+ v[b] &+ x; v[d] = rotr(v[d] ^ v[a], 32)
        v[c] = v[c] &+ v[d];      v[b] = rotr(v[b] ^ v[c], 24)
        v[a] = v[a] &+ v[b] &+ y; v[d] = rotr(v[d] ^ v[a], 16)
        v[c] = v[c] &+ v[d];      v[b] = rotr(v[b] ^ v[c], 63)
    }
    for round in 0..<12 {
        let s = sigma[round % 10]
        g(0, 4, 8, 12, m[s[0]], m[s[1]]); g(1, 5, 9, 13, m[s[2]], m[s[3]])
        g(2, 6, 10, 14, m[s[4]], m[s[5]]); g(3, 7, 11, 15, m[s[6]], m[s[7]])
        g(0, 5, 10, 15, m[s[8]], m[s[9]]); g(1, 6, 11, 12, m[s[10]], m[s[11]])
        g(2, 7, 8, 13, m[s[12]], m[s[13]]); g(3, 4, 9, 14, m[s[14]], m[s[15]])
    }
    for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
}

private extension [UInt8] {
    mutating func appendLE32(_ n: UInt32) { Swift.withUnsafeBytes(of: n.littleEndian) { append(contentsOf: $0) } }
    mutating func appendLE64(_ n: UInt64) { Swift.withUnsafeBytes(of: n.littleEndian) { append(contentsOf: $0) } }
}
