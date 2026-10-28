// Generates the Quicklet app icon: a macOS Big Sur style squircle with a
// blue gradient, a white menu card, and a clicking cursor arrow.
//
// Usage: swiftc -o /tmp/make_icon scripts/make_icon.swift && /tmp/make_icon
// Writes Resources/Quicklet.icns plus /tmp/quicklet-icon-preview.png.
//
// Regenerate after changing the drawing code, then commit the .icns.

import AppKit

let canvas: CGFloat = 1024
let inset: CGFloat = 100          // Big Sur template: glyph sits inside 824x824
let cornerRadius: CGFloat = 185.4

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// MARK: - Background squircle with gradient

let shape = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2),
                         xRadius: cornerRadius, yRadius: cornerRadius)
context.saveGState()
shape.addClip()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.72, blue: 1.00, alpha: 1),   // #5CB8FF
    NSColor(srgbRed: 0.13, green: 0.36, blue: 0.91, alpha: 1),   // #215CE8
])!
gradient.draw(in: shape, angle: -65)

// Soft top highlight across the whole squircle so there is no seam where
// the gradient rect would end.
let highlight = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.0),
    NSColor.white.withAlphaComponent(0.20),
])!
highlight.draw(in: NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2),
               angle: 90)
context.restoreGState()

// MARK: - Menu card

let cardRect = NSRect(x: 268, y: 300, width: 392, height: 452)
let card = NSBezierPath(roundedRect: cardRect, xRadius: 56, yRadius: 56)

context.saveGState()
context.setShadow(offset: NSSize(width: 0, height: -22), blur: 46,
                  color: NSColor.black.withAlphaComponent(0.30).cgColor)
NSColor.white.setFill()
card.fill()
context.restoreGState()

// First menu row: highlighted pill (the "item you are about to click").
let rowX = cardRect.minX + 44
let pill = NSBezierPath(roundedRect: NSRect(x: rowX, y: cardRect.maxY - 128, width: 304, height: 84),
                        xRadius: 26, yRadius: 26)
NSColor(srgbRed: 0.16, green: 0.47, blue: 0.96, alpha: 1).setFill()
pill.fill()

// Two plain rows below it.
let line = NSBezierPath(roundedRect: NSRect(x: rowX, y: cardRect.maxY - 236, width: 240, height: 44),
                        xRadius: 22, yRadius: 22)
NSColor(srgbRed: 0.78, green: 0.82, blue: 0.88, alpha: 1).setFill()
line.fill()

let line2 = NSBezierPath(roundedRect: NSRect(x: rowX, y: cardRect.maxY - 316, width: 168, height: 44),
                         xRadius: 22, yRadius: 22)
line2.fill()

// MARK: - Cursor arrow

// Classic arrow outline, unit coordinates scaled to ~200 pt tall.
let arrowPoints: [(CGFloat, CGFloat)] = [
    (0.00, 1.00), (0.00, 0.28), (0.24, 0.49), (0.40, 0.14),
    (0.53, 0.20), (0.37, 0.54), (0.66, 0.54),
]
let arrowScale: CGFloat = 205
let arrowPath = NSBezierPath()
let origin = NSPoint(x: 560, y: 300)
let points = arrowPoints.map { NSPoint(x: origin.x + $0.0 * arrowScale, y: origin.y + $0.1 * arrowScale) }
arrowPath.move(to: points[0])
points.dropFirst().forEach { arrowPath.line(to: $0) }
arrowPath.close()

context.saveGState()
// Transform: slight tilt so the click feels in motion.
context.translateBy(x: origin.x + arrowScale * 0.33, y: origin.y + arrowScale * 0.5)
context.rotate(by: -0.10)
context.translateBy(x: -(origin.x + arrowScale * 0.33), y: -(origin.y + arrowScale * 0.5))
context.setShadow(offset: NSSize(width: 0, height: -12), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
arrowPath.fill()
context.restoreGState()

arrowPath.lineWidth = 14
NSColor.white.setStroke()
arrowPath.stroke()

image.unlockFocus()

// MARK: - Export

func pngData(_ image: NSImage, pixels: Int) -> Data? {
    // Redraw at the exact pixel size: rep.size alone only changes the DPI,
    // and iconutil rejects files whose pixels do not match their name.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let fileManager = FileManager.default
let iconsetURL = URL(fileURLWithPath: "/tmp/quicklet.iconset")
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    try pngData(image, pixels: size)!.write(to: iconsetURL.appendingPathComponent("icon_\(size)x\(size).png"))
    try pngData(image, pixels: size * 2)!.write(to: iconsetURL.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let resourcesURL = URL(fileURLWithPath: "Resources")
try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
let icnsURL = resourcesURL.appendingPathComponent("Quicklet.icns")
try? fileManager.removeItem(at: icnsURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }

try pngData(image, pixels: 512)!.write(to: URL(fileURLWithPath: "/tmp/quicklet-icon-preview.png"))
print("wrote \(icnsURL.path)")
