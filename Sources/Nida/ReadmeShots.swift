#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `Nida --readme <dir>` renders the README images from the live views.
enum ReadmeShots {
    static func run(outDir: String) {
        Store.persist = false
        let out = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var p = Preferences()
        p.onboarded = true
        p.location = SavedLocation(name: "Paris", country: "France", countryCode: "FR",
                                   latitude: 48.8566, longitude: 2.3522, timeZoneID: "Europe/Paris")
        p.conventionID = "france"
        var maghrib = p.alert(for: .maghrib)
        maghrib.style = .chime
        p.setAlert(maghrib, for: .maghrib)
        Store.shared.prefs = p

        let app = AppController.shared
        guard let engine = app.engine else { return }
        let asr = engine.windows(for: Date())[2]
        func at(_ f: Double) -> Date { asr.start.addingTimeInterval(asr.duration * f) }

        // Hero scenes: early Asr (green) on a light desktop, closing Asr (red) on a dark one.
        for (dark, moment) in [(false, at(0.12)), (true, at(0.955))] {
            app.debugSet(now: moment)
            let pop = capture(PopoverView(app: app, store: .shared, player: .shared), dark: dark)
            let status = StatusRenderer.make(engine: engine, phase: engine.phase(at: moment), now: moment,
                                             prefs: Store.shared.prefs, isPlaying: false, darkMenuBar: dark)
            save(hero(popover: pop, status: status, dark: dark, moment: moment, engine: engine),
                 out.appendingPathComponent("hero-\(dark ? "dark" : "light").png"))
        }

        // The window draining from green to red.
        var states: [NSImage] = []
        for f in [0.1, 0.65, 0.95] {
            app.debugSet(now: at(f))
            states.append(capture(PopoverView(app: app, store: .shared, player: .shared), dark: false))
        }
        save(row(states, gap: 28, background: NSColor(white: 0.96, alpha: 1)), out.appendingPathComponent("window-colors.png"))

        // Menu bar styles, light and dark.
        save(menuBarStyles(engine: engine, moments: [at(0.12), at(0.65), at(0.955)]),
             out.appendingPathComponent("menubar-styles.png"))

        app.debugSet(now: at(0.4))
        for tab in [SettingsTab.general, .adhan, .calculation] {
            SettingsState.shared.tab = tab
            let img = capture(SettingsView(app: app, store: .shared, sounds: .shared, player: .shared, location: .shared,
                                           notifier: .shared, state: .shared),
                              dark: false, size: NSSize(width: 580, height: 640))
            save(framed(img, title: "Nida Settings", dark: false), out.appendingPathComponent("settings-\(tab.rawValue).png"))
        }
        var steps: [NSImage] = []
        for step in [1, 2, 4] {
            steps.append(capture(OnboardingView(app: app, location: .shared, sounds: .shared, player: .shared,
                                                notifier: .shared, startStep: step),
                                 dark: step == 2, size: NSSize(width: 520, height: 600)))
        }
        save(row(steps.map { framed($0, title: nil, dark: false) }, gap: 28, background: NSColor(white: 0.96, alpha: 1)),
             out.appendingPathComponent("setup.png"))
        print("README images written to \(out.path)")
    }

    // MARK: Composition

    private static func hero(popover: NSImage, status: StatusRenderer.Content, dark: Bool, moment: Date,
                             engine: PrayerEngine) -> NSImage {
        let size = NSSize(width: 900, height: popover.size.height + 30 + 12 + 40)
        return NSImage(size: size, flipped: true) { rect in
            // Wallpaper
            let wall = dark
                ? NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.13, blue: 0.20, alpha: 1),
                                      NSColor(srgbRed: 0.10, green: 0.22, blue: 0.24, alpha: 1),
                                      NSColor(srgbRed: 0.22, green: 0.16, blue: 0.28, alpha: 1)])!
                : NSGradient(colors: [NSColor(srgbRed: 0.80, green: 0.88, blue: 0.95, alpha: 1),
                                      NSColor(srgbRed: 0.93, green: 0.90, blue: 0.84, alpha: 1),
                                      NSColor(srgbRed: 0.96, green: 0.84, blue: 0.74, alpha: 1)])!
            wall.draw(in: rect, angle: -70)

            // Menu bar
            let barH: CGFloat = 30
            (dark ? NSColor(white: 0, alpha: 0.35) : NSColor(white: 1, alpha: 0.55)).setFill()
            NSRect(x: 0, y: 0, width: rect.width, height: barH).fill()
            let ink: NSColor = dark ? .white : NSColor(white: 0.1, alpha: 1)
            let font = NSFont.systemFont(ofSize: 13, weight: .regular)

            // Right side: system items + clock
            let clockFmt = DateFormatter()
            clockFmt.timeZone = engine.location.timeZone
            clockFmt.dateFormat = "EEE d MMM  h:mm a"
            let clock = NSAttributedString(string: clockFmt.string(from: moment), attributes: [.font: font, .foregroundColor: ink])
            var x = rect.width - 16 - clock.size().width
            clock.draw(at: NSPoint(x: x, y: (barH - clock.size().height) / 2))
            for name in ["switch.2", "wifi", "battery.75percent"] {
                guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) else { continue }
                x -= sym.size.width + 16
                tint(sym, ink).draw(in: NSRect(x: x, y: (barH - sym.size.height) / 2, width: sym.size.width, height: sym.size.height),
                                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }

            // Nida's item
            let title = NSAttributedString(string: status.title, attributes: [.font: StatusRenderer.font, .foregroundColor: ink])
            let pillW = status.image?.size.width ?? 0
            let itemW = pillW + title.size().width
            x -= itemW + 22
            let itemX = x
            if let img = status.image {
                let drawn = img.isTemplate ? tint(img, ink) : img
                drawn.draw(in: NSRect(x: x, y: (barH - img.size.height) / 2, width: img.size.width, height: img.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            title.draw(at: NSPoint(x: x + pillW, y: (barH - title.size().height) / 2))

            // Popover under the item
            let pw = popover.size.width, ph = popover.size.height
            let px = min(rect.width - pw - 24, max(24, itemX + itemW / 2 - pw / 2))
            let py = barH + 12
            let frame = NSRect(x: px, y: py, width: pw, height: ph)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.6 : 0.25)
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.set()
            let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
            let arrowX = itemX + itemW / 2
            shape.move(to: NSPoint(x: arrowX - 9, y: py))
            shape.line(to: NSPoint(x: arrowX, y: py - 9))
            shape.line(to: NSPoint(x: arrowX + 9, y: py))
            shape.close()
            (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).addClip()
            popover.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.1)).setStroke()
            let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            border.lineWidth = 1
            border.stroke()
            return true
        }
    }

    private static func menuBarStyles(engine: PrayerEngine, moments: [Date]) -> NSImage {
        let rowH: CGFloat = 34, width: CGFloat = 760
        var rows: [(StatusRenderer.Content, Bool)] = []
        for dark in [false, true] {
            for m in moments {
                rows.append((StatusRenderer.make(engine: engine, phase: engine.phase(at: m), now: m, prefs: Store.shared.prefs,
                                                 isPlaying: false, darkMenuBar: dark), dark))
            }
        }
        let colW = width / 2
        let perCol = moments.count
        return NSImage(size: NSSize(width: width, height: rowH * CGFloat(perCol)), flipped: true) { _ in
            for (i, r) in rows.enumerated() {
                let col = CGFloat(i / perCol), line = CGFloat(i % perCol)
                let cell = NSRect(x: col * colW, y: line * rowH, width: colW, height: rowH)
                (r.1 ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                cell.fill()
                let ink: NSColor = r.1 ? .white : NSColor(white: 0.1, alpha: 1)
                var x = cell.minX + 18
                if let img = r.0.image {
                    let drawn = img.isTemplate ? tint(img, ink) : img
                    drawn.draw(in: NSRect(x: x, y: cell.midY - img.size.height / 2, width: img.size.width, height: img.size.height),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    x += img.size.width
                }
                let t = NSAttributedString(string: r.0.title, attributes: [.font: StatusRenderer.font, .foregroundColor: ink])
                t.draw(at: NSPoint(x: x, y: cell.midY - t.size().height / 2))
            }
            return true
        }
    }

    /// Adds a window frame with traffic lights (and optional title) around a screen.
    private static func framed(_ image: NSImage, title: String?, dark: Bool) -> NSImage {
        let barH: CGFloat = title == nil ? 0 : 28
        let size = NSSize(width: image.size.width, height: image.size.height + barH)
        return NSImage(size: size, flipped: true) { rect in
            let clip = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            clip.addClip()
            (dark ? NSColor(white: 0.2, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            rect.fill()
            image.draw(in: NSRect(x: 0, y: barH, width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let lightsY = title == nil ? 14.0 : 9.0
            for (i, c) in [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                           NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                           NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
                c.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12 + CGFloat(i) * 20, y: lightsY, width: 12, height: 12)).fill()
            }
            if let title {
                let t = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                                         .foregroundColor: NSColor(white: 0.25, alpha: 1)])
                t.draw(at: NSPoint(x: rect.midX - t.size().width / 2, y: (barH - t.size().height) / 2))
            }
            NSColor(white: 0, alpha: 0.12).setStroke()
            clip.lineWidth = 1
            clip.stroke()
            return true
        }
    }

    private static func row(_ images: [NSImage], gap: CGFloat, background: NSColor) -> NSImage {
        let h = images.map(\.size.height).max() ?? 0
        let w = images.map(\.size.width).reduce(0, +) + gap * CGFloat(images.count + 1)
        return NSImage(size: NSSize(width: w, height: h + gap * 2), flipped: true) { rect in
            background.setFill()
            rect.fill()
            var x = gap
            for img in images {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
                shadow.shadowBlurRadius = 14
                shadow.shadowOffset = NSSize(width: 0, height: -4)
                shadow.set()
                let frame = NSRect(x: x, y: gap, width: img.size.width, height: img.size.height)
                NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).addClip()
                img.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                x += img.size.width + gap
            }
            return true
        }
    }

    // MARK: Helpers

    private static func capture<V: View>(_ view: V, dark: Bool, size: NSSize? = nil) -> NSImage {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let fitting = size ?? host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: fitting)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: fitting)
        image.addRepresentation(rep)
        return image
    }

    private static func tint(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
    }

    /// Saves at 2x for sharp images on Retina screens.
    private static func save(_ image: NSImage, _ url: URL) {
        let scale: CGFloat = 2
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
