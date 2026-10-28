import PencilKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: Sketches

/// A sketch from the iPhone (Continuity Camera's Add Sketch) arrives as a PencilKit drawing, which nothing else on
/// the Mac shows. It's drawn here as a picture: dark ink on white, as it looked on the phone.
enum Sketch {
    static let type = UTType("com.apple.drawing")

    static func isSketch(uti: String, name: String) -> Bool {
        uti == type?.identifier || (name as NSString).pathExtension.lowercased() == "drawing"
    }

    /// The drawing as a PNG on white, or nil when the bytes aren't a drawing.
    static func png(from data: Data) -> Data? {
        guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return nil }
        let area = drawing.bounds.insetBy(dx: -24, dy: -24)
        var png: Data?
        // Light appearance, so black ink stays black instead of turning white for dark mode.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            let ink = drawing.image(from: area, scale: 2)
            let size = NSSize(width: area.width * 2, height: area.height * 2)
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            ink.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            png = bitmap.representation(using: .png, properties: [:])
        }
        return png
    }
}

// MARK: Email

/// An email as Mail shows it: who, when, the subject, its attachments, then the message itself. The message is drawn
/// with scripts off and nothing allowed to load from the network, so opening it can't tell the sender (no tracking
/// pixels, no remote pictures) and links don't open.
struct EmailView: View {
    let data: Data
    /// Seal an attachment into the vault as a file of its own.
    let keep: (Email.Attachment) -> Void
    /// Save an attachment out, unencrypted.
    let save: (Email.Attachment) -> Void
    @State private var email: Email?
    /// The page as shown, built with the email off the main thread rather than on every redraw.
    @State private var page = ""
    @State private var unreadable = false

    var body: some View {
        Group {
            if let email {
                VStack(alignment: .leading, spacing: 0) {
                    header(email)
                    MailPage(html: page)
                }
            } else if unreadable {
                ScrollView {
                    Text(String(decoding: data, as: UTF8.self)).font(.system(size: 12, design: .monospaced)).opacity(0.85)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(Kit.Space.group)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task {
            let data = data
            let parsed = await ActivityLog.timed("email read") {
                await Task.detached(priority: .userInitiated) { Email.parse(data).map { ($0, $0.page()) } }.value
            }
            page = parsed?.1 ?? ""
            email = parsed?.0
            unreadable = parsed == nil
        }
    }

    private func header(_ email: Email) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(email.subject.isEmpty ? "No subject" : email.subject)
                .font(.system(size: 15, weight: .semibold)).lineLimit(2).textSelection(.enabled).padding(.bottom, 3)
            line("From", email.from)
            line("To", email.to)
            line("Cc", email.cc)
            if let date = email.date { line("Date", date.formatted(date: .long, time: .shortened)) }
            if !email.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(email.attachments) { attachment in
                            Menu {
                                Button("Add to Stillroom") { keep(attachment) }
                                Button("Save a Copy…") { save(attachment) }
                            } label: {
                                Label("\(attachment.name) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))",
                                      systemImage: "paperclip")
                                    .font(Kit.quiet).lineLimit(1)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.secondary)
                            .fixedSize()
                        }
                    }
                }
                .scrollIndicators(.never)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Kit.Space.group)
    }

    @ViewBuilder private func line(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(Kit.quiet).opacity(0.45).frame(width: 40, alignment: .leading)
                Text(value).font(Kit.quiet).opacity(0.8).lineLimit(2).textSelection(.enabled)
            }
        }
    }
}

/// The message's own page in WebKit, locked down three ways: scripts off, a content policy that allows only what is
/// inside the message itself (data: pictures, inline styles), and a WebKit block list for any other load. Nothing is
/// kept between messages (no cookies, no cache).
struct MailPage: NSViewRepresentable {
    let html: String

    static let policy = """
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline' data:; \
        font-src data:; media-src data:; form-action 'none'">
        <meta http-equiv="x-dns-prefetch-control" content="off">
        """
    static let rules = """
        [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},
         {"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}}]
        """

    func makeCoordinator() -> Guard { Guard() }

    func makeNSView(context: Context) -> WKWebView {
        let view = Self.lockedView(context.coordinator)
        Task { await Self.show(html, in: view, context.coordinator) }
        return view
    }

    /// A web view that can't run scripts, keep data or open windows. The test that no email reaches the network
    /// (`MailLockdownTests`) builds the very same one.
    static func lockedView(_ guard: Guard) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = `guard`
        view.allowsLinkPreview = false
        return view
    }

    /// The message, shown only once the block list is on; without it, nothing is shown (WebKit once rejected a rule
    /// here, silently, and the page went out with one lock fewer). Before <html>, the policy lands in the page's head
    /// however the message is written. Returns whether it was shown.
    @discardableResult
    static func show(_ html: String, in view: WKWebView, _ guard: Guard) async -> Bool {
        do {
            let list = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "app.gjin.stillroom.mail", encodedContentRuleList: rules)
            guard let list else { throw VaultError.damaged }
            view.configuration.userContentController.add(list)
        } catch {
            _ = ActivityLog.failed(error, "email block list")
            return false
        }
        `guard`.loaded = true
        view.loadHTMLString(policy + disarmed(html), baseURL: nil)
        return true
    }

    /// `<link>` tags shown as text: preconnect and prefetch links open connections the page policy doesn't cover,
    /// and an email has no other use for them (its stylesheets are blocked anyway). Turning the "<" that would start
    /// one into "&lt;" means no link element can be formed, however the rest of the tag is written.
    static func disarmed(_ html: String) -> String {
        html.replacing(/<(?=link[\s\/>])/.ignoresCase(), with: "&lt;")
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    /// Lets the message itself load, and nothing after it: a clicked link goes nowhere.
    @MainActor final class Guard: NSObject, WKNavigationDelegate {
        var loaded = false
        private var shown = false

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard loaded, !shown, action.navigationType == .other, action.request.url?.scheme == "about",
                  action.targetFrame?.isMainFrame == true else { return .cancel }
            shown = true
            return .allow
        }
    }
}

// MARK: Quick Look

/// Any other kind of file, drawn by the Mac's own Quick Look from a copy on Vault's RAM disk: Word, Pages, Keynote,
/// Excel, 3D models, fonts and the rest. Each previewer runs in Apple's own sandbox, apart from Stillroom. The copy is
/// deleted when the card shuts.
struct QuickLookView: View {
    let file: VaultFile
    let stage: () async throws -> URL
    let unstage: () -> Void
    @State private var url: URL?
    @State private var failed: String?

    /// The biggest file put out for a look: half the RAM disk, so it fits beside files being edited. Past this,
    /// editing in place or a copy is the way.
    static let largest = 512 << 20

    var body: some View {
        Group {
            if let url {
                QuickLookPane(url: url)
            } else if let failed {
                VStack(spacing: Kit.Space.label) {
                    Image(systemName: file.symbol).font(.system(size: 28, weight: .light)).opacity(0.45).padding(.bottom, 4)
                    Text("Couldn't show it").font(Kit.body)
                    Text(failed).font(Kit.quiet).opacity(0.45).multilineTextAlignment(.center).frame(maxWidth: 380)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task {
            ActivityLog.note("quick look: putting out a copy")
            do {
                let staged = try await stage()
                // Closed while the desk was mounting: onDisappear found nothing to delete, so the copy goes here.
                if Task.isCancelled { unstage(); return }
                url = staged
                ActivityLog.note("quick look: showing", action: false)
            } catch {
                failed = error.localizedDescription
                ActivityLog.note("quick look: failed (\(type(of: error)))")
            }
        }
        .onDisappear {
            ActivityLog.note("quick look: closed")
            unstage()
        }
    }
}

private struct QuickLookPane: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {}

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}
