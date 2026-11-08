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
        print("Snapshots written to \(out.path)")
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
