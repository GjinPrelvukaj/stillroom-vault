// Copied from Tally (Sources/BudgetKit/Design/Living.swift, itself from Brimlight) on 2026-10-23,
// trimmed to the pieces Stillroom uses. Change a look here, never inline in a screen.
import SwiftUI

/// Brimlight's language: one living thing made of dots or light, colour arriving as light from the window's
/// edge, quiet words given room, nothing moving unless something is happening.
enum Living {
    /// The quiet second line under a figure.
    static let caption = Font.system(size: 10.5, weight: .medium)
}

/// The motions everything uses, so each kind of change feels the same everywhere: springs, never a fixed-time ease.
/// Critically damped: nothing here was thrown by a gesture, so nothing overshoots (only the lock screen's shake bounces).
enum Motion {
    /// The pointer's touch: a hover lighting or lifting a button.
    static let hover = Animation.spring(response: 0.2, dampingFraction: 1)
    /// Something that changed: a value, a row, a switch, a light coming on.
    static let change = Animation.spring(response: 0.3, dampingFraction: 1)
    /// Something arriving: a screen's content, a card.
    static let appear = Animation.spring(response: 0.38, dampingFraction: 1)
    /// A light that lingers, then fades: a row that just arrived.
    static let linger = Animation.spring(response: 1.2, dampingFraction: 1)
    /// With Reduce Motion: a short fade in place of any of them.
    static let reduced = Animation.easeOut(duration: 0.18)

    static func or(_ animation: Animation, reduce: Bool) -> Animation { reduce ? reduced : animation }
}

/// A page arriving, the same way everywhere: it fades in as it rises a few points into place. `ready` holds it back
/// until what it shows has loaded, so nothing pops in a moment later. With Reduce Motion, it only fades.
struct Entrance: ViewModifier {
    var ready = true
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear { arrive() }
            .onChange(of: ready) { arrive() }
    }

    private func arrive() {
        guard ready, !shown else { return }
        withAnimation(Motion.appear) { shown = true }
    }
}

extension View {
    func entrance(ready: Bool = true) -> some View { modifier(Entrance(ready: ready)) }

    /// An item's name, carried from its row into its editor's heading as it opens (and back), so opening reads as
    /// one thing moving rather than a page swap. Nothing moves with Reduce Motion (the namespace is left out then).
    @ViewBuilder func itemTitle(_ id: UUID, in titles: Namespace.ID?) -> some View {
        if let titles { matchedGeometryEffect(id: id, in: titles, properties: .position, anchor: .leading) } else { self }
    }
}

extension EnvironmentValues {
    /// Where list rows and editors match their item's name (VaultView's); nil with Reduce Motion.
    @Entry var itemTitles: Namespace.ID?
}

/// Colour as light: soft lobes along the bottom edge, still, so it costs nothing to keep on screen.
struct EdgeLight: View {
    /// Left to right; three to five reads best.
    let colors: [Color]
    var strength: Double = EdgeLight.panel
    static let panel = 0.7
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // One colour as three lobes of it: one wide lobe reads brighter than three.
            let lobes = colors.count == 1 ? Array(repeating: colors[0], count: 3) : colors
            ZStack {
                ForEach(Array(lobes.enumerated()), id: \.offset) { i, color in
                    let x = w * (CGFloat(i) + 0.5) / CGFloat(lobes.count)
                    Ellipse()
                        .fill(RadialGradient(colors: [color.opacity(0.75 * strength), color.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: w / CGFloat(lobes.count)))
                        .frame(width: w / CGFloat(lobes.count) * 2, height: min(h, 76))
                        .position(x: x, y: h + 16)
                }
            }
            // Light adds on black; on paper adding light shows nothing, so the colour is laid on like ink instead.
            .blendMode(scheme == .dark ? .plusLighter : .multiply)
            .blur(radius: 12)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A ring of dots lit from the top, clockwise. Unlit dots are a faint track, so an empty ring still reads as one.
struct DotRing: View {
    /// How much of the ring is lit, 0 to 1.
    let lit: Double
    let tint: Color
    /// The unlit dots' colour, when they mean something (Check vault's damaged share).
    var rest: Color?
    var count = 48
    var dot: CGFloat = 3.2
    /// Which dots are lit, anywhere round the ring, in place of lighting them in order; the newest drawn larger.
    var pattern: Set<Int>?
    var newest: Int?

    var body: some View {
        let on = Int((Double(count) * min(1, max(0, lit))).rounded(.up))
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2 - dot
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ForEach(0..<count, id: \.self) { i in
                let isOn = pattern.map { $0.contains(i) } ?? (i < on)
                // The newest lit dot is larger: the ring's leading edge.
                let edge = pattern == nil ? i == on - 1 : i == newest
                let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
                Circle()
                    .fill(isOn ? tint : rest ?? Color.track)
                    .frame(width: edge ? dot * 1.6 : dot, height: edge ? dot * 1.6 : dot)
                    .shadow(color: isOn ? tint.opacity(0.6) : .clear, radius: 2)
                    .position(x: c.x + r * cos(a), y: c.y + r * sin(a))
            }
        }
        // Drawn once into one image per change: many glowing dots redrawn every frame cost a lot.
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// A ring of dots round one symbol: the mark of an empty page, and of Check vault's progress.
struct RingMark: View {
    let symbol: String
    var lit: Double = 0
    var tint: Color = .vault
    var rest: Color?
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            DotRing(lit: lit, tint: tint, rest: rest)
            Image(systemName: symbol)
                .font(Kit.glyph.weight(.light))
                .foregroundStyle(tint.opacity(lit >= 1 ? 1 : 0.75))
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .animation(Motion.change, value: lit)
    }
}

/// An empty page, the same everywhere: the ring mark, a title, one line, and what to do (lists, the intruder log).
struct EmptyState<Extra: View>: View {
    let symbol: String
    let title: String
    let line: String
    var lit: Double = 0
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: Kit.Space.group) {
            RingMark(symbol: symbol, lit: lit)
            VStack(spacing: Kit.Space.label) {
                Text(title).font(Kit.title)
                Text(line).font(Kit.body).quietText().frame(maxWidth: 340)
            }
            extra
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Glass.lightRoom)
    }
}

extension EmptyState where Extra == EmptyView {
    init(symbol: String, title: String, line: String) {
        self.init(symbol: symbol, title: title, line: line) { EmptyView() }
    }
}

/// Lifts what it is on while the pointer rests there: brighter, slightly larger.
struct HoverLift: ViewModifier {
    @State private var hovering = false
    @State private var width: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// About the same few points of growth for an icon and for a wide button.
    static func scale(width: CGFloat) -> CGFloat { 1 + min(0.07, 3 / max(width, 1)) }

    func body(content: Content) -> some View {
        content
            .brightness(hovering ? (scheme == .dark ? 0.12 : -0.08) : 0)
            .scaleEffect(hovering && !reduceMotion ? HoverLift.scale(width: width) : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onHover { hovering = $0 }
            .pointerStyle(.link)
            .animation(Motion.hover, value: hovering)
    }
}

extension View {
    /// The sign something can be clicked: it lifts under the pointer.
    func hoverLift() -> some View { modifier(HoverLift()) }
}
