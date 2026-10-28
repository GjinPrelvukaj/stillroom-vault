import SwiftUI

/// Settings' Security tab: how the vault is protected, as plain facts. Only what's true of every vault, plus settings
/// each vault keeps for itself (screen capture), so it never says which vault is open: nothing about Touch ID, the
/// recovery key, the kit or the decoy (docs/SECURITY.md rule 2). A protection that's switched off says so.
struct SecurityFacts: View {
    let state: AppState

    private struct Fact: Identifiable {
        let figure: String
        let title: String
        let detail: String
        /// A protection you've switched off: shown in orange, so the page never claims more than is on.
        var off = false
        var id: String { title }
    }

    private var facts: [Fact] {
        let cost = PasswordCost.current
        return [
            Fact(figure: "AES-256-GCM", title: "Every file sealed",
                 detail: "Each file, note, secret and earlier version has its own 256-bit key, made fresh every time it's saved, with a fresh nonce for every seal."),
            Fact(figure: "\(cost.memoryKiB / 1024) MB", title: "Of memory per password guess",
                 detail: "Your password is stretched with Argon2id (RFC 9106): \(cost.passes) passes, \(cost.lanes) lanes, a random 16-byte salt. Graphics cards and custom chips run short of memory, so guessing stays slow."),
            Fact(figure: "Bound", title: "No file can stand in for another",
                 detail: "Every sealed file, the list and the search index carry what they are. Swapped, copied over or changed by one byte, they refuse to open."),
            Fact(figure: "±12%", title: "Sizes hidden",
                 detail: "Files are padded before sealing, so a sealed size gives little away. Names, folders, kinds, tags and dates are sealed inside the list."),
            Fact(figure: "0", title: "Network connections",
                 detail: "Stillroom has no networking code: every build is checked and refused if any appears. No account, no server, no sync, no tracking."),
            Fact(figure: "Locked", title: "Keys forgotten",
                 detail: "The vault key and every file key are held in memory only while the vault is open, and let go the moment it locks. Previews live on a RAM disk, never the SSD."),
            // Follows Protection › Show in screenshots & screen sharing, which each vault keeps sealed for itself.
            state.showInCapture
                ? Fact(figure: "Visible", title: "To screen capture, as you chose",
                       detail: "Show in screenshots & screen sharing is on, so recordings and screen sharing can see Stillroom while it's open. The lock screen stays hidden, and keyloggers still can't read what you type.",
                       off: true)
                : Fact(figure: "Hidden", title: "From screen capture and keyloggers",
                       detail: "Screenshots, recordings and screen sharing see nothing while Stillroom is open. Secure keyboard input is on while Stillroom is in front."),
            Fact(figure: "SHA-256", title: "Checked before anything is deleted",
                 detail: "When Stillroom removes the originals of what you added, each sealed copy is read back and compared byte for byte first. A copy that doesn't match keeps its original."),
            Fact(figure: "Open", title: "A published format",
                 detail: "Every byte on disk is documented, and a short script opens a vault without the app. Nothing secret is hidden in Stillroom, and there's no back door."),
        ]
    }

    private let limits = [
        "A weak password. The strength check refuses guessable ones.",
        "Malware with administrator rights on this Mac while the vault is open.",
        "Copies other apps keep of files opened in them with Edit in Place, and names they remember.",
        "Someone able to change the vault's folder putting back an older copy of it.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Kit.Space.group) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: Kit.Space.item)], spacing: Kit.Space.item) {
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: Kit.Space.label) {
                        Text(fact.figure)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(fact.off ? Color.orange : Color.vault)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(fact.title).font(Kit.body)
                        Text(fact.detail).font(Kit.quiet).opacity(0.45).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
                    .rowPanel()
                    .accessibilityElement(children: .combine)
                }
            }
            VStack(alignment: .leading, spacing: Kit.Space.label) {
                Text("What Stillroom can't protect against").groupLabel().padding(.leading, 4)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(limits, id: \.self) { limit in
                        Label { Text(limit).font(Kit.quiet).opacity(0.7) } icon: {
                            Image(systemName: "exclamationmark.circle").font(Kit.quiet).opacity(0.45)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowPanel()
            }
        }
    }
}
