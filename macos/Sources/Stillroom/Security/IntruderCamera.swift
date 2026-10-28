import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo of whoever is at the Mac, for the intruder log.
///
/// The camera's green light comes on for the second or so this takes: macOS shows it, by design, and nothing can
/// hide it. The app bundle needs `NSCameraUsageDescription` in its Info.plist (or macOS kills it on first use) and,
/// under the hardened runtime, the entitlement `com.apple.security.device.camera` (or every frame comes back black
/// or the device is refused).
enum IntruderCamera {
    static var allowed: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    static var undecided: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined }

    /// Asks macOS for the camera, with the vault open, so the owner answers.
    static func ask() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    /// One JPEG from the Mac's camera, or nil if there's no camera, permission is denied or it takes more than ~3 s.
    /// Never throws, never blocks the main thread.
    static func snap() async -> Data? {
        guard AVCaptureDevice.default(for: .video) != nil else { return nil }
        // Never asks: the question would go to whoever is at the lock screen. You allow it, unlocked, with ask().
        guard allowed else { return nil }
        return await withCheckedContinuation { continuation in
            let shot = Shot(continuation)
            // startRunning blocks for a while, so it never runs on the caller's thread.
            DispatchQueue.global(qos: .userInitiated).async { shot.start() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { shot.finish(nil) }
        }
    }

    /// One capture from start to stop. Whichever comes first, the photo or the time limit, finishes it; the other is ignored.
    private final class Shot: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data?, Never>?
        private let session = AVCaptureSession()
        private let output = AVCapturePhotoOutput()

        init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }

        func start() {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input),
                  session.canAddOutput(output) else { return finish(nil) }
            session.beginConfiguration()
            session.sessionPreset = .photo
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
            // The time limit may have passed while it started: then the camera goes straight off again.
            guard isWaiting else { return session.stopRunning() }
            // A cold camera's first frames are black or badly exposed; give it a moment to settle.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.8) { [self] in
                guard isWaiting else { return }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            finish(photo.fileDataRepresentation().flatMap(Self.smallJPEG))
        }

        private var isWaiting: Bool { lock.withLock { continuation != nil } }

        func finish(_ data: Data?) {
            let waiting = lock.withLock { () -> CheckedContinuation<Data?, Never>? in
                defer { continuation = nil }
                return continuation
            }
            guard let waiting else { return }
            session.stopRunning()
            waiting.resume(returning: data)
        }

        /// At most 1280 px on the long side, JPEG at 0.7: a face is clear, the log stays small.
        private static func smallJPEG(_ data: Data) -> Data? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1280,
                  ] as CFDictionary) else { return nil }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
            return CGImageDestinationFinalize(dest) ? out as Data : nil
        }
    }
}
