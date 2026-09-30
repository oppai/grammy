// Renders the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon() {
    // macOS icon grid: 824pt body inset 100pt, continuous-corner radius ≈ 185.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0x4B3BE6).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [color(0x8A7CFF), color(0x5B45F0), color(0x3423C4)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -90)
    // Soft highlight across the top.
    NSGradient(starting: color(0xFFFFFF, 0.22), ending: color(0xFFFFFF, 0))!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Chat bubble with a tail at bottom-left.
    let bubbleRect = NSRect(x: 218, y: 350, width: 588, height: 420)
    let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 120, yRadius: 120)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 300, y: 380))
    tail.curve(to: NSPoint(x: 236, y: 262), controlPoint1: NSPoint(x: 296, y: 320), controlPoint2: NSPoint(x: 270, y: 284))
    tail.curve(to: NSPoint(x: 420, y: 360), controlPoint1: NSPoint(x: 320, y: 270), controlPoint2: NSPoint(x: 380, y: 310))
    tail.close()
    bubble.append(tail)

    NSGraphicsContext.saveGraphicsState()
    let bubbleShadow = NSShadow()
    bubbleShadow.shadowColor = color(0x1A0F80, 0.35)
    bubbleShadow.shadowOffset = NSSize(width: 0, height: -10)
    bubbleShadow.shadowBlurRadius = 24
    bubbleShadow.set()
    color(0xFFFFFF).setFill()
    bubble.fill()
    NSGraphicsContext.restoreGraphicsState()

    // "Aa" glyphs inside the bubble.
    let font = NSFont.systemFont(ofSize: 250, weight: .heavy)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 250) } ?? font
    let text = NSAttributedString(string: "Aa", attributes: [
        .font: rounded,
        .foregroundColor: color(0x3423C4),
        .kern: -6,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: bubbleRect.midX - size.width / 2 - 78, y: bubbleRect.midY - size.height / 2 + 14))

    // Green check badge overlapping the bubble's bottom-right corner.
    let center = NSPoint(x: 720, y: 372)
    let radius: CGFloat = 132
    NSGraphicsContext.saveGraphicsState()
    let badgeShadow = NSShadow()
    badgeShadow.shadowColor = color(0x000000, 0.3)
    badgeShadow.shadowOffset = NSSize(width: 0, height: -8)
    badgeShadow.shadowBlurRadius = 20
    badgeShadow.set()
    color(0xFFFFFF).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius - 16, y: center.y - radius - 16,
                                width: (radius + 16) * 2, height: (radius + 16) * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()

    let badge = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    NSGraphicsContext.saveGraphicsState()
    badge.addClip()
    NSGradient(starting: color(0x4ADE80), ending: color(0x16A34A))!
        .draw(in: badge.bounds, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let check = NSBezierPath()
    check.move(to: NSPoint(x: center.x - 62, y: center.y + 2))
    check.line(to: NSPoint(x: center.x - 16, y: center.y - 46))
    check.line(to: NSPoint(x: center.x + 66, y: center.y + 52))
    check.lineWidth = 40
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    color(0xFFFFFF).setStroke()
    check.stroke()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
