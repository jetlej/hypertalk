// Draws docs/assets/app-icon.png, the 1024 px source for Hypertalk.app's icon:
// the logo ("ripple" by Zach Bogart from the Noun Project, the same SVG as
// the menu bar's `MenuBarController.logoSVG`) in white on a black rounded
// square in the macOS icon grid (an 824 px body with a 100 px margin). A
// full-bleed or transparent icon gets a gray tile from macOS 26; this shape
// does not.
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

/// The rings, viewBox cropped to them, as `MenuBarController.logoSVG`.
func logoSVG(fill: String) -> Data {
    Data("""
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="4 4 92.6 92.6">\
    <path fill="\(fill)" d="M58.323,5.514c9.704,1.761 18.87,6.593 25.606,13.827c7.711,8.282 12.151,19.43 12.262,30.864c0,0.197 0,0.394 0,0.591c-0.108,11.158 -4.394,22.212 -11.89,30.459c-9.933,10.929 -25.364,16.542 -39.968,14.59c-10.111,-1.351 -19.712,-6.231 -26.812,-13.588c-12.226,-12.668 -16.263,-32.664 -9.339,-49.301c6.107,-14.676 20.35,-25.688 36.151,-27.8c2.265,-0.303 4.549,-0.424 6.829,-0.372c2.173,0.021 4.345,0.22 6.489,0.603c0.224,0.041 0.448,0.083 0.672,0.127Zm20.232,67.057c6.645,-6.946 10.915,-16.268 11.129,-26.31c0.006,-0.338 0.008,-0.676 0.007,-1.014c-0.098,-10.139 -4.226,-20.132 -11.335,-27.328c-6.955,-7.041 -16.678,-11.212 -26.562,-11.619c-0.81,-0.03 -1.621,-0.038 -2.431,-0.023c-1.391,0.03 -2.782,0.136 -4.163,0.321c-15.695,2.097 -29.513,14.486 -33.057,30.28c-0.616,2.745 -0.933,5.555 -0.951,8.369c-0.063,10.039 3.907,20.054 10.843,27.328c1.15,1.206 2.38,2.331 3.678,3.37c-6.656,-6.522 -10.96,-15.539 -11.021,-25.214c-0.057,-9.148 3.559,-18.266 9.876,-24.891c5.314,-5.572 12.507,-9.251 20.093,-10.545c1.815,-0.343 3.659,-0.511 5.505,-0.513c2.209,-0.035 4.421,0.137 6.6,0.527c16.045,2.873 29.046,17.802 29.419,34.499c0.005,0.308 0.007,0.616 0.006,0.923c-0.069,7.866 -2.8,15.657 -7.636,21.84Zm-9.66,-4.4c0.957,-0.77 1.866,-1.603 2.716,-2.494c5.028,-5.273 7.964,-12.437 8.078,-19.799c0.002,-0.189 0.003,-0.378 0.002,-0.567c-0.109,-11.232 -7.193,-22.016 -17.379,-26.548c-3.063,-1.363 -6.36,-2.158 -9.699,-2.395c-1.181,-0.074 -2.366,-0.088 -3.549,-0.042c-4.433,0.208 -8.821,1.395 -12.714,3.541c-12.322,6.794 -18.54,23.123 -12.995,36.685c1.601,3.917 4.107,7.432 7.214,10.303c-5.808,-7.151 -7.474,-17.517 -3.973,-26.084c3.386,-8.284 11.366,-14.525 20.247,-15.771c7.913,-1.109 16.286,1.71 21.912,7.405c4.733,4.791 7.456,11.548 7.436,18.262c-0.063,6.509 -2.848,12.797 -7.296,17.504Zm-6.485,-7.633c4.454,-3.612 7.304,-9.22 7.281,-15.162c-0.086,-8.951 -7.106,-17.377 -16.08,-18.866c-8.538,-1.415 -17.715,3.69 -20.996,11.717c-2.703,6.614 -1.319,14.697 3.425,20.042c0.668,0.752 1.397,1.443 2.176,2.07c-0.975,-1.164 -1.779,-2.469 -2.359,-3.887c-2.283,-5.585 -0.984,-12.443 3.186,-16.816c2.355,-2.47 5.555,-4.047 8.925,-4.594c0.319,-0.078 0.643,-0.141 0.972,-0.187c0.918,-0.129 1.841,-0.121 2.746,0.007c1.989,0.131 3.951,0.63 5.754,1.527c5.152,2.563 8.637,8.077 8.751,13.908c0.001,0.204 0.001,0.203 0,0.407c-0.071,3.614 -1.49,7.091 -3.781,9.834Zm-6.924,-7.332c2.459,-1.665 4.145,-4.507 4.205,-7.586c0.001,-0.12 0.001,-0.119 0,-0.239c-0.091,-4.692 -4.203,-8.819 -8.872,-9.105c-0.732,-0.007 -1.463,0.045 -2.187,0.154c-4.126,0.849 -7.44,4.819 -7.44,9.07c0,2.999 1.708,5.805 4.172,7.518c-0.424,-0.754 -0.672,-1.607 -0.672,-2.518c0,-2.548 1.912,-5.016 4.452,-5.602c3.282,-0.758 6.933,1.84 7.046,5.455c0.001,0.074 0.002,0.148 0.001,0.222c-0.018,0.923 -0.271,1.827 -0.705,2.631Z"/>\
    </svg>
    """.utf8)
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
    NSImage(data: logoSVG(fill: "white"))!.draw(in: logoRect)
}
write(icon, "docs/assets/app-icon.png")

for (fill, path) in [("black", "docs/assets/icon.png"), ("white", "docs/assets/icon-dark.png")] {
    let readme = bitmap(256) {
        NSImage(data: logoSVG(fill: fill))!.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
    }
    write(readme, path)
}
