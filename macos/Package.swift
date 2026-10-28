// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Stillroom",
    platforms: [.macOS("26.0")],
    targets: [
        // The Argon2 reference C, unchanged (see Sources/CArgon2/README.md). Optimized even in debug builds, where an
        // unoptimized stretch takes many seconds per unlock.
        .target(name: "CArgon2", cSettings: [.unsafeFlags(["-O3", "-w"])]),
        .executableTarget(name: "Stillroom", dependencies: ["CArgon2"]),
        .testTarget(name: "StillroomTests", dependencies: ["Stillroom"]),
    ]
)
