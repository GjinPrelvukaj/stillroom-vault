import SwiftUI

/// A new password, typed twice, and the current one first when changing it. Used to change the password, to set a
/// decoy, and (with no way out) to set a new one after the recovery key opened the vault.
struct PasswordSheet: View {
    let title: String
    let message: String
    /// A consequence to read before saving, on a line of its own in the caution colour.
    var warning: String?
    /// The button, naming what it does.
    var action = "Save"
    var asksCurrent = true
    var canCancel = true
    let save: (_ current: String, _ new: String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var again = ""
    @State private var problem: String?
    @State private var working = false

    private static let shortest = 12

    private var ready: Bool {
        new.count >= Self.shortest && PasswordStrength.isEnough(new) && new == again && (!asksCurrent || !current.isEmpty) && !working
    }

    private var line: String? {
        if let problem { return problem }
        if !new.isEmpty && new.count < Self.shortest { return "At least \(Self.shortest) characters. Longer is stronger." }
        if !new.isEmpty && !PasswordStrength.isEnough(new) { return PasswordStrength.advice }
        if !again.isEmpty && again != new { return "The two don't match yet." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text(title).font(Kit.title)
                Text(message).font(Kit.body).quietText().fixedSize(horizontal: false, vertical: true)
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(Kit.body).foregroundStyle(Color.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Kit.Space.label)
                }
            }
            VStack(spacing: Kit.Space.item) {
                if asksCurrent { GlassField(hint: "Current password", text: $current, secure: true, symbol: "key", autofocus: true) }
                GlassField(hint: "New password", text: $new, secure: true, symbol: "key", autofocus: !asksCurrent)
                GlassField(hint: "New password again", text: $again, secure: true, symbol: "key")
            }
            .onSubmit(go)
            // Room for advice only once typing starts: no blank band above the buttons before then.
            if !new.isEmpty || problem != nil {
                Text(line ?? " ")
                    .font(Kit.quiet)
                    .foregroundStyle(problem == nil ? Color.quietInk : Color.problem)
                    // Advice can run to two lines: room for both from the start, so the buttons don't step down.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 32, alignment: .top)
                    .transition(.opacity)
            }
            HStack(spacing: Kit.Space.item) {
                Spacer()
                if canCancel { Button("Cancel") { dismiss() }.buttonStyle(.quiet).keyboardShortcut(.cancelAction) }
                Button(action, action: go).buttonStyle(.primary).keyboardShortcut(.defaultAction).disabled(!ready)
            }
        }
        .sheetCard(.question)
        .animation(Motion.change, value: new.isEmpty)
        .onChange(of: new) { problem = nil }
        .onChange(of: current) { problem = nil }
        .interactiveDismissDisabled(!canCancel)
    }

    private func go() {
        guard ready else { return }
        working = true
        Task {
            do {
                try await save(current, new)
                dismiss()
            } catch {
                problem = ActivityLog.failed(error, error.localizedDescription)
            }
            working = false
        }
    }
}

/// The recovery key, shown once: it opens the vault on any Mac without the password, so it goes on paper, not in a
/// file or the clipboard. Then two of its five groups are typed back, so it can't be waved past unwritten.
struct RecoveryKeySheet: View {
    let code: String
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    @State private var first = ""
    @State private var second = ""
    /// Which two groups are asked for, picked at random each time (0-based, in order).
    @State private var asked: [Int] = Array((0..<5).shuffled().prefix(2)).sorted()

    private var groups: [String] { code.split(separator: "-").map(String.init) }
    private var matches: Bool {
        groups.count == 5 && normalizedRecoveryCode(first) == groups[asked[0]] && normalizedRecoveryCode(second) == groups[asked[1]]
    }

    private static let ordinals = ["first", "second", "third", "fourth", "fifth"]

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            if checking { check } else { show }
        }
        .sheetCard(.task)
        .interactiveDismissDisabled()
        .animation(Motion.change, value: checking)
    }

    private var show: some View {
        Group {
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text("Your Recovery Key").font(Kit.title)
                Text("Write it on paper and keep it somewhere safe. If you forget your password, it's the only other way in. It also opens this vault on any Mac, so treat it like the vault itself. It won't be shown again.")
                    .font(Kit.body).quietText().fixedSize(horizontal: false, vertical: true)
            }
            Text(code)
                .font(Kit.figure.monospaced())
                .tracking(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .rowPanel()
                .accessibilityLabel(code.map(String.init).joined(separator: " "))
            HStack {
                Spacer()
                Button("I've Written It Down") { checking = true }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var check: some View {
        Group {
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text("Check What You Wrote").font(Kit.title)
                Text("Type the \(Self.ordinals[asked[0]]) and \(Self.ordinals[asked[1]]) groups from your paper.")
                    .font(Kit.body).quietText().fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Kit.Space.item) {
                GlassField(hint: "Group \(asked[0] + 1)", text: $first, symbol: "\(asked[0] + 1).circle", autofocus: true)
                GlassField(hint: "Group \(asked[1] + 1)", text: $second, symbol: "\(asked[1] + 1).circle")
            }
            .onSubmit { if matches { dismiss() } }
            Text(first.count >= 5 && second.count >= 5 && !matches ? "That doesn't match. Check your paper, or see the key again." : " ")
                .font(Kit.quiet).foregroundStyle(Color.problem)
            HStack(spacing: Kit.Space.item) {
                Button("See the Key Again") { checking = false; first = ""; second = "" }.buttonStyle(.quiet)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.primary).keyboardShortcut(.defaultAction).disabled(!matches)
            }
        }
    }
}
