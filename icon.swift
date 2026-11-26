import AppKit

// Renders the 1024 px app icon: a black squircle with the white walking figure.
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let inset = r.insetBy(dx: 100, dy: 100)
    let shape = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 1),
               ending: NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))!.draw(in: shape, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: 520, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let sym = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    sym.draw(in: NSRect(x: (size - sym.size.width) / 2, y: (size - sym.size.height) / 2,
                        width: sym.size.width, height: sym.size.height))
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
