// Draws docs/assets/app-icon.png, the 1024 px source for Hypertalk.app's icon:
// the logo (a white chat bubble with Tabler's bolt cut out of it, drawn as
// the menu bar's `MenuBarController.logo` is) on a black rounded square in
// the macOS icon grid (an 824 px body with a 100 px margin). A full-bleed or
// transparent icon gets a gray tile from macOS 26; this shape does not.
//
// Also writes docs/assets/icon.png and icon-dark.png, the README's logo in
// black and white.
//
//     swift scripts/make-app-icon.swift
import AppKit

let canvas: CGFloat = 1024
let body: CGFloat = 824
let corner: CGFloat = 185
/// The logo's width as a share of the body.
let logoScale: CGFloat = 0.6

/// The bubble, its viewBox cropped to it, as `MenuBarController.bubbleSVG`.
func bubbleSVG(fill: String) -> Data {
    Data("""
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="2.8 2.6 18.4 18.4">\
    <path fill="\(fill)" d="M12 3.2c5 0 9 3.4 9 7.6s-4 7.6-9 7.6c-1 0-2-.1-2.9-.4L4.6 20.4l1.2-3.9C4.1 15.1 3 13.1 3 10.8 3 6.6 7 3.2 12 3.2z"/>\
    </svg>
    """.utf8)
}

/// Tabler Icons "bolt" (filled), MIT License, as `MenuBarController.boltSVG`.
let boltSVG = Data("""
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\
    <path d="M13 2l.018 .001l.016 .001l.083 .005l.011 .002h.011l.038 .009l.052 .008l.016 .006l.011 .001l.029 .011l.052 .014l.019 .009l.015 .004l.028 .014l.04 .017l.021 .012l.022 .01l.023 .015l.031 .017l.034 .024l.018 .011l.013 .012l.024 .017l.038 .034l.022 .017l.008 .01l.014 .012l.036 .041l.026 .027l.006 .009c.12 .147 .196 .322 .218 .513l.001 .012l.002 .041l.004 .064v6h5a1 1 0 0 1 .868 1.497l-.06 .091l-8 11c-.568 .783 -1.808 .38 -1.808 -.588v-6h-5a1 1 0 0 1 -.868 -1.497l.06 -.091l8 -11l.01 -.013l.018 -.024l.033 -.038l.018 -.022l.009 -.008l.013 -.014l.04 -.036l.028 -.026l.008 -.006a1 1 0 0 1 .402 -.199l.011 -.001l.027 -.005l.074 -.013l.011 -.001l.041 -.002z"/>\
    </svg>
    """.utf8)

/// The logo in `rect`: the bubble with the bolt cut out of its body, placed
/// as `MenuBarController.logo(side:)` places it. Draw into a clear layer:
/// the cut clears whatever is under it.
func drawLogo(in rect: NSRect, fill: String) {
    NSImage(data: bubbleSVG(fill: fill))!.draw(in: rect)
    let box = rect.width * 0.6
    let center = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.554)
    NSImage(data: boltSVG)!.draw(
        in: NSRect(x: center.x - box / 2, y: center.y - box / 2, width: box, height: box),
        from: .zero, operation: .destinationOut, fraction: 1
    )
}

func bitmap(_ side: CGFloat, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

guard FileManager.default.fileExists(atPath: "docs/assets") else {
    fatalError("run from the repository root: docs/assets not found")
}

let icon = bitmap(canvas) {
    let margin = (canvas - body) / 2
    // The soft drop shadow macOS icons carry.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(
        roundedRect: NSRect(x: margin, y: margin, width: body, height: body),
        xRadius: corner, yRadius: corner
    ).fill()
    NSShadow().set()

    let side = body * logoScale
    let logoRect = NSRect(x: (canvas - side) / 2, y: (canvas - side) / 2, width: side, height: side)
    let logo = NSImage(size: logoRect.size, flipped: false) { rect in
        drawLogo(in: rect, fill: "white")
        return true
    }
    logo.draw(in: logoRect)
}
write(icon, "docs/assets/app-icon.png")

for (fill, path) in [("black", "docs/assets/icon.png"), ("white", "docs/assets/icon-dark.png")] {
    let readme = bitmap(256) {
        drawLogo(in: NSRect(x: 0, y: 0, width: 256, height: 256), fill: fill)
    }
    write(readme, path)
}
