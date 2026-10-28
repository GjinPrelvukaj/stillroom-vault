import AppKit
import Testing
@testable import Stillroom

/// An iPhone sketch (a PencilKit drawing) comes out as a PNG on white, with its dark ink still dark.
@MainActor @Test func sketchesBecomePicturesOnWhite() throws {
    // A real drawing (one black pen stroke), made once by a small tool: building one here would need an app identity
    // PencilKit insists on, which a test run doesn't have.
    let data = try #require(Data(base64Encoded: "d3Jk8AEACAASEAAAAAAAAAAAAAAAAAAAAAASEArc8v3ur06Kkas0DpMotqEaBggAEAAYABoGCAEQARgBIjQKFA0AAAAAFQAAAAAdAAAAACUAAIA/EhFjb20uYXBwbGUuaW5rLnBlbhgDQQAAAAAAAAAAKtUGChCgQeHjRQtEtpLs5LkfDw/6EgYIABABGAEaBggAEAEYACAAKpEGChDhwh+mZG9K5KJZslom0He/EYO+UhQdRshBGDwgAyj8HzIaAAAAQegDAADoA/9/AAD/fwAAAEEAAAAAAAA60AUAACBCAADwQgAAAAAAADhCKvQBQ4mIiDwAAFBCtqELQ4mICD0AAGhC+sMUQ83MTD0AAIBCKRodQ4mIiD0AAIxCHmkkQ6uqqj0AAJhC/3wqQ83MzD0AAKRCrSovQ+/u7j0AALBC91AyQ4mICD4AALxChtkzQ5qZGT4AAMhCd7kzQ6uqKj4AANRCr/ExQ7y7Oz4AAOBCz44uQ83MTD4AAOxC3agpQ97dXT4AAPhCmWIjQ+/ubj4AAAJDiOgbQwAAgD4AAAhDtW8TQ4mIiD4AAA5DOzQKQxERkT4AABRDmncAQ5qZmT4AABpDz/3sQiIioj4AACBDwSHZQquqqj4AACZD8OfFQjMzsz4AACxDxdizQry7uz4AADJDXnSjQkRExD4AADhDBy+VQs3MzD4AAD5DAG6JQlVV1T4AAERDrYSAQt7d3T4AAEpDjWR1QmZm5j4AAFBDNkBwQu/u7j4AAFZDz8BxQnd39z4AAFxDsdt5QgAAAD8AAGJDrSuEQkREBD8AAGhDhWaOQomICD8AAG5DzVWbQs3MDD8AAHRDwJ2qQhERET8AAHpD9NG7QlVVFT8AAIBDW3jOQpqZGT8AAINDpAziQt7dHT8AAIZD5wP2QiIiIj8AAIlDPugEQ2ZmJj8AAIxD93IOQ6uqKj8AAI9Dal4XQ+/uLj8AAJJDUGsfQzMzMz8AAJVDjGAmQ3d3Nz8AAJhDwAwsQ7y7Oz8AAJtDrkcwQwAAQD8AAJ5DUvMyQ0RERD8AAKFDuvwzQ4mISD8AAKRDi1wzQ83MTD8AAKdDNhcxQxERUT8AAKpD1jwtQ1VVVT8AAK1Dw+gnQ5qZWT8AALBDyUAhQ97dXT8AALNDInQZQyIiYj8AALZDJLoQQ2ZmZj8AALlDt1AHQ6uqaj8AALxDRPX6Qu/ubj8AAL9DXPvmQjMzcz8AAMJDbkHTQnd3dz8AAMVDb1PAQry7ez8yFA0AAARCFQAAWEIdAAC4QyUAAARDQKCngfbfBDoGCAAQABgAQhATA9jccBtJYKOGI/9mRZFX"))

    #expect(Sketch.isSketch(uti: "public.data", name: "Scan 2026.drawing"))
    let png = try #require(Sketch.png(from: data))
    let bitmap = try #require(NSBitmapImageRep(data: png))
    let corner = try #require(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
    #expect(corner.brightnessComponent > 0.95)
    let darkest = (0..<bitmap.pixelsWide).compactMap { bitmap.colorAt(x: $0, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)?.brightnessComponent }.min() ?? 1
    #expect(darkest < 0.3)
    #expect(Sketch.png(from: Data("not a drawing".utf8)) == nil)
}
