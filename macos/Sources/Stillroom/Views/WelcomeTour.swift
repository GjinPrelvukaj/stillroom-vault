import SwiftUI

/// The first time, before a vault is made: four short pages on what Stillroom does and the few things to know, the ring
/// filling as they go. Shown whenever there's no vault yet, so nothing about it needs remembering.
struct WelcomeTour: View {
    let done: () -> Void
    @State private var page = 0
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Page {
        let symbol: String
        let title: String
        let text: String
    }

    private let pages = [
        Page(symbol: "lock.shield", title: "Everything stays on this Mac",
             text: "Files, notes and passwords are encrypted right here. No account, no server, no cloud, so nobody else can open your vault. Not even whoever made Stillroom."),
        Page(symbol: "key", title: "Your password is the way in",
             text: "It can't be reset or sent to you, so pick one you won't forget. Next you'll get a recovery key to write on paper: the only other way in."),
        Page(symbol: "person.2", title: "A second password, if you need one",
             text: "In Settings you can add a decoy password. It opens a separate, harmless vault, for when someone makes you open Stillroom."),
        Page(symbol: "bolt", title: "Quick to lock",
             text: "Stillroom locks itself when the Mac sleeps or sits untouched. \(LockKey.shortcut) in any app locks and hides it at once."),
    ]

    var body: some View {
        let current = pages[page]
        VStack(spacing: Kit.Space.group) {
            ZStack {
                DotRing(lit: Double(page + 1) / Double(pages.count), tint: .vault)
                Image(systemName: current.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .opacity(0.75)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 84, height: 84)
            .animation(Motion.change, value: page)

            VStack(spacing: Kit.Space.label) {
                Text(current.title).font(Kit.title)
                Text(current.text)
                    .font(Kit.body).opacity(0.5)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Room for the longest page, so the buttons stay put.
            .frame(height: 104, alignment: .top)
            .id(page)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)),
                removal: .opacity.combined(with: .offset(x: forward ? -24 : 24))))

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule().fill(i == page ? Color.vault : Color.ink.opacity(0.15)).frame(width: i == page ? 16 : 6, height: 6)
                }
            }
            .animation(Motion.change, value: page)
            .accessibilityElement()
            .accessibilityLabel("Page \(page + 1) of \(pages.count)")

            HStack(spacing: Kit.Space.item) {
                if page > 0 {
                    Button("Back") { go(-1) }.buttonStyle(.secondary)
                }
                Button(page == pages.count - 1 ? "Make My Vault" : "Next") { page == pages.count - 1 ? done() : go(1) }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Kit.Space.item)

            Button("Skip", action: done).buttonStyle(.quiet).opacity(page == pages.count - 1 ? 0 : 1)
        }
        .frame(width: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Glass.lightRoom / 2)
        .entrance()
        .onAppear { ActivityLog.note("welcome tour") }
    }

    private func go(_ step: Int) {
        forward = step > 0
        withAnimation(Motion.change) { page += step }
    }
}
