import AppKit
import SwiftUI

/// Who tried to get in: each wrong password or recovery key typed at the lock screen, when, and a photo when the
/// camera allowed one. Both vaults show the same log, and only once open.
struct IntruderView: View {
    let state: AppState
    @State private var entries: [IntruderLog.Entry] = []
    @State private var enlarged: IntruderLog.Entry?
    @State private var clearing = false
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Kit.Space.label) {
                    Text("Intruder log").eyebrow()
                    Text(entries.isEmpty ? "No one has tried" : "\(entries.count) wrong \(entries.count == 1 ? "try" : "tries")")
                        .font(Kit.title)
                }
                Spacer()
                if !entries.isEmpty { Button("Clear All…") { clearing = true }.buttonStyle(.secondary) }
            }
            Text("Your own typos show here too. Only your open vault can read this log.")
                .font(Kit.quiet).opacity(0.45)
            if entries.isEmpty {
                VStack(spacing: Kit.Space.group) {
                    Image(systemName: "person.badge.shield.checkmark").font(.system(size: 34, weight: .light)).opacity(0.5)
                    Text("Every wrong password typed at the lock screen will be listed here, with a photo when the camera is allowed.")
                        .font(Kit.body).opacity(0.5).multilineTextAlignment(.center).frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            if entry.id != entries.first?.id { Rectangle().fill(Color.ink.opacity(0.05)).frame(height: 1) }
                            row(entry)
                        }
                    }
                    .rowPanel()
                }
                .scrollIndicators(.never)
            }
        }
        .pane(wide: true)
        .entrance(ready: loaded)
        .task {
            entries = state.intruderEntries()
            UserDefaults.standard.set(entries.count, forKey: "intrudersSeen")
            loaded = true
        }
        .sheet(item: $enlarged) { entry in
            VStack(spacing: Kit.Space.group) {
                if let photo = entry.photo, let image = NSImage(data: photo) {
                    Image(nsImage: image).resizable().scaledToFit().mirrored().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack {
                    Text(entry.date.formatted(date: .long, time: .standard)).font(Kit.quiet).opacity(0.5)
                    Spacer()
                    Button("Done") { enlarged = nil }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
                }
            }
            .padding(Kit.Space.edge)
            .frame(width: 560)
            .background(Color.ground)
            .hiddenFromCapture()
        }
        .confirmationDialog("Clear the intruder log?", isPresented: $clearing) {
            Button("Clear All", role: .destructive) { state.clearIntruders(); entries = [] }
        } message: {
            Text("Every entry and photo goes for good.")
        }
    }

    private func row(_ entry: IntruderLog.Entry) -> some View {
        HStack(spacing: Kit.Space.group) {
            Group {
                if let photo = entry.photo, let image = NSImage(data: photo) {
                    Button { enlarged = entry } label: {
                        Image(nsImage: image).resizable().scaledToFill().mirrored().frame(width: 64, height: 48).clipped()
                    }
                    .buttonStyle(.plain)
                    .help("Show the photo")
                } else {
                    Image(systemName: "camera.slash").opacity(0.35).frame(width: 64, height: 48)
                        .background(Color.ink.opacity(0.04))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.kind == .wrongPassword ? "Wrong password" : "Wrong recovery key").font(Kit.body)
                Text(entry.date.formatted(date: .abbreviated, time: .standard)).font(Kit.quiet).opacity(0.45)
            }
            Spacer()
            Button { state.deleteIntruder(entry.id); entries.removeAll { $0.id == entry.id } } label: { Image(systemName: "trash") }
                .buttonStyle(.quiet)
                .help("Delete this entry")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Settings for the intruder log, kept with the app's other preferences.
enum IntruderSettings {
    static var takesPhoto: Bool { UserDefaults.standard.object(forKey: "intruderPhoto") as? Bool ?? true }

    /// Logs a wrong try at the lock screen, with a photo (if allowed and on). What was typed is never kept.
    static func record(_ kind: IntruderLog.Kind) {
        let photo = takesPhoto
        Task.detached(priority: .userInitiated) {
            let picture = photo ? await IntruderCamera.snap() : nil
            try? IntruderLog.record(kind: kind, photo: picture)
        }
    }
}

private extension View {
    /// The camera's photo as a mirror shows a face, the way the person saw themselves.
    func mirrored() -> some View { scaleEffect(x: -1, y: 1) }
}
