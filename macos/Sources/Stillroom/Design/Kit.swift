// After Tally's Design/Kit.swift, Glass.swift and SheetCard.swift (2026-10-23), trimmed to what Stillroom uses.
import AppKit
import SwiftUI

/// The few sizes, buttons and surfaces every screen uses, so they read as one app (and as Tally and Brimlight).
/// Change a look here, never inline in a screen.
enum Kit {
    /// Words in rows and cards.
    static let body = Font.system(size: 13)
    /// The quiet line under a figure or a row.
    static let quiet = Font.system(size: 11.5)
    /// A screen's or a card's title.
    static let title = Font.system(size: 20, weight: .semibold)
    /// Long text to read and write: a note.
    static let reading = Font.system(size: 14)
    /// A number that stands out on its own: the sidebar's total, a two-factor code, a recovery key (`.monospaced()`).
    static let figure = Font.system(size: 17, weight: .semibold)
    /// The few big figures on the Security tab.
    static let hero = Font.system(size: 24, weight: .semibold, design: .rounded)
    /// Text shown as it is: previews of text files, a kit's pieces.
    static let mono = Font.system(size: 12, design: .monospaced)
    /// A tag's word in its chip, and the smallest labels.
    static let chip = Font.system(size: 10.5, weight: .medium)
    /// Chevrons and the digits inside a small ring.
    static let micro = Font.system(size: 9, weight: .semibold)
    /// A symbol at the centre of a ring or an item's tile.
    static let glyph = Font.system(size: 22, weight: .medium)
    /// The large faint symbol that stands in for something that can't be shown.
    static let placeholder = Font.system(size: 28, weight: .light)
    /// Every button is this tall, so a row of them lines up.
    static let control: CGFloat = 28
    /// Every field, and a button that sits beside one (Search, New Folder), on the lock screen and in the header alike.
    static let field: CGFloat = 32
    /// The widest a column of text to read gets: about 68 characters of a note.
    static let measure: CGFloat = 620
    /// The widest a screen's content gets: a row's name and its size stay close however wide the window.
    static let readable: CGFloat = 820

    /// The only gaps used, smallest to largest.
    enum Space {
        /// A label and what it labels.
        static let label: CGFloat = 6
        /// Rows or buttons next to each other.
        static let item: CGFloat = 8
        /// One part of a screen and the next.
        static let group: CGFloat = 16
        /// Round a card's edge.
        static let edge: CGFloat = 20
    }
}

extension Color {
    /// Vault's one colour, everywhere it's purple: the light round the window and the icon, toggles, folders, tags.
    /// Lilac on black; on paper, the website's deeper violet, so it keeps its contrast.
    static let vault = adaptive(dark: 0xB08CFF, light: 0x6043CA)
    /// What sits on the ground: text's own colour, and at low opacity every faint fill and hairline. White on black,
    /// near-black on paper. Use it where a dark-only screen would say `.white`.
    static let ink = adaptive(dark: 0xFFFFFF, light: 0x17151F)
    /// The window's and every sheet's surface: black glass, or warm paper (the website's) in the light appearance.
    static let ground = adaptive(dark: 0x000000, light: 0xF7F6F2)
    /// Secondary text: dates, details, the line under a row. Ink faded only as far as it still reads (WCAG AA, 4.5:1)
    /// on either ground. Low opacity is for fills and hairlines, never words.
    static let quietInk = adaptive(dark: 0xFFFFFF, light: 0x17151F, darkAlpha: 0.55, lightAlpha: 0.64)
    /// A field's hint before anything is typed: fainter than quiet text, still readable.
    static let hintInk = adaptive(dark: 0xFFFFFF, light: 0x17151F, darkAlpha: 0.4, lightAlpha: 0.5)
    /// Something to take care over: a protection that's off, an action that can't be undone. Amber on paper.
    static let caution = adaptive(dark: 0xFF9F0A, light: 0xB45309)
    /// Something went wrong.
    static let problem = adaptive(dark: 0xFF6961, light: 0xC0262D)
    /// An empty ring's unlit dots and a timer's track: faint, but still there on paper.
    static let track = adaptive(dark: 0xFFFFFF, light: 0x17151F, darkAlpha: 0.1, lightAlpha: 0.16)
    /// Over the window behind a card: a dim on black; on paper only a light veil, so the blur does the work.
    static let scrim = adaptive(dark: 0x000000, light: 0x17151F, darkAlpha: 0.35, lightAlpha: 0.12)

    static func hex(_ rgb: UInt32) -> Color { Color(nsColor: .hex(rgb)) }

    /// One colour for the dark appearance and one for the light, picked as each view is drawn.
    static func adaptive(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) {
            $0.isDark ? .hex(dark).withAlphaComponent(darkAlpha) : .hex(light).withAlphaComponent(lightAlpha)
        })
    }
}

extension NSColor {
    static func hex(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension View {
    /// The small capital label over a screen or a card ("ALL FILES", "SETTINGS").
    func eyebrow() -> some View {
        font(Living.caption).tracking(0.8).textCase(.uppercase).foregroundStyle(Color.quietInk)
    }

    /// Secondary text, in the one colour that still reads in both appearances.
    func quietText() -> some View { foregroundStyle(Color.quietInk) }

    /// Every sheet's surface: the ground, a faint light along its bottom, one of two widths, the same room inside,
    /// hidden from screen capture.
    func sheetCard(_ width: SheetWidth = .question) -> some View {
        padding(Kit.Space.edge)
            .frame(width: width.rawValue)
            .background {
                ZStack {
                    Color.ground
                    EdgeLight(colors: [.vault], strength: 0.3)
                }
                .ignoresSafeArea()
            }
            .hiddenFromCapture()
    }

    /// The label over a group in the sidebar ("Kinds").
    func groupLabel() -> some View {
        font(Kit.quiet.weight(.semibold)).foregroundStyle(Color.quietInk)
    }

    /// A screen's content right of the sidebar: the same room round every one, no wider than `Kit.readable`.
    /// `wide` (lists): uses the whole width, so a full-screen window isn't mostly empty. Either way it starts at the
    /// same left edge, so opening a note or Settings from a list doesn't move the page sideways.
    func pane(wide: Bool = false) -> some View {
        frame(maxWidth: wide ? .infinity : Kit.readable, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, Glass.lightRoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A list's rows on one quiet rounded panel.
    func rowPanel() -> some View {
        background(Color.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ink.opacity(0.06), lineWidth: 1))
    }

    /// The glass a card sits on: the ground (black, or paper), a hairline round it, light along its bottom edge.
    func card() -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            ZStack {
                shape.fill(Color.ground)
                EdgeLight(colors: [.vault])
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.ink.opacity(0.1), lineWidth: 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// The window itself: black glass (paper in the light appearance) with continuous corners, a hairline round it, and colour only as light from the
/// bottom edge. Grey while locked; Vault's colour once open, brighter while files are dragged over it.
struct Glass: View {
    let open: Bool
    let bright: Bool

    /// How far up from the bottom edge its light reaches: content stays above it.
    static let lightRoom: CGFloat = 48

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        ZStack {
            shape.fill(Color.ground)
            EdgeLight(colors: [.vault], strength: 0.8).opacity(open ? 0 : 1)
            EdgeLight(colors: [.vault]).opacity(open ? 1 : 0)
            EdgeLight(colors: [.vault], strength: 1.4).opacity(bright ? 1 : 0)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.ink.opacity(0.08), lineWidth: 1))
        .background(WindowEdge())
        .animation(Motion.change, value: open)
        .animation(Motion.change, value: bright)
        .ignoresSafeArea()
    }
}

/// The window under the glass: see-through, so only the glass's own 22-point corners show, never the system's
/// smaller ones. The shadow is worked out again from what's drawn whenever the layout changes, so it follows the
/// glass's curve too.
private struct WindowEdge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Watcher() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Watcher: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            DispatchQueue.main.async { window.invalidateShadow() }
        }
        override func layout() { super.layout(); window?.invalidateShadow() }
    }
}

/// The three buttons: the one action (lit in Vault's colour), a second choice (grey glass), and leaving (plain words).
/// `menu` is a second choice that opens a menu: grey glass with the up-down chevron of a pop-up.
enum KitButton {
    case primary, secondary, quiet, menu
}

struct KitButtonStyle: ButtonStyle {
    var kind: KitButton
    var tint: Color = .vault
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(kind == .primary ? .system(size: 13, weight: .medium) : Kit.body)
            .lineLimit(1)
        Group {
            switch kind {
            // Waiting for input, the one action keeps its shape: a fainter fill, its words dimmed, never a smudge.
            case .primary: label.opacity(enabled ? 1 : 0.5).modifier(Capsuled(fill: tint.opacity(enabled ? 0.32 : 0.18), padding: 16))
            case .secondary: label.modifier(Capsuled(fill: Color.ink.opacity(0.1), padding: 14))
            case .menu:
                HStack(spacing: Kit.Space.label) {
                    label
                    Image(systemName: "chevron.up.chevron.down").font(Kit.micro).opacity(0.6)
                }
                .modifier(Capsuled(fill: Color.ink.opacity(0.1), padding: 14))
            // Faded, not recoloured, so a tinted quiet button keeps its colour; less on paper, where it must still read.
            case .quiet: label.opacity(scheme == .dark ? 0.6 : 0.72).frame(height: Kit.control).contentShape(Rectangle())
                .focusRing(RoundedRectangle(cornerRadius: 6, style: .continuous)).hoverLift()
            }
        }
        .opacity(enabled || kind == .primary ? 1 : 0.4)
        // Answered on the press itself: a little smaller and dimmer, never larger.
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .brightness(configuration.isPressed ? (scheme == .dark ? -0.08 : 0.04) : 0)
        .animation(Motion.hover, value: configuration.isPressed)
    }
}

/// A capsule button's body: one height everywhere, a faint hairline so it reads as glass.
private struct Capsuled: ViewModifier {
    var fill: Color
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, padding)
            .frame(height: Kit.control)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.ink.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
            .focusRing(Capsule())
            .hoverLift()
    }
}

extension ButtonStyle where Self == KitButtonStyle {
    static var primary: KitButtonStyle { KitButtonStyle(kind: .primary) }
    static func primary(_ tint: Color) -> KitButtonStyle { KitButtonStyle(kind: .primary, tint: tint) }
    static var secondary: KitButtonStyle { KitButtonStyle(kind: .secondary) }
    static var quiet: KitButtonStyle { KitButtonStyle(kind: .quiet) }
    static var menu: KitButtonStyle { KitButtonStyle(kind: .menu) }
}

/// A symbol-only button (show, copy, more): its own round plate on hover and press, so it reads as a button and not
/// a stray glyph. Works for a `Menu` with `.menuStyle(.button)` too.
struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.quietInk)
            .frame(width: 24, height: 24)
            .background(Color.ink.opacity(configuration.isPressed ? 0.14 : hovering && enabled ? 0.08 : 0), in: Circle())
            .contentShape(Circle())
            .focusRing(Circle())
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.hover, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

/// A button that sits beside a field (New Folder next to Search): the field's own shape, fill and height, so the
/// two read as one bar rather than a field and a pill.
struct FieldButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Kit.body)
            .lineLimit(1)
            .opacity(hovering ? 0.9 : 0.6)
            .padding(.horizontal, 11)
            .frame(minWidth: Kit.field, minHeight: Kit.field, maxHeight: Kit.field)
            .background(Color.ink.opacity(configuration.isPressed ? 0.12 : hovering ? 0.09 : 0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.ink.opacity(0.06), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .focusRing(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
    }
}

extension ButtonStyle where Self == FieldButtonStyle {
    static var field: FieldButtonStyle { FieldButtonStyle() }
}

/// An on/off in the app's own glass: a small capsule whose knob slides and whose track lights.
struct GlassSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                configuration.label.font(Kit.body)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Color.vault.opacity(0.55) : Color.ink.opacity(scheme == .dark ? 0.14 : 0.18))
                    Circle().fill(.white).shadow(color: .black.opacity(0.18), radius: 1, y: 0.5).padding(2)
                }
                .frame(width: 36, height: 22)
                .focusRing(Capsule())
                .animation(Motion.or(Motion.change, reduce: reduceMotion), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

extension ToggleStyle where Self == GlassSwitchStyle {
    static var glass: GlassSwitchStyle { GlassSwitchStyle() }
}

/// A section in the sidebar: its symbol and name, a count on the right, the chosen one on a soft highlight.
struct SidebarItemStyle: ButtonStyle {
    var chosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Kit.body)
            .opacity(chosen ? 0.95 : 0.65)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.ink.opacity(chosen ? 0.1 : configuration.isPressed ? 0.05 : 0),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .focusRing(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension ButtonStyle where Self == SidebarItemStyle {
    static func sidebarItem(chosen: Bool) -> SidebarItemStyle { SidebarItemStyle(chosen: chosen) }
}

/// A line to type in that reads as one: a faint rounded fill, brighter while typing, its hint drawn faint
/// (a field's own prompt shows almost as bright as typed text).
struct GlassField: View {
    let hint: String
    @Binding var text: String
    var secure = false
    var symbol: String?
    var autofocus = false
    /// Raised to put the cursor here, at the end of what's typed (⌘F, or typing in a list).
    var focusRequest = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Kit.Space.item) {
            if let symbol { Image(systemName: symbol).font(Kit.body).opacity(focused ? 0.8 : 0.45) }
            Group {
                if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .font(Kit.body)
            .textFieldStyle(.plain)
            .focused($focused)
            .accessibilityLabel(hint)
            .overlay(alignment: .leading) {
                if text.isEmpty { Text(hint).font(Kit.body).foregroundStyle(Color.hintInk).allowsHitTesting(false).accessibilityHidden(true) }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Kit.field)
        .background(Color.ink.opacity(focused ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.ink.opacity(focused ? 0.14 : 0.06), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { if autofocus { focused = true } }
        .onChange(of: focusRequest) {
            focused = true
            // Focusing selects what's there; the cursor goes after it instead, so typing carries on.
            DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil) }
        }
        .animation(Motion.hover, value: focused)
    }
}

/// A choice of a few in one glass capsule, the chosen one lit in Vault's colour, the way a primary button is lit.
/// For tabs and short plans, in place of the system's blue segmented control.
struct Segments<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Namespace private var lit

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let chosen = option.value == selection
                Button { withAnimation(Motion.change) { selection = option.value } } label: {
                    Text(option.title)
                        .font(chosen ? .system(size: 13, weight: .medium) : Kit.body)
                        .opacity(chosen ? 1 : 0.6)
                        .padding(.horizontal, 14)
                        .frame(height: Kit.control - 4)
                        .background {
                            if chosen {
                                Capsule().fill(Color.vault.opacity(0.32)).matchedGeometryEffect(id: "lit", in: lit)
                            }
                        }
                        .contentShape(Capsule())
                        .focusRing(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.ink.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.ink.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Scrolling content fades out as it reaches the window's bottom light, so nothing sits sharp and half-readable
    /// on the glow. The fade covers `Glass.lightRoom`, which `.pane()` leaves empty at the end of a page, so the last
    /// row is still fully clear once scrolled to.
    func fadesIntoLight() -> some View {
        mask {
            VStack(spacing: 0) {
                Color.black
                // Gone before the light's brightest part, so nothing is left half-readable on it.
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Glass.lightRoom)
            }
            .ignoresSafeArea()
        }
    }
}

/// How wide a sheet is: a question (a name, a password, a yes or no), a task (a kit, a check, a list of versions),
/// or a photo.
enum SheetWidth: CGFloat {
    case question = 400, task = 480, photo = 560
}

/// A kit control's keyboard focus (Tab in a sheet, Full Keyboard Access): a violet line round its own shape, in place
/// of the system's blue ring.
struct FocusRing<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay(shape.strokeBorder(Color.vault.opacity(0.6), lineWidth: 2).opacity(focused ? 1 : 0).allowsHitTesting(false))
    }
}

extension View {
    func focusRing<S: InsettableShape>(_ shape: S) -> some View { modifier(FocusRing(shape: shape)) }
}

/// A tag, the same everywhere: its colour's dot and its word on a soft capsule of that colour. Chosen (in the Tags
/// sheet), a check takes the dot's place; not chosen there, the capsule is only a faint outline.
struct TagChip: View {
    let tag: String
    var chosen: Bool?

    var body: some View {
        let color = TagColor.of(tag)
        HStack(spacing: 5) {
            if chosen == true {
                Image(systemName: "checkmark").font(Kit.micro)
            } else {
                TagDot(tag: tag)
            }
            Text(tag).font(Kit.chip).lineLimit(1)
        }
        .foregroundStyle(chosen == false ? Color.quietInk : color)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(chosen == false ? Color.ink.opacity(0.04) : color.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(chosen == false ? Color.ink.opacity(0.1) : .clear, lineWidth: 1))
    }
}

/// A tag's colour as a dot: in its chip, and beside its name in the sidebar.
struct TagDot: View {
    let tag: String
    var body: some View { Circle().fill(TagColor.of(tag)).frame(width: 7, height: 7) }
}

/// An item's own page, the same look everywhere it has one (its editor, its card, its cool-down): its symbol in a
/// soft tile of Vault's colour.
struct ItemTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(Kit.glyph)
            .foregroundStyle(Color.vault)
            .frame(width: 46, height: 46)
            .background(Color.vault.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.vault.opacity(0.22), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
