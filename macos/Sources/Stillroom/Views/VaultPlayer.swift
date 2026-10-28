import AVFoundation
import AVKit
import CryptoKit
import SwiftUI

/// Plays a sealed video or song straight from the vault: AVPlayer asks for byte ranges on a made-up URL scheme,
/// and each is opened from the sealed blob as it's asked for. Nothing unsealed is ever written to disk.
struct VaultPlayer: NSViewRepresentable {
    let url: URL
    let key: SymmetricKey
    let fileID: UUID
    let plainSize: Int
    let uti: String

    final class Coordinator {
        var fileID: UUID?
        var loader: VaultStreamLoader?
        let player = AVPlayer()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.player = context.coordinator.player
        load(into: context.coordinator)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        // The same view can be handed another file; it must not keep playing the old one.
        if context.coordinator.fileID != fileID { load(into: context.coordinator) }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.player.replaceCurrentItem(with: nil)
        view.player = nil
        coordinator.loader = nil
    }

    private func load(into coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.fileID = fileID
        guard let reader = try? ChunkedReader(url: url, key: key, fileID: fileID, plainSize: plainSize) else {
            coordinator.player.replaceCurrentItem(with: nil)
            coordinator.loader = nil
            return
        }
        let loader = VaultStreamLoader(reader: reader, uti: uti)
        coordinator.loader = loader
        coordinator.player.replaceCurrentItem(with: AVPlayerItem(asset: loader.asset))
    }
}

/// Answers AVFoundation's requests for a sealed file's bytes. The asset holds this only weakly, so whoever plays
/// the asset keeps this alive.
final class VaultStreamLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let asset: AVURLAsset
    private let reader: ChunkedReader
    private let uti: String
    private let queue = DispatchQueue(label: "vault-stream")

    init(reader: ChunkedReader, uti: String) {
        self.reader = reader
        self.uti = uti
        // A scheme AVFoundation doesn't know, so it has to ask the delegate instead of opening the URL itself.
        asset = AVURLAsset(url: URL(string: "vault-stream://file/\(UUID().uuidString)")!)
        super.init()
        asset.resourceLoader.setDelegate(self, queue: queue)
    }

    deinit { asset.cancelLoading() }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        if let info = request.contentInformationRequest {
            info.contentType = uti
            info.contentLength = Int64(reader.plainSize)
            info.isByteRangeAccessSupported = true
        }
        // Served off the delegate queue, so a long read never holds up the next request or a cancel.
        let box = Box(request)
        DispatchQueue.global(qos: .userInitiated).async { [reader] in Self.serve(box.request, from: reader) }
        return true
    }

    private static func serve(_ request: AVAssetResourceLoadingRequest, from reader: ChunkedReader) {
        guard let data = request.dataRequest else { request.finishLoading(); return }
        var offset = Int(data.currentOffset)
        let end = data.requestsAllDataToEndOfResource
            ? reader.plainSize : min(reader.plainSize, Int(data.requestedOffset) + data.requestedLength)
        do {
            // A chunk at a time, so a seek that cancels this request stops it within a chunk.
            while offset < end, !request.isCancelled {
                let piece = try reader.read(offset..<min(end, offset + reader.chunkSize - offset % reader.chunkSize))
                guard !piece.isEmpty else { break }
                data.respond(with: piece)
                offset += piece.count
            }
            if !request.isCancelled { request.finishLoading() }
        } catch {
            if !request.isCancelled { request.finishLoading(with: error) }
        }
    }

    /// AVFoundation's requests aren't marked Sendable, but each is only touched by the one job serving it.
    private struct Box: @unchecked Sendable { let request: AVAssetResourceLoadingRequest; init(_ r: AVAssetResourceLoadingRequest) { request = r } }
}
