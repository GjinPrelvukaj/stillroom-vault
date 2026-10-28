// Draws the app icon: a padlock on black glass, with violet light glowing in from all four edges (Tally's comes
// only from the bottom), in the app's own colour. The lock is drawn, not an SF Symbol: Apple's licence doesn't allow those in app icons.
// Usage: swift Scripts/make-icon.swift <out.png>   (make-icon.sh turns it into AppIcon.icns)
import AppKit
import SwiftUI

let violet = Color(red: 0xB0 / 255, green: 0x8C / 255, blue: 0xFF / 255)
/// The edge light: the app's one violet (Color.vault, #B08CFF).
let glow = Color(red: 0xB0 / 255, green: 0x8C / 255, blue: 0xFF / 255)

struct Icon: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(white: 0.11), .black], startPoint: .top, endPoint: .bottom))
            // The glow: violet light running round all four edges, as Tally's rises from its bottom one,
            // fading inward so the middle stays black behind the lock.
            Group {
                shape.strokeBorder(glow, lineWidth: 60)
                    .blur(radius: 52)
                    .opacity(0.8)
                shape.strokeBorder(glow, lineWidth: 8)
                    .blur(radius: 14)
                    .opacity(0.55)
            }
            // Added as light, as Tally's glow is, so it brightens the black rather than painting over it.
            .blendMode(.plusLighter)
            lock
            shape.strokeBorder(.white.opacity(0.1), lineWidth: 4)
        }
        .clipShape(shape)
        .frame(width: 824, height: 824)
        .frame(width: 1024, height: 1024)
    }

    /// A padlock: a shackle over a rounded body, with a keyhole.
    var lock: some View {
        let white = Color(white: 0.95)
        return VStack(spacing: -20) {
            UnevenRoundedRectangle(topLeadingRadius: 84, topTrailingRadius: 84, style: .continuous)
                .strokeBorder(white, lineWidth: 38)
                .frame(width: 168, height: 162)
                .mask(Rectangle().frame(height: 162))
            ZStack {
                RoundedRectangle(cornerRadius: 44, style: .continuous).fill(white).frame(width: 250, height: 200)
                VStack(spacing: -6) {
                    Circle().frame(width: 50, height: 50)
                    Capsule().frame(width: 22, height: 56)
                }
                .foregroundStyle(Color(white: 0.06))
            }
        }
        .compositingGroup()
        .shadow(color: violet.opacity(0.35), radius: 20)
        .offset(y: 12)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        fatalError("could not draw the icon")
    }
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
