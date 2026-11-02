import SwiftUI

/// Check Stillroom: everything read back all the way through, then what doesn't open, each with what can be done.
struct CheckSheet: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var done = 0
    @State private var total = 0
    @State private var damage: [AppState.Damage]?
    @State private var fixed = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            HStack(spacing: Kit.Space.group) {
                // Fills as items are read; ends full with a check, or with the damaged share in orange.
                RingMark(symbol: mark, lit: lit, tint: .vault, rest: damage?.isEmpty == false ? Color.caution : nil, size: 56)
                VStack(alignment: .leading, spacing: Kit.Space.label) {
                    Text("Check Vault").font(Kit.title)
                    Text(summary).font(Kit.body).quietText().fixedSize(horizontal: false, vertical: true)
                }
            }
            if let damage, !damage.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(damage) { item in
                            if item.id != damage.first?.id { Rectangle().fill(Color.ink.opacity(0.05)).frame(height: 1) }
                            row(item)
                        }
                    }
                    .rowPanel()
                }
                .frame(maxHeight: 260)
                .scrollIndicators(.never)
            }
            HStack {
                Spacer()
                Button(damage == nil ? "Cancel" : "Done") { dismiss() }
                    .buttonStyle(damage == nil ? .quiet : .primary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheetCard(.task)
        .task {
            let found = await state.checkVault { done = $0; total = $1 }
            damage = found
        }
    }

    private var lit: Double {
        guard let damage else { return total == 0 ? 0 : Double(done) / Double(total) }
        return total == 0 ? 1 : Double(total - damage.count) / Double(total)
    }

    private var mark: String {
        guard let damage else { return "doc.text.magnifyingglass" }
        return damage.isEmpty ? "checkmark" : "exclamationmark"
    }

    private var summary: String {
        guard let damage else { return total == 0 ? "Reading every item back…" : "Reading \(done) of \(total)…" }
        if damage.isEmpty && fixed > 0 { return "All dealt with. Run the check again any time." }
        if damage.isEmpty { return "Everything opens as it should. \(total) checked, nothing damaged." }
        return "\(damage.count) of \(total) didn't open. If you have a backup from before this, restoring it brings them back; otherwise fix each below."
    }

    private func row(_ item: AppState.Damage) -> some View {
        HStack(spacing: Kit.Space.group) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.caution).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.file.name).font(Kit.body).lineLimit(1).truncationMode(.middle)
                Text(item.version.map { "Earlier version from \($0.date.formatted(date: .abbreviated, time: .shortened))" } ?? "Current contents")
                    .font(Kit.quiet).quietText()
            }
            Spacer()
            if let version = item.version {
                Button("Remove Version") { state.dropVersion(version, of: item.file.id); resolve(item) }.buttonStyle(.secondary)
            } else if let fallback = item.fallback {
                Button("Use Earlier Version") { state.fallBack(item.file.id, to: fallback); resolve(item) }.buttonStyle(.secondary)
            } else {
                Button("Delete") { state.delete(item.file); resolve(item) }.buttonStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func resolve(_ item: AppState.Damage) {
        fixed += 1
        withAnimation(Motion.change) { damage?.removeAll { $0.id == item.id } }
    }
}
