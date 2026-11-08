// Renders the app icon and DMG background with AppKit.
// Usage: swift scripts/make_art.swift <output-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/art")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
}

func render(width: Int, height: Int, _ draw: (CGRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

/// A pointed (lancet) arch — the mihrab shape.
func archPath(in r: CGRect) -> NSBezierPath {
    let p = NSBezierPath()
    let shoulder = r.minY + r.height * 0.58
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.line(to: CGPoint(x: r.minX, y: shoulder))
    p.curve(to: CGPoint(x: r.midX, y: r.maxY),
            controlPoint1: CGPoint(x: r.minX, y: shoulder + r.height * 0.26),
            controlPoint2: CGPoint(x: r.midX - r.width * 0.16, y: r.maxY - r.height * 0.08))
    p.curve(to: CGPoint(x: r.maxX, y: shoulder),
            controlPoint1: CGPoint(x: r.midX + r.width * 0.16, y: r.maxY - r.height * 0.08),
            controlPoint2: CGPoint(x: r.maxX, y: shoulder + r.height * 0.26))
    p.line(to: CGPoint(x: r.maxX, y: r.minY))
    p.close()
    return p
}

/// Fills a crescent (outer disc minus an offset inner disc) with a gradient.
func drawCrescent(center c: CGPoint, radius: CGFloat, gradient: NSGradient) {
    let outer = NSBezierPath(ovalIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
    let cut = radius * 0.84
    let o = CGPoint(x: c.x + radius * 0.40, y: c.y + radius * 0.20)
    let inner = NSBezierPath(ovalIn: CGRect(x: o.x - cut, y: o.y - cut, width: cut * 2, height: cut * 2))
    NSGraphicsContext.saveGraphicsState()
    let outside = NSBezierPath(rect: outer.bounds.insetBy(dx: -radius, dy: -radius))
    outside.append(inner)
    outside.windingRule = .evenOdd
    outside.addClip()
    gradient.draw(in: outer, angle: -60)
    NSGraphicsContext.restoreGraphicsState()
}

func star(center c: CGPoint, radius: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    for i in 0..<10 {
        let r = i % 2 == 0 ? radius : radius * 0.42
        let a = CGFloat(i) * .pi / 5 + .pi / 2
        let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    return p
}

func drawIcon(_ rect: CGRect) {
    let s = rect.width
    // macOS icon grid: 824pt body inside 1024 canvas
    let body = rect.insetBy(dx: s * 0.0977, dy: s * 0.0977)
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    hex(0x0B3B38).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [hex(0x14615A), hex(0x0B3B38), hex(0x061F24)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!.draw(in: body, angle: -90)
    // soft glow behind the arch
    NSGradient(colors: [hex(0xF4D58D, 0.28), hex(0xF4D58D, 0)])!
        .draw(fromCenter: CGPoint(x: body.midX, y: body.midY + s * 0.04), radius: 0,
              toCenter: CGPoint(x: body.midX, y: body.midY + s * 0.04), radius: s * 0.42, options: [])

    // mihrab arch
    let archRect = CGRect(x: body.midX - s * 0.2, y: body.minY + s * 0.15, width: s * 0.4, height: s * 0.56)
    let arch = archPath(in: archRect)
    NSGradient(colors: [hex(0x1E7A70, 0.9), hex(0x0E4A45, 0.9)])!.draw(in: arch, angle: -90)
    hex(0xE9C46A, 0.95).setStroke()
    arch.lineWidth = s * 0.016
    arch.stroke()
    let innerArch = archPath(in: archRect.insetBy(dx: s * 0.035, dy: s * 0.035).offsetBy(dx: 0, dy: -s * 0.012))
    hex(0xE9C46A, 0.35).setStroke()
    innerArch.lineWidth = s * 0.006
    innerArch.stroke()

    // crescent + star
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = hex(0xFFE3A3, 0.55)
    glow.shadowBlurRadius = s * 0.03
    glow.set()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let gold = NSGradient(colors: [hex(0xFFE7A8), hex(0xE2B04A)])!
    let moonCenter = CGPoint(x: body.midX - s * 0.025, y: archRect.minY + archRect.height * 0.5)
    drawCrescent(center: moonCenter, radius: s * 0.11, gradient: gold)
    let st = star(center: CGPoint(x: moonCenter.x + s * 0.075, y: moonCenter.y + s * 0.035), radius: s * 0.03)
    gold.draw(in: st, angle: -90)
    ctx.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()

    // floor line
    let floor = NSBezierPath()
    floor.move(to: CGPoint(x: archRect.minX - s * 0.06, y: archRect.minY))
    floor.line(to: CGPoint(x: archRect.maxX + s * 0.06, y: archRect.minY))
    hex(0xE9C46A, 0.95).setStroke()
    floor.lineWidth = s * 0.016
    floor.lineCapStyle = .round
    floor.stroke()

    // top highlight
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    hex(0xFFFFFF, 0.12).setStroke()
    squircle.lineWidth = s * 0.003
    squircle.stroke()
}

func drawDMGBackground(_ rect: CGRect, scale: CGFloat) {
    NSGradient(colors: [hex(0xF7F3EA), hex(0xEDE6D6)])!.draw(in: rect, angle: -90)
    // faint arch watermark
    let arch = archPath(in: CGRect(x: rect.midX - 150 * scale, y: -40 * scale, width: 300 * scale, height: 520 * scale))
    hex(0x0B3B38, 0.035).setFill()
    arch.fill()

    let title = NSAttributedString(string: "Install Nida", attributes: [
        .font: NSFont.systemFont(ofSize: 22 * scale, weight: .semibold),
        .foregroundColor: hex(0x0B3B38),
    ])
    let ts = title.size()
    title.draw(at: CGPoint(x: rect.midX - ts.width / 2, y: rect.height - 62 * scale))

    let sub = NSAttributedString(string: "Drag Nida into your Applications folder", attributes: [
        .font: NSFont.systemFont(ofSize: 13 * scale, weight: .regular),
        .foregroundColor: hex(0x0B3B38, 0.6),
    ])
    let ss = sub.size()
    sub.draw(at: CGPoint(x: rect.midX - ss.width / 2, y: rect.height - 88 * scale))

    // arrow between icon slots (icons centered at x=170 and x=490, y=215 from top)
    let y = rect.height - 215 * scale
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 255 * scale, y: y))
    arrow.curve(to: CGPoint(x: 400 * scale, y: y),
                controlPoint1: CGPoint(x: 300 * scale, y: y + 22 * scale),
                controlPoint2: CGPoint(x: 355 * scale, y: y + 22 * scale))
    hex(0xC9A24A).setStroke()
    arrow.lineWidth = 3 * scale
    arrow.lineCapStyle = .round
    let dash: [CGFloat] = [1 * scale, 9 * scale]
    arrow.setLineDash(dash, count: 2, phase: 0)
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 388 * scale, y: y + 11 * scale))
    head.line(to: CGPoint(x: 404 * scale, y: y))
    head.line(to: CGPoint(x: 389 * scale, y: y - 10 * scale))
    head.lineWidth = 3 * scale
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
}

// App icon at all iconset sizes
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                     (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    let rep = render(width: size, height: size, drawIcon)
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
save(render(width: 1024, height: 1024, drawIcon), "AppIcon-1024.png")
save(render(width: 660, height: 420) { drawDMGBackground($0, scale: 1) }, "dmg-background.png")
save(render(width: 1320, height: 840) { drawDMGBackground($0, scale: 2) }, "dmg-background@2x.png")
print("Art written to \(outDir.path)")
