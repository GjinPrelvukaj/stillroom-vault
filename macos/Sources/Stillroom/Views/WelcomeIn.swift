import AppKit
import SwiftUI

/// The moment a licence checks out: the window blurs behind a card that welcomes the buyer by name, the vault's ring of
/// dots fills, and violet confetti bursts out from behind the card once. With Reduce Motion it only fades in.
/// The same in either vault (the licence is shared), so it tells nothing about which is open.
struct WelcomeIn: View {
    let license: License
    let done: () -> Void
    @State private var shown = false
    @State private var filled = 0.0
    /// The words, then the button, come in after the ring has started: one thing at a time, not all at once.
    @State private var words = false
    @State private var button = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// "Ada" from "Ada Lovelace"; a company or an email address stays whole.
    private var firstName: String {
        let name = license.name
        guard license.edition != .teams, !name.contains("@") else { return name }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var message: String {
        switch license.edition {
        case .personal:
            "Thank you for backing a small, independent app. Your vault has no limit now, on every Mac of yours, and every 1.x update is yours."
        case .family:
            "Thank you for bringing your family in. The same key works for up to \(license.seats) people: each adds it on their own Mac, and each vault stays their own."
        case .teams:
            "Thank you for trusting Stillroom with your team's work. The key covers \(license.seats) people, each with a vault of their own that nobody else can open."
        }
    }

    var body: some View {
        ZStack {
            Color.ground.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: done)
                .accessibilityHidden(true)
            if !reduceMotion && shown { Confetti().ignoresSafeArea() }
            card
                .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            guard !reduceMotion else {
                withAnimation(.easeOut(duration: 0.3)) { shown = true; filled = 1; words = true; button = true }
                return
            }
            // Slow on purpose: a moment to take in, not a flash. About two and a half seconds until the button.
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { shown = true }
            withAnimation(.easeInOut(duration: 2.2).delay(0.3)) { filled = 1 }
            withAnimation(.easeOut(duration: 0.8).delay(0.9)) { words = true }
            withAnimation(.easeOut(duration: 0.7).delay(2.0)) { button = true }
        }
    }

    private var card: some View {
        VStack(spacing: Kit.Space.group) {
            ZStack {
                DotRing(lit: filled, tint: .vault, count: 48, dot: 3.6)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.vault)
                    .scaleEffect(filled > 0.6 || reduceMotion ? 1 : 0.6)
                    .opacity(filled > 0.3 || reduceMotion ? 1 : 0)
                    .animation(.spring(response: 0.7, dampingFraction: 0.7), value: filled > 0.6)
            }
            .frame(width: 96, height: 96)

            VStack(spacing: Kit.Space.label) {
                Text(license.edition.name).eyebrow()
                    .opacity(words ? 1 : 0)
                Text("Welcome in, \(firstName).").font(Kit.title)
                Text(message)
                    .font(Kit.body).opacity(0.6)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(words ? 1 : 0)
            .offset(y: words ? 0 : 8)

            Button("Start Using It", action: done)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .padding(.top, Kit.Space.item)
                .opacity(button ? 1 : 0)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 32)
        .frame(width: 420)
        .card()
        .onExitCommand(perform: done)
        .accessibilityLabel("Welcome in, \(firstName). \(message)")
    }
}

/// One burst of violet paper from the middle of the window, drifting down under light gravity and gone in about five
/// seconds. Drawn in one Canvas; it stops redrawing once the last piece has gone.
private struct Confetti: View {
    private struct Piece {
        let angle: Double, speed: Double, spin: Double, size: CGSize, color: Color, delay: Double, round: Bool
    }

    private static let life = 5.0
    private let started = Date()
    @State private var over = false
    private let pieces: [Piece] = {
        let colors: [Color] = [.vault, .vault.opacity(0.7), .hex(0xD9C6FF), .hex(0x8A63F0), .hex(0xF2B8E6), .ink.opacity(0.8)]
        return (0..<140).map { _ in
            Piece(angle: .random(in: (-.pi * 0.95)...(-.pi * 0.05)),
                  speed: .random(in: 300...760),
                  spin: .random(in: -6...6),
                  size: CGSize(width: .random(in: 5...9), height: .random(in: 8...14)),
                  color: colors.randomElement()!,
                  delay: .random(in: 0...0.35),
                  round: Bool.random() && Bool.random())
        }
    }()

    var body: some View {
        TimelineView(.animation(paused: over)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(started)
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.45)
                for piece in pieces {
                    let age = t - piece.delay
                    guard age > 0, age < Self.life else { continue }
                    // Thrown out and up, slowed by the air, pulled down.
                    let drag = (1 - exp(-1.4 * age)) / 1.4
                    let x = origin.x + cos(piece.angle) * piece.speed * drag
                    let y = origin.y + sin(piece.angle) * piece.speed * drag + 0.5 * 300 * age * age
                    var c = context
                    c.opacity = min(1, (Self.life - age) / 1.5)
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(piece.spin * age))
                    // A flat piece turning over: its width shrinks and grows.
                    c.scaleBy(x: cos(piece.spin * age * 0.7), y: 1)
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2, width: piece.size.width, height: piece.size.height)
                    c.fill(piece.round ? Path(ellipseIn: rect.insetBy(dx: 0, dy: 2)) : Path(roundedRect: rect, cornerRadius: 1.5), with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(Self.life + 0.3))
            over = true
        }
    }
}
