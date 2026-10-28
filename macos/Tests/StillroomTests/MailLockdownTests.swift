import Foundation
import Network
import Testing
import WebKit
@testable import Stillroom

/// The one part of Stillroom that could reach the internet is the email viewer: emails are full of remote images and
/// trackers. A hostile email, every kind of remote load in it pointed at a server on this Mac, must make no
/// connection at all.
@MainActor @Test func anEmailCantReachTheNetwork() async throws {
    let server = try LocalServer()
    defer { server.stop() }
    try await server.ready()

    // The server answers, so a zero below means blocked, not unreachable.
    _ = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/control")!)
    #expect(server.connections == 1)

    let page = MailPage.hostile(port: server.port)
    let guardian = MailPage.Guard()
    let view = MailPage.lockedView(guardian)
    #expect(await MailPage.show(page, in: view, guardian), "the block list didn't compile")

    // The message itself shows (its title is read back), then time for anything it pulls in.
    let shown = ContinuousClock.now
    while view.title != "lockdown", ContinuousClock.now - shown < .seconds(15) { try await Task.sleep(for: .milliseconds(50)) }
    #expect(view.title == "lockdown")
    try await Task.sleep(for: .seconds(3))
    #expect(server.connections == 1, "the email reached the server: \(server.requests.dropFirst())")
}

extension MailPage {
    /// Every way HTML and CSS can load something, at two names for this Mac.
    static func hostile(port: UInt16) -> String {
        let hosts = ["http://127.0.0.1:\(port)", "http://localhost:\(port)"]
        let loads = hosts.map { h in
            """
            <img src="\(h)/img"><img srcset="\(h)/srcset 2x"><picture><source srcset="\(h)/picture"></picture>
            <link rel="stylesheet" href="\(h)/css"><link rel="prefetch" href="\(h)/prefetch">
            <link rel="preconnect" href="\(h)"><link rel="dns-prefetch" href="\(h)"><link rel="icon" href="\(h)/icon">
            <style>@import url(\(h)/import); body { background: url(\(h)/background) }
            @font-face { font-family: remote; src: url(\(h)/font) } p { font-family: remote }</style>
            <p style="background-image: url(\(h)/inline)">text</p>
            <iframe src="\(h)/frame"></iframe><script src="\(h)/script"></script>
            <video poster="\(h)/poster" src="\(h)/video" autoplay></video><audio src="\(h)/audio" autoplay></audio>
            <object data="\(h)/object"></object><embed src="\(h)/embed">
            <form action="\(h)/form"><input type="image" src="\(h)/input"></form>
            <svg><image href="\(h)/svg" width="10" height="10"/></svg>
            """
        }
        return """
            <html><head><title>lockdown</title><meta http-equiv="refresh" content="0;url=\(hosts[0])/refresh">
            <base href="\(hosts[0])/base/"></head><body><img src="relative.png">\(loads.joined())</body></html>
            """
    }
}

/// A server on a free port of this Mac that only counts who connects.
private final class LocalServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var count = 0
    private var asked: [String] = []
    /// The first line of each request: which load got through.
    var requests: [String] { lock.withLock { asked } }
    private var started: CheckedContinuation<Void, Error>?

    var connections: Int { lock.withLock { count } }
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            lock.withLock { count += 1 }
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                let line = data.flatMap { String(data: $0, encoding: .utf8)?.components(separatedBy: "\r\n").first } ?? "?"
                self.lock.withLock { self.asked.append(line) }
            }
            let reply = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    func ready() async throws {
        try await withCheckedThrowingContinuation { continuation in
            started = continuation
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.started?.resume(); self?.started = nil
                case .failed(let error): self?.started?.resume(throwing: error); self?.started = nil
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    func stop() { listener.cancel() }
}
