#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `Nida --snapshot <dir>` renders every screen with sample data to PNGs.
enum Snapshot {
    static func run(outDir: String) {
        Store.persist = false
        let out = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var p = Preferences()
        p.onboarded = true
        p.location = SavedLocation(name: "Paris", country: "France", countryCode: "FR",
                                   latitude: 48.8566, longitude: 2.3522, timeZoneID: "Europe/Paris")
        p.conventionID = "france"
        var fajr = p.alert(for: .fajr)
        fajr.length = .takbir
        p.setAlert(fajr, for: .fajr)
        var maghrib = p.alert(for: .maghrib)
        maghrib.style = .chime
        p.setAlert(maghrib, for: .maghrib)
        Store.shared.prefs = p

        let app = AppController.shared
        guard let engine = app.engine else { return }
        let w = engine.windows(for: Date())
        let asr = w[2], dhuhr = w[1]
        let states: [(String, Date)] = [
            ("popover-asr-opening", asr.start.addingTimeInterval(asr.duration * 0.08)),
            ("popover-asr-half", asr.start.addingTimeInterval(asr.duration * 0.62)),
            ("popover-asr-closing", asr.start.addingTimeInterval(asr.duration * 0.94)),
            ("popover-waiting", dhuhr.start.addingTimeInterval(-5400)),
        ]
        for dark in [false, true] {
            for (name, date) in states {
                app.debugSet(now: date)
                render(PopoverView(app: app, store: .shared, player: .shared), name: name, dark: dark, out: out)
            }
        }

        app.debugSet(now: asr.start.addingTimeInterval(asr.duration * 0.3))
        Store.shared.pendingMove = SavedLocation(name: "London", country: "United Kingdom", countryCode: "GB",
                                                 latitude: 51.5072, longitude: -0.1276, timeZoneID: "Europe/London")
        render(PopoverView(app: app, store: .shared, player: .shared), name: "popover-move", dark: false, out: out)
        Store.shared.pendingMove = nil

        for tab in [SettingsTab.general, .location, .calculation, .adhan, .about] {
            SettingsState.shared.tab = tab
            render(SettingsView(app: app, store: .shared, sounds: .shared, player: .shared, location: .shared,
                                notifier: .shared, state: .shared),
                   name: "settings-\(tab.rawValue)", dark: false, out: out, size: NSSize(width: 580, height: 640))
        }
        for step in 0..<6 {
            render(OnboardingView(app: app, location: .shared, sounds: .shared, player: .shared, notifier: .shared,
                                  startStep: step),
                   name: "onboarding-\(step)", dark: step == 4, out: out, size: NSSize(width: 520, height: 600))
        }
        menuBarStrip(app: app, engine: engine, out: out)
        print("Snapshots written to \(out.path)")
    }

    /// Draws the status item content for several moments on fake light and dark menu bars.
    private static func menuBarStrip(app: AppController, engine: PrayerEngine, out: URL) {
        let w = engine.windows(for: Date())
        let moments: [(Date, Preferences.Type?)] = [
            (w[2].start.addingTimeInterval(w[2].duration * 0.1), nil),
            (w[2].start.addingTimeInterval(w[2].duration * 0.6), nil),
            (w[2].start.addingTimeInterval(w[2].duration * 0.95), nil),
            (w[1].start.addingTimeInterval(-4500), nil),
        ]
        let rowH: CGFloat = 26, width: CGFloat = 420
        var rows: [(StatusRenderer.Content, Bool, String)] = []
        for dark in [false, true] {
            for style in [MenuStyle.time, .countdown, .icon] {
                for (date, _) in moments {
                    var p = Store.shared.prefs
                    p.menuStyle = style
                    rows.append((StatusRenderer.make(engine: PrayerEngine(prefs: p, location: p.location!),
                                                     phase: engine.phase(at: date), now: date, prefs: p,
                                                     isPlaying: false, darkMenuBar: dark), dark, style.rawValue))
                }
            }
        }
        let img = NSImage(size: NSSize(width: width, height: rowH * CGFloat(rows.count)), flipped: true) { _ in
            for (i, row) in rows.enumerated() {
                let r = NSRect(x: 0, y: CGFloat(i) * rowH, width: width, height: rowH)
                (row.1 ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                r.fill()
                let ink: NSColor = row.1 ? .white : .black
                var x: CGFloat = 12
                if let im = row.0.image {
                    let drawn = im.isTemplate ? tint(im, ink) : im
                    drawn.draw(in: NSRect(x: x, y: r.midY - im.size.height / 2, width: im.size.width, height: im.size.height),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    x += im.size.width
                }
                let t = NSAttributedString(string: row.0.title, attributes: [.font: StatusRenderer.font, .foregroundColor: ink])
                t.draw(at: NSPoint(x: x, y: r.midY - t.size().height / 2))
                NSAttributedString(string: row.2, attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.gray])
                    .draw(at: NSPoint(x: width - 60, y: r.minY + 8))
            }
            return true
        }
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("menubar.png"))
        }
    }

    private static func tint(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
    }

    private static func render<V: View>(_ view: V, name: String, dark: Bool, out: URL, size: NSSize? = nil) {
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
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let file = out.appendingPathComponent("\(name)\(dark ? "-dark" : "").png")
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}
#endif
