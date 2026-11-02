import AppKit
import SwiftUI

/// A note, open: its title and text, saved as you type (a moment after you stop), encrypted like any file.
struct NoteEditor: View {
    let state: AppState
    let file: VaultFile
    let back: () -> Void
    let versions: () -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var loaded = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            EditorBar(back: back, backTitle: "Notes", file: file, versions: versions)
            EditorHeader(id: file.id, kind: "Note", symbol: "note.text", title: $title, hint: "Title")
            // Room round the words and a column no wider than reads easily, inside a panel that still fills the page.
            TextEditor(text: $text)
                .font(Kit.reading)
                .scrollContentBackground(.hidden)
                .lineSpacing(5)
                .frame(maxWidth: Kit.measure, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowPanel()
        }
        .entrance(ready: loaded)
        .task {
            title = file.name
            text = (try? state.read(file)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            loaded = true
        }
        .onChange(of: text) { schedule() }
        .onChange(of: title) { schedule() }
        // Leaving saves at once, rather than waiting out the pause.
        .onDisappear { flush() }
    }

    private func schedule() {
        guard loaded else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        guard loaded else { return }
        pending?.cancel()
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled note" : title
        let current = state.files.first { $0.id == file.id }
        let data = Data(text.utf8)
        // Nothing changed: nothing written, no version made.
        if current?.name == name, let current, (try? state.read(current)) == data { return }
        state.update(file.id, with: data, name: name)
    }
}

/// A secret, open: its fields, each labelled. Concealed values show as ten dots, whatever their length, until the eye
/// is pressed or they're clicked to type in, and copy to a
/// clipboard that other apps' history managers are asked to skip and that empties itself after 30 seconds.
struct SecretEditor: View {
    let state: AppState
    let file: VaultFile
    let back: () -> Void
    let versions: () -> Void
    @State private var title = ""
    @State private var secret = Secret(template: .other)
    @State private var loaded = false
    @State private var shown: Set<UUID> = []
    /// The concealed field clicked to type in: a secure field until focus leaves it, then the mask again.
    @State private var editing: UUID?
    @FocusState private var focused: UUID?
    @State private var copied: UUID?
    @State private var copiedAt = Date.distantPast
    @State private var pending: Task<Void, Never>?
    /// A line in place of the copied one, about the two-factor setup just added or not found.
    @State private var note: String?
    /// A QR screenshot just read from a file, offered to the Trash.
    @State private var screenshot: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            EditorBar(back: back, backTitle: "Secrets", file: file, versions: versions)
            EditorHeader(id: file.id, kind: secret.template.title, symbol: secret.template.symbol, title: $title, hint: "Name")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($secret.fields) { $field in
                        if field.id != secret.fields.first?.id { Rectangle().fill(Color.ink.opacity(0.05)).frame(height: 1) }
                        row($field)
                        if let code = field.oneTimeCode { OneTimeCodeRow(code: code, copied: $copied, id: field.id) }
                    }
                }
                .rowPanel()
                HStack {
                    Button { secret.fields.append(.init(label: "New field")) } label: { Label("Add Field", systemImage: "plus") }
                        .buttonStyle(.quiet)
                    Button { secret.fields.append(.init(label: "Password", concealed: true)) } label: {
                        Label("Add Password", systemImage: "key")
                    }
                    .buttonStyle(.quiet)
                    Menu {
                        Button("Type or Paste the Setup Key") { addTwoFactor("") }
                        Button("Read QR Code from Clipboard", action: readQRFromClipboard)
                        Button("Read QR Code from a Screenshot…", action: readQRFromFile)
                    } label: {
                        Label("Add Two-Factor", systemImage: "clock.badge.checkmark")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.quiet)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    Spacer()
                }
                .padding(.top, Kit.Space.item)
            }
            .scrollIndicators(.never)
            if let note {
                Text(note).font(Kit.quiet).quietText().transition(.opacity)
            } else if copied != nil {
                Text("Copied. The clipboard empties itself in 30 seconds.").font(Kit.quiet).quietText().transition(.opacity)
            }
        }
        .animation(Motion.change, value: copied)
        .animation(Motion.change, value: note)
        .confirmationDialog("Move the screenshot to the Trash?", isPresented: .init(get: { screenshot != nil }, set: { if !$0 { screenshot = nil } })) {
            Button("Move to Trash") {
                if let screenshot { NSWorkspace.shared.recycle([screenshot]) }
                screenshot = nil
            }
            Button("Keep It", role: .cancel) { screenshot = nil }
        } message: {
            Text("It holds the same two-factor secret, unencrypted. Empty the Trash afterwards.")
        }
        .entrance(ready: loaded)
        .task {
            title = file.name
            if let data = try? state.read(file), let decoded = try? JSONDecoder().decode(Secret.self, from: data) {
                secret = decoded
            }
            loaded = true
        }
        .onChange(of: secret) { schedule() }
        // Focus left the field being typed in: back to the mask.
        .onChange(of: focused) { if focused != editing { editing = nil } }
        .onChange(of: title) { schedule() }
        .onDisappear { flush() }
    }

    private func row(_ field: Binding<Secret.Field>) -> some View {
        let id = field.wrappedValue.id
        let visible = !field.wrappedValue.concealed || shown.contains(id)
        // Hidden and not being typed in: a fixed mask, never as many dots as the value has characters.
        let masked = !visible && editing != id && !field.wrappedValue.value.isEmpty
        return HStack(spacing: Kit.Space.item) {
            TextField("Label", text: field.label)
                .textFieldStyle(.plain)
                .font(Kit.quiet)
                .quietText()
                .frame(width: 130, alignment: .leading)
            Group {
                if masked {
                    let twoFactor = field.wrappedValue.oneTimeCode != nil
                    Button { editing = id } label: {
                        Text(field.wrappedValue.mask)
                            .font(twoFactor ? Kit.body : Kit.body.monospaced())
                            .foregroundStyle(twoFactor ? Color.quietInk : Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Click to type a new one; the eye shows it")
                    .accessibilityLabel("\(field.wrappedValue.label), hidden")
                } else if visible {
                    TextField("Empty", text: field.value).focused($focused, equals: id)
                } else {
                    SecureField("Empty", text: field.value)
                        .focused($focused, equals: id)
                        .onAppear { if editing == id { DispatchQueue.main.async { focused = id } } }
                }
            }
            .textFieldStyle(.plain)
            .font(field.wrappedValue.concealed ? Kit.body.monospaced() : Kit.body)
            if field.wrappedValue.concealed {
                icon(visible ? "eye.slash" : "eye", help: visible ? "Hide" : "Show") {
                    if visible { shown.remove(id) } else { shown.insert(id) }
                }
                if field.wrappedValue.takesGeneratedPassword {
                    icon("dice", help: "Make a strong random password") {
                        field.wrappedValue.value = generatedPassword()
                        shown.insert(id)
                    }
                }
            }
            Button {
                Clipboard.copy(field.wrappedValue.value, concealed: field.wrappedValue.concealed)
                let at = Date.now
                copied = id
                copiedAt = at
                Task {
                    try? await Task.sleep(for: .seconds(Clipboard.life))
                    if copied == id, copiedAt == at { copied = nil }
                }
            } label: { ClipboardMark(since: copied == id ? copiedAt : nil) }
                .buttonStyle(.icon)
                .help("Copy")
                .accessibilityLabel("Copy")
                .disabled(field.wrappedValue.value.isEmpty)
            Menu {
                Toggle("Concealed", isOn: field.concealed)
                Button("Remove Field", role: .destructive) { secret.fields.removeAll { $0.id == id } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.icon)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private func icon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).contentTransition(.symbolEffect(.replace)) }
            .buttonStyle(.icon)
            .help(help)
            .accessibilityLabel(help)
    }

    /// A two-factor field, concealed: the setup key is as secret as the password.
    private func addTwoFactor(_ value: String) {
        secret.fields.append(.init(label: "Two-factor setup", value: value, concealed: true))
        say(value.isEmpty ? "Paste the setup key or otpauth link the website shows under its QR code." : "Two-factor added. The code below changes every 30 seconds.")
    }

    private func readQRFromClipboard() {
        let board = NSPasteboard.general
        guard let image = NSImage(pasteboard: board)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let link = OneTimeCode.fromQR(in: image) else {
            say("No two-factor QR code on the clipboard. Take a screenshot of it with ⇧⌃⌘4 first.")
            return
        }
        addTwoFactor(link)
        // The picture holds the secret too.
        board.clearContents()
    }

    private func readQRFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose the screenshot of the website's two-factor QR code."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let link = OneTimeCode.fromQR(in: image) else {
            say("No two-factor QR code found in that picture.")
            return
        }
        addTwoFactor(link)
        screenshot = url
    }

    private func say(_ text: String) {
        note = text
        Task {
            try? await Task.sleep(for: .seconds(6))
            if note == text { note = nil }
        }
    }

    private func schedule() {
        guard loaded else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        guard loaded, let data = try? JSONEncoder().encode(secret) else { return }
        pending?.cancel()
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? secret.template.title : title
        let current = state.files.first { $0.id == file.id }
        if current?.name == name, let current, let old = try? state.read(current),
           (try? JSONDecoder().decode(Secret.self, from: old)) == secret { return }
        state.update(file.id, with: data, name: name)
    }
}

/// Under a two-factor setup: the code the website asks for now, the seconds it has left, and a copy button.
private struct OneTimeCodeRow: View {
    let code: OneTimeCode
    @Binding var copied: UUID?
    let id: UUID
    @State private var done: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = code.code(at: context.date)
            let left = code.secondsLeft(at: context.date)
            HStack(spacing: Kit.Space.item) {
                Text("Code").font(Kit.quiet).quietText().frame(width: 130, alignment: .leading)
                // Split in half, as authenticator apps show it: easier to read off and type.
                Text(now.prefix(now.count / 2) + " " + now.dropFirst(now.count / 2))
                    .font(Kit.figure.monospaced())
                    // Always Vault's colour (orange means a protection is off); the last seconds only dim it.
                    .foregroundStyle(Color.vault)
                    .opacity(left <= 3 ? 0.6 : 1)
                    .contentTransition(.numericText())
                    .textSelection(.disabled)
                    .accessibilityLabel("Code \(now.map(String.init).joined(separator: " "))")
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(Color.track, lineWidth: 2)
                    // One smooth sweep per period, not a step a second.
                    TimelineView(.animation(minimumInterval: 1 / 30)) { frame in
                        let period = Double(code.period)
                        let rest = period - frame.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
                        Circle().trim(from: 0, to: rest / period)
                            .stroke(Color.vault, style: .init(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Text("\(left)").font(Kit.micro).quietText()
                }
                .frame(width: 20, height: 20)
                .help("Seconds until the code changes")
                .accessibilityLabel("\(left) seconds left")
                Button {
                    Clipboard.copy(code.code(), concealed: true)
                    let at = Date.now, mine = UUID()
                    done = at
                    copied = mine
                    Task {
                        try? await Task.sleep(for: .seconds(Clipboard.life))
                        if done == at { done = nil }
                        if copied == mine { copied = nil }
                    }
                } label: { ClipboardMark(since: done) }
                    .buttonStyle(.icon)
                    .help("Copy the code")
                    .accessibilityLabel("Copy the code")
                // Lines up with the field rows' menu button.
                Color.clear.frame(width: 24, height: 1)
            }
            .animation(Motion.change, value: now)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.vault.opacity(0.05))
    }
}

/// An open note's or secret's heading, in the same shape as every page's: what kind it is, small and spaced, over
/// its name (typed straight into), beside its symbol in a soft tile of Vault's colour.
private struct EditorHeader: View {
    let id: UUID
    let kind: String
    let symbol: String
    @Binding var title: String
    let hint: String
    @Environment(\.itemTitles) private var titles

    var body: some View {
        HStack(spacing: 14) {
            ItemTile(symbol: symbol)
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text(kind).eyebrow()
                TextField(hint, text: $title).textFieldStyle(.plain).font(Kit.title).itemTitle(id, in: titles)
            }
        }
        .padding(.bottom, 4)
    }
}

/// The bar over an editor: back to the list, when it was last changed, and its versions.
private struct EditorBar: View {
    let back: () -> Void
    let backTitle: String
    let file: VaultFile
    let versions: () -> Void

    var body: some View {
        HStack {
            Button(action: back) { Label(backTitle, systemImage: "chevron.left") }
                .buttonStyle(.quiet)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("Saved \(file.changedAt.formatted(.relative(presentation: .named)))").font(Kit.quiet).quietText()
            if let count = file.versions?.count, count > 0 {
                Button { versions() } label: { Label("\(count)", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(.quiet)
                    .help("Earlier versions")
            }
        }
    }
}

/// Copying a secret: kept to this Mac (Universal Clipboard doesn't send it to your other devices), marked so
/// clipboard history apps skip it, and cleared after 30 seconds if nothing else was copied since.
/// Also cleared at once when the vault locks or Stillroom quits, if it's still the last thing copied.
@MainActor enum Clipboard {
    /// The pasteboard's change count right after Stillroom's last copy; nil once cleared or replaced.
    private static var mine: Int?
    /// Seconds a copy stays on the clipboard.
    static let life: Double = 30

    static func copy(_ text: String, concealed: Bool) {
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        board.setString(text, forType: .string)
        board.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        board.setString("", forType: .init("org.nspasteboard.TransientType"))
        let copied = board.changeCount
        mine = copied
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(life))
            if mine == copied { clearIfOurs() }
        }
    }

    /// Empties the clipboard if what's on it is still what Stillroom put there; something copied since is left alone.
    static func clearIfOurs() {
        guard let copied = mine else { return }
        mine = nil
        let board = NSPasteboard.general
        if board.changeCount == copied { board.clearContents() }
    }
}

/// A copy button's face: the copy icon, or, once copied, a check inside a thin ring that drains over the time until
/// the clipboard empties itself, then the copy icon again. Reassurance without a message.
struct ClipboardMark: View {
    let since: Date?

    var body: some View {
        if let since {
            TimelineView(.animation(minimumInterval: 1 / 10)) { frame in
                let left = max(0, 1 - frame.date.timeIntervalSince(since) / Clipboard.life)
                ZStack {
                    Circle().stroke(Color.track, lineWidth: 1.5)
                    Circle().trim(from: 0, to: left)
                        .stroke(Color.vault, style: .init(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "checkmark").font(Kit.micro).foregroundStyle(Color.vault)
                }
                .frame(width: 15, height: 15)
            }
            .transition(.opacity)
            .accessibilityLabel("Copied")
        } else {
            Image(systemName: "doc.on.doc").transition(.opacity)
        }
    }
}

// MARK: Sheets

/// A name for something new, or a new name for something.
struct NameSheet: View {
    let title: String
    var initial = ""
    let action: String
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            Text(title).font(Kit.title)
            GlassField(hint: "Name", text: $name, autofocus: true).onSubmit(go)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.quiet).keyboardShortcut(.cancelAction)
                Button(action, action: go).buttonStyle(.primary).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheetCard(.question)
        .onAppear { name = initial }
    }

    private func go() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        done(name)
        dismiss()
    }
}

/// An item's tags: the ones in use to pick from, and a field for a new one.
struct TagSheet: View {
    let state: AppState
    let file: VaultFile
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: [String] = []
    @State private var new = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text("Tags").font(Kit.title)
                Text(file.name).font(Kit.body).quietText().lineLimit(1)
            }
            let all = Array(Set(state.tags + chosen)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if !all.isEmpty {
                FlowRow(all) { tag in
                    let on = chosen.contains(tag)
                    Button {
                        withAnimation(Motion.hover) { if on { chosen.removeAll { $0 == tag } } else { chosen.append(tag) } }
                    } label: {
                        TagChip(tag: tag, chosen: on).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusRing(Capsule())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            GlassField(hint: "New tag", text: $new, symbol: "tag").onSubmit(addNew)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.quiet).keyboardShortcut(.cancelAction)
                Button("Done") {
                    addNew()
                    state.setTags(chosen, on: file.id)
                    dismiss()
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .sheetCard(.question)
        .onAppear { chosen = file.tagList }
    }

    private func addNew() {
        let tag = new.trimmingCharacters(in: .whitespaces)
        if !tag.isEmpty && !chosen.contains(tag) { chosen.append(tag) }
        new = ""
    }
}

/// Earlier contents of an item, newest first: open one to look, or put it back.
struct VersionsSheet: View {
    let state: AppState
    let file: VaultFile
    let open: (VaultFile.Version, Data) -> Void
    @Environment(\.dismiss) private var dismiss

    private var versions: [VaultFile.Version] {
        (state.files.first { $0.id == file.id }?.versions ?? []).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text("Versions").font(Kit.title)
                Text("“\(file.name)” as it was before each change. Putting one back keeps today's as a version too.")
                    .font(Kit.body).quietText().fixedSize(horizontal: false, vertical: true)
            }
            if versions.isEmpty {
                // Saved as it changes, so an empty list is only "not yet": say when one will be kept.
                Label("No earlier versions yet. Each time this changes, what it held before is kept here, at most one every ten minutes, the last 20.",
                      systemImage: "clock.arrow.circlepath")
                    .font(Kit.body).quietText()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rowPanel()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(versions) { version in
                            if version.id != versions.first?.id { Rectangle().fill(Color.ink.opacity(0.05)).frame(height: 1) }
                            HStack {
                                Image(systemName: "clock").opacity(0.5)
                                Text(version.date.formatted(date: .abbreviated, time: .shortened)).font(Kit.body)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(version.size), countStyle: .file))
                                    .font(Kit.quiet).quietText()
                                Spacer()
                                Button("Open") {
                                    if let data = try? state.readVersion(version) {
                                        dismiss()
                                        open(version, data)
                                    }
                                }
                                .buttonStyle(.quiet)
                                Button("Put Back") {
                                    state.restore(version, of: file.id)
                                    dismiss()
                                }
                                .buttonStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                        }
                    }
                    .rowPanel()
                }
                .frame(maxHeight: 320)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
        }
        .sheetCard(.task)
    }
}

/// Chips laid out in rows, wrapping to the next row when one is full.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(_ items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        Flow(spacing: 6) { ForEach(items, id: \.self) { content($0) } }
    }

    private struct Flow: Layout {
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let rows = arrange(proposal.width ?? .infinity, subviews)
            return CGSize(width: proposal.width ?? rows.width, height: rows.height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
            for view in subviews {
                let size = view.sizeThatFits(.unspecified)
                if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
                view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
        }

        private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (width: CGFloat, height: CGFloat) {
            var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
            for view in subviews {
                let size = view.sizeThatFits(.unspecified)
                if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
                x += size.width + spacing
                widest = max(widest, x)
                rowHeight = max(rowHeight, size.height)
            }
            return (widest, y + rowHeight)
        }
    }
}
