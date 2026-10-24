import AppKit
import SwiftUI

// The look the windows and the menu-bar panel share, after the landing page
// (site/index.html): black, with an electric-blue glow rising from below the
// top and teal at the edges, light-blue accents, and a tall condensed
// wordmark filled with a white-to-blue gradient. The windows are always dark.

enum Theme {
    /// The blue of the glow.
    static let blue = Color(red: 47 / 255, green: 61 / 255, blue: 255 / 255)
    /// The recording pill's bars and the accents.
    static let ice = Color(red: 181 / 255, green: 209 / 255, blue: 255 / 255)
    static let teal = Color(red: 14 / 255, green: 110 / 255, blue: 120 / 255)
    /// The wordmark's fill, top to bottom.
    static let wordmark = LinearGradient(
        colors: [.white, Color(red: 0.87, green: 0.91, blue: 1), Color(red: 0.62, green: 0.72, blue: 1)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Dark Aqua, so controls and text read on the black backdrop.
    static func applyAppearance(to window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        // The backdrop runs under a transparent title bar.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
    }
}

/// Black with the blue glow centered `glowAt` down the view, and teal at the
/// upper corners.
struct Backdrop: View {
    /// Where the blue glow is centered, as a fraction of the height.
    var glowAt: CGFloat = 0.16
    /// How strong the glow is, 0 to 1.
    var intensity: Double = 1

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                RadialGradient(
                    colors: [Theme.blue.opacity(0.95 * intensity), Theme.blue.opacity(0.4 * intensity), .clear],
                    center: UnitPoint(x: 0.5, y: glowAt),
                    startRadius: 0,
                    endRadius: max(size.width, 320) * 0.62
                )
                .scaleEffect(x: 1, y: 0.62, anchor: UnitPoint(x: 0.5, y: glowAt))
                RadialGradient(
                    colors: [Theme.teal.opacity(0.55 * intensity), .clear],
                    center: UnitPoint(x: 0, y: 0.05),
                    startRadius: 0,
                    endRadius: size.width * 0.5
                )
                RadialGradient(
                    colors: [Theme.teal.opacity(0.5 * intensity), .clear],
                    center: UnitPoint(x: 1, y: 0.05),
                    startRadius: 0,
                    endRadius: size.width * 0.5
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// "HYPERTALK" in a tall, heavy, compressed face with the gradient fill.
struct Wordmark: View {
    var size: CGFloat = 54

    var body: some View {
        Text("HYPERTALK")
            .font(.system(size: size, weight: .black).width(.compressed))
            .tracking(size * 0.01)
            .foregroundStyle(Theme.wordmark)
            .shadow(color: Theme.blue.opacity(0.55), radius: size * 0.35)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Small uppercase monospaced text, like the landing page's corner labels.
struct MonoLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}
