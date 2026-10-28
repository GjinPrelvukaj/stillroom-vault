import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// The vault, open. The sidebar holds the library (files, notes, secrets), the kinds of file, the tags in use and
/// Settings; the pane shows the chosen one. All Files is browsed by folder. A file opens in a card over the blurred
/// window, a note or a secret in its editor. Files dropped on the window go into the folder that's open.
struct VaultView: View {
    let state: AppState
    @Binding var dropping: Bool
    @State private var place: Place = .shelf(.all)
    /// The folder open in All Files; nil at the top.
    @State private var folder: String?
    /// The note or secret open in its editor.
    @State private var editing: VaultFile.ID?
    @State private var search = ""
    @State private var choosing = false
    /// The file shown in the card, and what it holds, unsealed in memory only while the card is up.
    @State private var opened: (file: VaultFile, data: Data)?
    @State private var deleting: VaultFile?
    @State private var deletingFolder: String?
    /// What just went in and checked out: its originals can now be deleted or binned, if the person says so.
    @State private var originals: Originals?
    /// A password export just imported: what came in, and the file, which lists every password unencrypted.
    @State private var imported: (file: URL, added: Int, skipped: Int)?
    /// About to open in another app: what that means is said first, unless the person turned that off.
    @State private var aboutToEdit: VaultFile?
    @AppStorage("editWarningOff") private var editWarningOff = false
    @State private var fileVaultOn = true
    @State private var sheet: Sheet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    enum Place: Hashable { case shelf(Shelf), tag(String), settings, intruders }

    private enum Sheet: Identifiable {
        case newFolder, renameItem(VaultFile), renameFolder(String), tags(VaultFile), versions(VaultFile)
        var id: String {
            switch self {
            case .newFolder: "new-folder"
            case .renameItem(let f): "rename-\(f.id)"
            case .renameFolder(let p): "rename-folder-\(p)"
            case .tags(let f): "tags-\(f.id)"
            case .versions(let f): "versions-\(f.id)"
            }
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Color.ink.opacity(0.06)).frame(width: 1)
                pane.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .blur(radius: opened != nil && !reduceTransparency ? 14 : 0)
            .allowsHitTesting(opened == nil)
            .accessibilityHidden(opened != nil)
            card
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Motion.appear, value: opened?.file)
        .modifier(ActivityNotes(card: opened?.file, folder: folder, searching: !search.isEmpty, sheet: sheetName, dialog: dialogName))
        // A scan or photo from the iPhone arrives as bytes and is sealed straight from memory; it never touches the disk.
        .importsItemProviders([.pdf, .jpeg, .heic, .png, Sketch.type, .image].compactMap { $0 }) { providers in
            providers.forEach(takeScan)
            return !providers.isEmpty
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            take(files)
            return !files.isEmpty
        } isTargeted: { dropping = $0 }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { take(urls) }
        }
        // On a view of its own: "Don't ask again" reaches every dialog below where it's put, so it stays out of the rest.
        .background {
            Color.clear
                .confirmationDialog("Open “\(aboutToEdit?.name ?? "")” in \(aboutToEdit.map(appName) ?? "its app")?",
                                    isPresented: .init(get: { aboutToEdit != nil }, set: { if !$0 { aboutToEdit = nil } })) {
                    Button("Open") { if let file = aboutToEdit { state.editInPlace(file) } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It opens from a copy kept in memory, and every save comes back encrypted. While it's open, \(aboutToEdit.map(appName) ?? "that app") can read it, and may keep its name in Recent items and copies of its own outside the vault. To only look at it, open it here instead.")
                }
                .dialogSuppressionToggle("Don't ask again", isSuppressed: $editWarningOff)
        }
        .confirmationDialog(importedTitle, isPresented: .init(get: { imported != nil }, set: { if !$0 { imported = nil } })) {
            Button("Delete It for Good", role: .destructive) { removeExport(forGood: true) }
            Button("Move to Trash") { removeExport(forGood: false) }
            Button("Keep It", role: .cancel) { imported = nil }
        } message: {
            Text("The file you exported lists every password unencrypted, and everything in it is now in the vault. Delete it now?")
        }
        .confirmationDialog(originalsQuestion, isPresented: .init(get: { originals != nil }, set: { if !$0 { originals = nil } })) {
            Button("Delete Originals", role: .destructive) { removeOriginals(forGood: true) }
            Button("Move to Trash") { removeOriginals(forGood: false) }
            Button("Keep Originals", role: .cancel) { originals = nil }
        } message: {
            Text(originalsMessage)
        }
        // Opened with the recovery key: a new password before anything else.
        .sheet(isPresented: .constant(state.mustSetPassword)) {
            PasswordSheet(title: "Set a new password",
                          message: "Your vault opened without its password. Pick a new password for it; the old one stops working.",
                          asksCurrent: false, canCancel: false) { _, new in
                try await state.setPasswordAfterRecovery(new)
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newFolder:
                NameSheet(title: "New folder", action: "Make Folder") { state.makeFolder($0, in: folderHere) }
            case .renameItem(let file):
                NameSheet(title: "Rename", initial: file.name, action: "Rename") { state.rename(file.id, to: $0) }
            case .renameFolder(let path):
                NameSheet(title: "Rename folder", initial: path.shownLast, action: "Rename") {
                    // Stay where you are; inside the renamed folder, follow it to its new name.
                    if let new = state.renameFolder(path, to: $0), let here = folder,
                       here == path || here.hasPrefix(path + "/") {
                        folder = new + here.dropFirst(path.count)
                    }
                }
            case .tags(let file):
                TagSheet(state: state, file: file)
            case .versions(let file):
                VersionsSheet(state: state, file: file) { version, data in
                    let shown = VaultFile(id: version.id, name: file.name, uti: file.uti, size: version.size,
                                          addedAt: version.date, entry: file.entry)
                    opened = (shown, data)
                }
            }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")” from the vault?", isPresented: .init(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    state.delete(deleting)
                    if editing == deleting.id { editing = nil }
                }
            }
        } message: {
            Text("It and its earlier versions can't be brought back.")
        }
        .confirmationDialog("Delete the folder “\(deletingFolder?.shownLast ?? "")” and everything in it?",
                            isPresented: .init(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
            Button("Delete Folder", role: .destructive) {
                if let deletingFolder { state.deleteFolder(deletingFolder); folder = parent(of: deletingFolder) }
            }
        } message: {
            Text("Every file, note and secret inside it goes too, and can't be brought back.")
        }
        // Shut while a file is open: its unsealed bytes go with the card.
        .onChange(of: state.isOpen) { if !state.isOpen { opened = nil; editing = nil } }
        // A new place closes the editor, unless it's the shelf the open note or secret is on (New Note goes there).
        .onChange(of: place) {
            search = ""
            if let editing, let file = state.files.first(where: { $0.id == editing }), place == .shelf(file.kind) { return }
            editing = nil
        }
        .onAppear(perform: takeInbox)
        .onChange(of: Inbox.shared.waiting) { takeInbox() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Shelf.library, id: \.self) { shelf in
                        item(.shelf(shelf), shelf.title, shelf.symbol, count: state.files.count { shelf.holds($0) })
                    }
                    Text("Kinds").groupLabel().padding(.leading, 10).padding(.top, Kit.Space.group).padding(.bottom, 4)
                    ForEach(Shelf.kinds, id: \.self) { kind in
                        item(.shelf(kind), kind.title, kind.symbol, count: state.files.count { kind.holds($0) })
                    }
                    if !state.tags.isEmpty {
                        Text("Tags").groupLabel().padding(.leading, 10).padding(.top, Kit.Space.group).padding(.bottom, 4)
                        ForEach(state.tags, id: \.self) { tag in
                            item(.tag(tag), tag, "circle.fill", count: state.files.count { $0.tagList.contains(tag) }, tint: TagColor.of(tag))
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            Group {
                let unseen = state.intruderCount - UserDefaults.standard.integer(forKey: "intrudersSeen")
                item(.intruders, "Intruder Log", "person.badge.shield.checkmark", count: state.intruderCount,
                     tint: unseen > 0 ? .red : nil)
                    .padding(.top, Kit.Space.item)
            }
            item(.settings, "Settings", "gearshape")
            VStack(alignment: .leading, spacing: 2) {
                Text("In the vault").eyebrow()
                Text(ByteCountFormatter.string(fromByteCount: Int64(state.size), countStyle: .file))
                    .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(state.files.count) \(state.files.count == 1 ? "item" : "items"), all encrypted")
                    .font(Kit.quiet).opacity(0.45)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, Kit.Space.group)
            .accessibilityElement(children: .combine)
            .animation(Motion.change, value: state.size)
            HStack(spacing: Kit.Space.item) {
                Button { choosing = true } label: { Label("Add Files", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.primary)
                    .keyboardShortcut("n")
                    .help("Add files or folders (⌘N)")
                Button { state.lock("lock button or ⇧⌘L") } label: { Image(systemName: "lock.fill").frame(width: 14) }
                    .buttonStyle(.secondary)
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .help("Lock (⇧⌘L)")
                    .accessibilityLabel("Lock")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: 230)
        .frame(maxHeight: .infinity)
        .background(Color.ink.opacity(0.025))
    }

    private func item(_ p: Place, _ title: String, _ symbol: String, count: Int = 0, tint: Color? = nil) -> some View {
        Button {
            withAnimation(Motion.change) { place = p; folder = nil }
            ActivityLog.note("page: \(pageName)")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(tint == nil || symbol != "circle.fill" ? Kit.body : .system(size: 8))
                    .foregroundStyle(tint ?? .primary)
                    .frame(width: 18)
                Text(title).lineLimit(1)
                Spacer()
                if count > 0 { Text("\(count)").font(Kit.quiet).monospacedDigit().opacity(0.5) }
            }
        }
        .buttonStyle(.sidebarItem(chosen: place == p))
    }

    // MARK: Pane

    @ViewBuilder private var pane: some View {
        if place == .settings {
            SettingsPane(state: state)
        } else if place == .intruders {
            IntruderView(state: state)
        } else if let editing, let file = state.files.first(where: { $0.id == editing }) {
            Group {
                if file.entry == .secret {
                    SecretEditor(state: state, file: file, back: { edit(nil) }, versions: { sheet = .versions(file) })
                } else {
                    NoteEditor(state: state, file: file, back: { edit(nil) }, versions: { sheet = .versions(file) })
                }
            }
            .id(file.id)
            .pane()
        } else {
            list
        }
    }

    private var shelf: Shelf? { if case .shelf(let s) = place { s } else { nil } }
    /// Browsing All Files by folder (a search shows everything that matches instead).
    private var browsing: Bool { shelf == .all && search.isEmpty }
    /// Where something made or dropped now goes.
    private var folderHere: String? { browsing ? folder : nil }

    private var shown: [VaultFile] {
        state.files
            .filter {
                switch place {
                case .shelf(let s): s.holds($0)
                case .tag(let t): $0.tagList.contains(t)
                case .settings, .intruders: false
                }
            }
            .filter { !browsing || $0.folder == folder }
            .filter {
                search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                    || ($0.folder ?? "").shownName.localizedCaseInsensitiveContains(search)
                    || $0.tagList.contains { $0.localizedCaseInsensitiveContains(search) }
                    || state.words[$0.id]?.text.localizedCaseInsensitiveContains(search) == true
            }
            .sorted { $0.entry == nil ? $0.addedAt > $1.addedAt : $0.changedAt > $1.changedAt }
    }

    /// The folders directly inside the one open, when browsing.
    private var subfolders: [String] {
        guard browsing else { return [] }
        return state.folders.filter { parent(of: $0) == folder }
    }

    private var list: some View {
        let shown = shown
        let subfolders = subfolders
        return VStack(alignment: .leading, spacing: Kit.Space.group) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Kit.Space.label) {
                    Text(placeTitle).eyebrow()
                    Text(headline(shown.count)).font(Kit.title).contentTransition(.numericText())
                }
                Spacer()
                if !state.files.isEmpty {
                    GlassField(hint: "Search", text: $search, symbol: "magnifyingglass").frame(width: 220)
                }
                actions
            }
            if browsing, folder != nil { breadcrumb }
            if !EditDesk.shared.open.isEmpty { editingBar }
            if let problem = state.problem {
                HStack {
                    Text(problem).font(Kit.quiet).foregroundStyle(.red.opacity(0.85))
                    Button("OK") { state.problem = nil }.buttonStyle(.quiet)
                }
                .transition(.opacity)
            }
            if shown.isEmpty && subfolders.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(subfolders, id: \.self) { path in
                            if path != subfolders.first { divider }
                            FolderRow(path: path, count: state.files.count { $0.isInside(path) },
                                      open: { withAnimation(Motion.change) { folder = path } },
                                      rename: { sheet = .renameFolder(path) }, delete: { deletingFolder = path },
                                      drop: { drop($0, into: path) })
                        }
                        ForEach(shown) { file in
                            if file.id != shown.first?.id || !subfolders.isEmpty { divider }
                            FileRow(file: file, showsFolder: !browsing, folders: state.folders,
                                    snippet: snippet(for: file),
                                    open: { open(file) },
                                    menu: menu(for: file))
                        }
                    }
                    .rowPanel()
                    // The room below the rows: right-click there for what can be made.
                    Color.clear.frame(height: 400).contentShape(Rectangle()).contextMenu { spaceMenu }
                }
                .scrollIndicators(.never)
            }
        }
        .animation(Motion.change, value: shown)
        .animation(Motion.change, value: subfolders)
        .animation(Motion.change, value: state.problem)
        .pane(wide: true)
        .entrance()
    }

    /// Right-click on empty space.
    @ViewBuilder private var spaceMenu: some View {
        if browsing { Button("New Folder…") { sheet = .newFolder } }
        Button("Add Files or Folders…") { choosing = true }
        Divider()
        Button("New Note") { newNote() }
        SwiftUI.Menu("New Secret") {
            ForEach(Secret.Template.allCases, id: \.self) { template in Button(template.title) { newSecret(template) } }
        }
        Button("Import from Passwords…") { importPasswords() }
    }

    /// Something dropped on a folder: items and folders dragged from the list move into it, files from Finder are
    /// added to it.
    private func drop(_ urls: [URL], into path: String?) -> Bool {
        let moving = Set(urls.compactMap(FileRow.item(from:)))
        let folders = urls.compactMap(FolderRow.path(from:))
        let adding = urls.filter(\.isFileURL)
        if !moving.isEmpty { withAnimation(Motion.change) { state.move(moving, to: path) } }
        for folder in folders { withAnimation(Motion.change) { state.moveFolder(folder, into: path) } }
        if !adding.isEmpty {
            Task {
                offer(await state.add(adding, into: path))
            }
        }
        return !moving.isEmpty || !folders.isEmpty || !adding.isEmpty
    }

    private var divider: some View { Rectangle().fill(Color.ink.opacity(0.05)).frame(height: 1).padding(.leading, 44) }

    /// What can be made here: a note, a secret, or a folder.
    @ViewBuilder private var actions: some View {
        switch shelf {
        case .notes:
            Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }.buttonStyle(.field)
        case .secrets:
            Menu {
                ForEach(Secret.Template.allCases, id: \.self) { template in
                    Button { newSecret(template) } label: { Label(template.title, systemImage: template.symbol) }
                }
                Divider()
                Button { importPasswords() } label: { Label("Import from Passwords…", systemImage: "square.and.arrow.down") }
            } label: { Label("New Secret", systemImage: "plus") }
                .menuStyle(.button)
                .buttonStyle(.field)
                .fixedSize()
        case .all where browsing:
            Button { sheet = .newFolder } label: { Image(systemName: "folder.badge.plus") }
                .buttonStyle(.field)
                .help("New Folder")
                .accessibilityLabel("New Folder")
        default:
            EmptyView()
        }
    }

    private var breadcrumb: some View {
        let parts = (folder ?? "").split(separator: "/").map(String.init)
        return HStack(spacing: 4) {
            Button("All Files") { withAnimation(Motion.change) { folder = nil } }.buttonStyle(.quiet)
                .dropDestination(for: URL.self) { urls, _ in _ = drop(urls, into: nil) }
            ForEach(parts.indices, id: \.self) { i in
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).opacity(0.35)
                let path = parts[...i].joined(separator: "/")
                Button(parts[i].shownName) { withAnimation(Motion.change) { folder = path } }
                    .buttonStyle(.quiet)
                    .dropDestination(for: URL.self) { urls, _ in _ = drop(urls, into: path) }
                    .opacity(i == parts.count - 1 ? 1.6 : 1)
            }
        }
        .font(Kit.body)
    }

    private var placeTitle: String {
        switch place {
        case .shelf(let s): s.title
        case .tag(let t): "Tagged “\(t)”"
        case .settings: "Settings"
        // Only your vault has this page: named plainly, so the log doesn't mark which vault a session was.
        case .intruders: "another page"
        }
    }

    private func headline(_ n: Int) -> String {
        if state.adding > 0 { return "Encrypting \(state.adding) \(state.adding == 1 ? "file" : "files")…" }
        if !search.isEmpty { return n == 0 ? "Nothing called that" : "\(n) found" }
        if browsing, let folder { return folder.shownLast }
        let noun = shelf == .notes ? "note" : shelf == .secrets ? "secret" : place == .shelf(.all) || shelf != nil ? "file" : "item"
        return n == 0 ? "Nothing here yet" : "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// Empty: a still ring of dots, lit while files are over the window, and the one thing to do here.
    private var empty: some View {
        VStack(spacing: Kit.Space.group) {
            ZStack {
                DotRing(lit: dropping ? 1 : 0, tint: .vault)
                Image(systemName: dropping ? "arrow.down" : emptySymbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.vault.opacity(dropping ? 1 : 0.75))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 72, height: 72)
            .animation(Motion.change, value: dropping)
            VStack(spacing: Kit.Space.label) {
                Text(emptyTitle).font(Kit.title)
                Text(emptyLine).font(Kit.body).opacity(0.5).frame(maxWidth: 340)
            }
            if search.isEmpty {
                switch shelf {
                case .notes: Button("New Note") { newNote() }.buttonStyle(.secondary)
                case .secrets: Button("New Login") { newSecret(.login) }.buttonStyle(.secondary)
                case nil: EmptyView()
                default: Button("Choose Files or Folders…") { choosing = true }.buttonStyle(.secondary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Glass.lightRoom)
        .contentShape(Rectangle())
        .contextMenu { spaceMenu }
    }

    private var emptySymbol: String {
        if !search.isEmpty { return "magnifyingglass" }
        switch place {
        case .shelf(let s) where s != .all: return s.symbol
        case .tag: return "tag"
        default: return folder == nil ? "lock" : "folder"
        }
    }

    private var emptyTitle: String {
        if !search.isEmpty { return "Nothing has that in its name" }
        switch place {
        case .shelf(.notes): return "No notes yet"
        case .shelf(.secrets): return "No secrets yet"
        case .tag: return "Nothing tagged yet"
        default: return folder == nil ? "Drop files here" : "This folder is empty"
        }
    }

    private var emptyLine: String {
        if !search.isEmpty { return "Try another word." }
        switch place {
        case .shelf(.notes): return "Anything that should stay private.\nSaved as you type, encrypted."
        case .shelf(.secrets): return "Logins, cards, Wi-Fi, ID numbers.\nCopied to a clipboard that empties itself."
        case .tag: return "Add tags to anything from its menu."
        default: return "Files or whole folders.\nEncrypted the moment they land."
        }
    }

    private func menu(for file: VaultFile) -> FileRow.Menu {
        FileRow.Menu(
            rename: { sheet = .renameItem(file) },
            tags: { sheet = .tags(file) },
            versions: file.versions?.isEmpty == false ? { sheet = .versions(file) } : nil,
            edit: AppState.canEdit(file) ? { askToEdit(file) } : nil,
            save: file.isFile ? { saveCopy(file) } : nil,
            move: { state.move([file.id], to: $0) },
            delete: { deleting = file })
    }

    /// While files are open in other apps: how many, and a way to be done (each save is already sealed back in).
    private var editingBar: some View {
        let count = EditDesk.shared.open.count
        return HStack(spacing: Kit.Space.item) {
            Image(systemName: "pencil.and.outline").foregroundStyle(Color.vault)
            Text("Editing \(count) \(count == 1 ? "file" : "files") in \(count == 1 ? "its app" : "their apps"). Each save is encrypted back in.")
                .font(Kit.quiet)
            Spacer()
            Button("Done Editing") { EditDesk.shared.clearAll() }.buttonStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .rowPanel()
    }

    /// For a search that matched inside an item, the words around the match.
    private func snippet(for file: VaultFile) -> String? {
        guard !search.isEmpty, !file.name.localizedCaseInsensitiveContains(search),
              let text = state.words[file.id]?.text else { return nil }
        return SearchIndex.snippet(text, around: search)
    }

    /// Files sent from Finder ("Move to Stillroom") or dropped on the Dock icon go in now; with "Move", their
    /// originals are deleted for good once checked, or binned if FileVault is off (deleting wouldn't be for good).
    private func takeInbox() {
        guard state.isOpen, !Inbox.shared.waiting.isEmpty else { return }
        let (urls, moving) = Inbox.shared.take()
        Task {
            let added = await state.add(urls, into: folderHere)
            guard !added.isEmpty else { return }
            guard moving else { offer(added); return }
            if Originals.fileVaultOn {
                forget(added)
            } else {
                do {
                    try await added.trash()
                    state.problem = "FileVault is off, so the originals went to the Trash rather than being deleted for good."
                } catch {
                    state.problem = ActivityLog.failed(error, "The originals couldn't be moved to the Trash. \(error.localizedDescription)")
                }
            }
        }
    }

    /// A document scanned, photo taken or sketch drawn on the iPhone, into the folder that's open. A sketch comes in
    /// as a PNG on white, so it shows (and is searched) like any picture.
    private func takeScan(_ provider: NSItemProvider) {
        let preferred = [UTType.pdf, .png, .jpeg, .heic, Sketch.type].compactMap { $0 }
        let type = preferred.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }
            ?? provider.registeredContentTypes.first ?? .data
        let folder = folderHere
        ActivityLog.note("import from iPhone (\(type == .pdf ? "scan" : type == Sketch.type ? "sketch" : "photo"))")
        _ = provider.loadDataRepresentation(for: type) { data, error in
            Task { @MainActor in
                guard let data else {
                    state.problem = "That didn't come through from the iPhone. \(error?.localizedDescription ?? "")"
                    return
                }
                let stamp = Self.scanStamp.string(from: .now)
                if type == Sketch.type, let png = Sketch.png(from: data) {
                    state.add(png, named: "Sketch \(stamp).png", folder: folder)
                } else {
                    let kind = type == .pdf ? "Scan" : type.conforms(to: .image) ? "Photo" : "Import"
                    state.add(data, named: "\(kind) \(stamp).\(type.preferredFilenameExtension ?? "data")", folder: folder)
                }
            }
        }
    }

    private static let scanStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    /// For the activity log: where you are, without any name you gave anything.
    private var pageName: String {
        switch place {
        case .shelf(let s): s.title
        case .tag: "a tag"
        case .settings: "Settings"
        // Only your vault has this page: named plainly, so the log doesn't mark which vault a session was.
        case .intruders: "another page"
        }
    }

    private var sheetName: String? {
        switch sheet {
        case .newFolder: "new folder"
        case .renameItem: "rename"
        case .renameFolder: "rename folder"
        case .tags: "tags"
        case .versions: "versions"
        case nil: nil
        }
    }

    private var dialogName: String? {
        if deleting != nil { return "delete an item?" }
        if deletingFolder != nil { return "delete a folder?" }
        if originals != nil { return "delete originals?" }
        if imported != nil { return "delete the password export?" }
        if aboutToEdit != nil { return "edit in place warning" }
        return nil
    }

    /// Opens a note or secret in its editor (nil: back to the list), moving the way switching pages does.
    private func edit(_ id: VaultFile.ID?) {
        if id == nil { ActivityLog.note("close editor") }
        withAnimation(Motion.change) { editing = id }
    }

    // MARK: Making

    private func newNote() {
        if let note = state.newEntry(.note, name: "Untitled note", content: Data(), folder: folderHere) {
            withAnimation(Motion.change) { place = .shelf(.notes) }
            edit(note.id)
        }
    }

    private func newSecret(_ template: Secret.Template) {
        let content = (try? JSONEncoder().encode(Secret(template: template))) ?? Data()
        if let secret = state.newEntry(.secret, name: template.title, content: content, folder: folderHere) {
            withAnimation(Motion.change) { place = .shelf(.secrets) }
            edit(secret.id)
        }
    }

    private func parent(of path: String) -> String? {
        let parts = path.split(separator: "/").dropLast()
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    // MARK: Adding

    private func take(_ urls: [URL]) {
        let into = folderHere
        Task {
            offer(await state.add(urls, into: into))
        }
    }

    /// Edit in Place, after saying what it gives away (once, if the person says so).
    private func askToEdit(_ file: VaultFile) {
        if editWarningOff { state.editInPlace(file) } else { aboutToEdit = file }
    }

    /// The app a file would open in ("Pages", "Preview").
    private func appName(_ file: VaultFile) -> String {
        guard let type = file.type, let app = NSWorkspace.shared.urlForApplication(toOpen: type) else { return "its app" }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Accounts from Apple Passwords (or Chrome, Bitwarden, 1Password) out of the file it exported, into Secrets.
    private func importPasswords() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose the file Passwords exported (in Passwords: File › Export All Passwords)."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ActivityLog.note("import passwords")
        do {
            let logins = try PasswordImport.logins(from: Data(contentsOf: url))
            let result = state.importLogins(logins)
            withAnimation(Motion.change) { place = .shelf(.secrets) }
            // Some left out at the free tier's limit: the export still holds them, so it isn't offered for deletion.
            if result.left == 0 { imported = (url, result.added, result.skipped) }
        } catch {
            state.problem = ActivityLog.failed(error, error.localizedDescription)
        }
    }

    private var importedTitle: String {
        guard let imported else { return "" }
        if imported.added == 0 { return imported.skipped == 0 ? "No accounts in that file." : "Nothing new: all \(imported.skipped) were already here." }
        let what = "Imported \(imported.added) \(imported.added == 1 ? "login" : "logins")"
        return imported.skipped > 0 ? "\(what); \(imported.skipped) were already here." : "\(what)."
    }

    private func removeExport(forGood: Bool) {
        guard let file = imported?.file else { return }
        imported = nil
        let export = Originals(files: [file])
        if forGood {
            forget(export)
        } else {
            Task { do { try await export.trash() } catch { state.problem = ActivityLog.failed(error, "The file couldn't be moved to the Trash. \(error.localizedDescription)") } }
        }
    }

    /// Asks what to do with the originals of what just went in (only those whose copies checked out).
    private func offer(_ added: Originals) {
        guard !added.isEmpty else { return }
        fileVaultOn = Originals.fileVaultOn
        originals = added
    }

    private var originalsQuestion: String {
        guard let files = originals?.files else { return "" }
        return files.count == 1 ? "Delete “\(files[0].lastPathComponent)” now that it's in the vault?"
                                : "Delete the \(files.count) originals now that they're in the vault?"
    }

    private var originalsMessage: String {
        var lines = ["Each was checked against its encrypted copy first. Deleting skips the Trash and can't be undone."]
        if !fileVaultOn {
            lines.append("FileVault is off, so deleted files could still be recovered from this disk. Turn it on in System Settings › Privacy & Security.")
        }
        if originals?.fromICloud == true { lines.append("iCloud Drive keeps deleted files in Recently Deleted for 30 days.") }
        return lines.joined(separator: "\n\n")
    }

    private func removeOriginals(forGood: Bool) {
        guard let added = originals else { return }
        originals = nil
        if forGood {
            forget(added)
        } else {
            Task {
                do { try await added.trash() } catch { state.problem = ActivityLog.failed(error, "The originals couldn't be moved to the Trash. \(error.localizedDescription)") }
            }
        }
    }

    /// Deletes the originals for good, off the main thread (a big folder takes a moment).
    private func forget(_ added: Originals) {
        Task {
            let failed = await Task.detached(priority: .userInitiated) { added.delete() }.value
            if !failed.isEmpty { state.problem = "Couldn't delete \(failed.joined(separator: ", ")). They're still where they were." }
        }
    }

    // MARK: Opening

    private func open(_ file: VaultFile) {
        ActivityLog.note("open \(file.kind.title.lowercased())\(file.streamed ? " (streamed)" : "")")
        if file.entry != nil {
            if case .shelf(let s) = place, s == file.kind {} else { withAnimation(Motion.change) { place = .shelf(file.kind) } }
            edit(file.id)
            return
        }
        if file.playable {
            opened = (file, Data())
            return
        }
        // Too big to hold in memory for a look: the card offers editing in place or saving a copy instead.
        if file.size > 64 << 20 {
            opened = (file, Data())
            return
        }
        do { opened = (file, try ActivityLog.timed("read for the card") { try state.read(file) }) } catch { state.problem = ActivityLog.failed(error, error.localizedDescription) }
    }

    /// A copy outside the vault, where the person picks. It is not encrypted, and the panel says so.
    private func saveCopy(_ file: VaultFile, data: Data? = nil) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.message = "This copy won't be encrypted."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if let data, !data.isEmpty {
                try data.write(to: url, options: .atomic)
                VaultStore.stampDates(file, on: url)
                VaultStore.quarantine(url)
            } else {
                try state.export(file, to: url)
            }
        } catch {
            state.problem = ActivityLog.failed(error, error.localizedDescription)
        }
    }

    /// An email's attachment out of the vault, unencrypted, where the person picks.
    private func saveAttachment(_ attachment: Email.Attachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.name
        panel.message = "This copy won't be encrypted."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try attachment.data.write(to: url, options: .atomic)
            // An attachment is the classic way a program arrives: Gatekeeper checks it before it can run.
            VaultStore.quarantine(url)
        } catch { state.problem = ActivityLog.failed(error, error.localizedDescription) }
    }

    /// The open file in a card over the blurred window.
    @ViewBuilder private var card: some View {
        if let opened {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(reduceTransparency ? 0.7 : 0.35))
                .ignoresSafeArea()
                .onTapGesture { self.opened = nil }
                .accessibilityHidden(true)
                .transition(.opacity)
            PreviewCard(file: opened.file, data: opened.data,
                        player: state.player(for: opened.file).map { AnyView($0.id(opened.file.id)) },
                        edit: AppState.canEdit(opened.file) && state.files.contains { $0.id == opened.file.id }
                            ? { let f = opened.file; self.opened = nil; askToEdit(f) } : nil,
                        save: { saveCopy(opened.file, data: opened.data) },
                        versions: state.files.first { $0.id == opened.file.id }?.versions?.isEmpty == false
                            ? { let f = opened.file; self.opened = nil; sheet = .versions(f) } : nil,
                        close: { self.opened = nil },
                        stage: { [file = opened.file, data = opened.data] in try await state.stage(file, data: data) },
                        unstage: { [id = opened.file.id] in EditDesk.shared.unstage(id: id) },
                        keep: { [folder = opened.file.folder] in state.add($0.data, named: $0.name, folder: folder) },
                        saveAttachment: saveAttachment)
                .frame(maxWidth: 860, maxHeight: 700)
                .padding(.horizontal, 40)
                .padding(.vertical, Glass.lightRoom)
                .geometryGroup()
                .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

/// A tag's colour, the same every time for the same word: Tally's palette, picked by the word.
enum TagColor {
    static let palette: [Color] = [.hex(0x60A5FA), .hex(0xF472B6), .hex(0x34D399), .hex(0xFBBF24),
                                   .hex(0xB08CFF), .hex(0xFB923C), .hex(0x22D3EE), .hex(0xF87171)]
    static func of(_ tag: String) -> Color {
        palette[tag.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count]
    }
}

/// A folder inside the one open: its name and how much is in it. Click to go in.
private struct FolderRow: View {
    let path: String
    let count: Int
    let open: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    let drop: ([URL]) -> Bool
    @State private var hovering = false
    @State private var targeted = false

    /// A folder dragged within the window carries "vault-folder:<random id>", never its name: dropped on the Desktop
    /// or in another app, it lands as a link that says nothing about what's in the vault.
    static func path(from url: URL) -> String? {
        guard url.scheme == "vault-folder" else { return nil }
        return UUID(uuidString: String(url.absoluteString.dropFirst("vault-folder:".count))).flatMap { FolderDrag.paths[$0] }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: targeted ? "folder.fill.badge.plus" : "folder.fill").frame(width: 18)
                    .foregroundStyle(Color.vault.opacity(targeted ? 1 : 0.8))
                Text(path.shownLast).font(Kit.body).lineLimit(1)
                Spacer(minLength: Kit.Space.group)
                Text(count == 1 ? "1 item" : "\(count) items").font(Kit.quiet).opacity(0.45)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).opacity(0.3)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(targeted ? Color.vault.opacity(0.16) : Color.ink.opacity(hovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in drop(urls) } isTargeted: { targeted = $0 }
        .draggable(URL(string: "vault-folder:\(FolderDrag.token(for: path).uuidString)")!) {
            Label(path.shownLast, systemImage: "folder.fill")
                .padding(8).foregroundStyle(.white).background(.black.opacity(0.6), in: Capsule())
        }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.hover, value: targeted)
        .contextMenu {
            Button("Open", action: open)
            Button("Rename…", action: rename)
            Divider()
            Button("Delete Folder…", role: .destructive, action: delete)
        }
    }
}

/// One file, note or secret: its symbol, its name and tags, then quietly its kind, size and day.
struct FileRow: View {
    let file: VaultFile
    /// Out of folder browsing (a search, a kind, a tag), the folder it sits in is shown.
    var showsFolder = true
    var folders: [String] = []
    /// When a search matched inside it, the words around the match.
    var snippet: String?
    let open: () -> Void
    let menu: Menu
    @State private var hovering = false

    /// A row dragged within the window carries its item as "vault-item:<id>"; it never means anything outside.
    static func item(from url: URL) -> UUID? {
        url.scheme == "vault-item" ? UUID(uuidString: String(url.absoluteString.dropFirst("vault-item:".count))) : nil
    }

    struct Menu {
        var rename: () -> Void
        var tags: () -> Void
        var versions: (() -> Void)?
        var edit: (() -> Void)?
        var save: (() -> Void)?
        var move: (String?) -> Void
        var delete: () -> Void
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: file.symbol).frame(width: 18).opacity(0.6)
                Text(file.name).font(Kit.body).lineLimit(1).truncationMode(.middle)
                ForEach(file.tagList, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 7).frame(height: 18)
                        .background(TagColor.of(tag).opacity(0.18), in: Capsule())
                        .foregroundStyle(TagColor.of(tag))
                }
                if let snippet {
                    Text(snippet).font(Kit.quiet).opacity(0.5).lineLimit(1)
                } else if showsFolder, let folder = file.folder {
                    Label(folder.shownPath, systemImage: "folder").font(Kit.quiet).opacity(0.45).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: Kit.Space.group)
                Group {
                    if let versions = file.versions, !versions.isEmpty {
                        Label("\(versions.count)", systemImage: "clock.arrow.circlepath").help("Earlier versions kept")
                    }
                    Text(file.kindName).lineLimit(1)
                    if file.isFile { Text(file.sizeText).monospacedDigit().frame(width: 64, alignment: .trailing) }
                    Text(file.shownDate.formatted(.dateTime.day().month(.abbreviated).year())).frame(width: 84, alignment: .trailing)
                }
                .font(Kit.quiet).opacity(0.45)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.ink.opacity(hovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .draggable(URL(string: "vault-item:\(file.id.uuidString)")!) {
            Label(file.name, systemImage: file.symbol).padding(8).foregroundStyle(.white).background(.black.opacity(0.6), in: Capsule())
        }
        .animation(Motion.hover, value: hovering)
        .contextMenu {
            Button("Open", action: open)
            if let edit = menu.edit { Button("Edit in Place", action: edit) }
            Button("Rename…", action: menu.rename)
            Button("Tags…", action: menu.tags)
            SwiftUI.Menu("Move To") {
                Button("Top Level") { menu.move(nil) }.disabled(file.folder == nil)
                if !folders.isEmpty { Divider() }
                ForEach(folders, id: \.self) { path in
                    Button(path.shownPath) { menu.move(path) }.disabled(file.folder == path)
                }
            }
            if let versions = menu.versions { Button("Versions…", action: versions) }
            if let save = menu.save { Button("Save a Copy…", action: save) }
            Divider()
            Button("Delete…", role: .destructive, action: menu.delete)
        }
    }
}

/// What a file holds: pictures, PDFs, text and email are drawn here from memory; any other kind by Quick Look, from
/// a copy on the RAM disk that goes when the card shuts.
private struct PreviewCard: View {
    let file: VaultFile
    let data: Data
    var player: AnyView?
    var edit: (() -> Void)?
    let save: () -> Void
    var versions: (() -> Void)?
    let close: () -> Void
    let stage: () async throws -> URL
    let unstage: () -> Void
    let keep: (Email.Attachment) -> Void
    let saveAttachment: (Email.Attachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text(file.kindName).eyebrow()
                Text(file.name).font(Kit.title).lineLimit(1).truncationMode(.middle)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: Kit.Space.item) {
                Text("\(file.sizeText) · \(file.shownDate.formatted(date: .long, time: .omitted))").font(Kit.quiet).opacity(0.45)
                Spacer()
                Button("Close", action: close).buttonStyle(.quiet).keyboardShortcut(.cancelAction)
                if let versions { Button("Versions…", action: versions).buttonStyle(.secondary) }
                if file.isFile { Button("Save a Copy…", action: save).buttonStyle(.secondary) }
                if let edit { Button("Edit in Place", action: edit).buttonStyle(.primary) }
            }
        }
        .padding(Kit.Space.edge)
        .padding(.bottom, 8)
        .card()
    }

    @ViewBuilder private var content: some View {
        if let player {
            player
        } else if file.entry == .secret, let secret = try? JSONDecoder().decode(Secret.self, from: data) {
            // An earlier version of a secret: concealed values stay hidden here too.
            ScrollView {
                VStack(alignment: .leading, spacing: Kit.Space.item) {
                    ForEach(secret.fields) { field in
                        HStack {
                            Text(field.label).font(Kit.quiet).opacity(0.55).frame(width: 140, alignment: .leading)
                            Text(field.concealed ? String(repeating: "•", count: 10) : field.value).font(Kit.body)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Kit.Space.group)
            }
        } else if Email.isEmail(file), !data.isEmpty {
            EmailView(data: data, keep: keep, save: saveAttachment)
        } else if data.isEmpty && file.isFile && file.size <= QuickLookView.largest {
            QuickLookView(file: file, stage: stage, unstage: unstage)
        } else if data.isEmpty && file.isFile {
            VStack(spacing: Kit.Space.label) {
                Image(systemName: file.symbol).font(.system(size: 28, weight: .light)).opacity(0.45).padding(.bottom, 4)
                Text("Too big to show here").font(Kit.body)
                Text("Edit it in place to open it in its app, or save a copy.").font(Kit.quiet).opacity(0.45)
            }
        } else if file.type?.conforms(to: .pdf) == true, let pdf = PDFDocument(data: data) {
            PDFPreview(document: pdf)
        } else if Sketch.isSketch(uti: file.uti, name: file.name), let png = Sketch.png(from: data), let image = NSImage(data: png) {
            Image(nsImage: image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(Kit.Space.group)
        } else if let image = NSImage(data: data), file.type?.conforms(to: .image) == true {
            Image(nsImage: image).resizable().scaledToFit().padding(Kit.Space.group)
        } else if file.entry != nil || file.type?.conforms(to: .text) == true, let text = String(data: data, encoding: .utf8) {
            ScrollView {
                Text(text).font(.system(size: 12, design: .monospaced)).opacity(0.85).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Kit.Space.group)
            }
        } else {
            QuickLookView(file: file, stage: stage, unstage: unstage)
        }
    }
}

/// PDFKit's own view, on the card's dark instead of grey.
private struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}

/// What the window shows, written to the activity log as it changes: the card, folder depth, search, sheets and
/// dialogs. Kept apart so the window's own description stays small enough to compile quickly.
private struct ActivityNotes: ViewModifier {
    let card: VaultFile?
    let folder: String?
    let searching: Bool
    let sheet: String?
    let dialog: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: card) { old, new in if new == nil, old != nil { ActivityLog.note("close card") } }
            .onChange(of: folder) { ActivityLog.note("folder: \(folder.map { "level \($0.split(separator: "/").count)" } ?? "top")") }
            .onChange(of: searching) { ActivityLog.note(searching ? "search started" : "search cleared") }
            .onChange(of: sheet) { ActivityLog.note(sheet.map { "sheet: \($0)" } ?? "sheet closed", action: sheet != nil) }
            .onChange(of: dialog) { if let dialog { ActivityLog.note("dialog: \(dialog)") } }
    }
}

/// Which folder each drag id stands for, held only in memory and forgotten on lock.
@MainActor enum FolderDrag {
    private(set) static var paths: [UUID: String] = [:]

    static func token(for path: String) -> UUID {
        if let known = paths.first(where: { $0.value == path })?.key { return known }
        let fresh = UUID()
        paths[fresh] = path
        return fresh
    }

    static func forget() { paths = [:] }
}
