import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        if Installer.handleLaunch() { return } // relaunching from /Applications
        AppController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AdhanPlayer.shared.stop(fade: false) // puts any raised volume back
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppController.shared.showPopover()
        return false
    }

    /// Accessory apps have no visible menu bar, but the key equivalents (⌘C, ⌘V, ⌘W…) still need a menu.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Nida", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}

final class AppController: NSObject, ObservableObject, NSPopoverDelegate, NSWindowDelegate {
    static let shared = AppController()

    let store = Store.shared
    let player = AdhanPlayer.shared
    let sounds = SoundLibrary.shared
    let notifier = Notifier.shared
    let location = LocationService.shared

    @Published private(set) var now = Date()
    @Published private(set) var phase: PrayerPhase?

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var timer: Timer?
    private var lastStatusKey = ""
    private var lastContent: StatusRenderer.Content?
    private var fired: [String: Date] = [:]
    private var lastBackgroundRefresh = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    private var cachedEngine: PrayerEngine?

    /// Reused while settings and location are unchanged, so its per-day cache survives.
    var engine: PrayerEngine? {
        guard let loc = store.prefs.location else { cachedEngine = nil; return nil }
        if let e = cachedEngine, e.location == loc, e.prefs == store.prefs { return e }
        let e = PrayerEngine(prefs: store.prefs, location: loc)
        cachedEngine = e
        return e
    }

    /// Only push per-second updates into SwiftUI while something is on screen.
    private var uiVisible: Bool {
        popover.isShown || settingsWindow?.isVisible == true || onboardingWindow?.isVisible == true
    }

    // MARK: Lifecycle

    func start() {
        notifier.setUp()
        notifier.onAction = { [weak self] action, category in self?.handleNotificationAction(action, category: category) }
        location.onBackgroundLocation = { [weak self] loc in self?.handleDetected(loc) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.imagePosition = .imageLeading
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Re-render as soon as settings or playback change.
        store.$prefs.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.tick() }.store(in: &cancellables)
        player.$nowPlaying.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }.store(in: &cancellables)


        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(timeZoneChanged),
                                               name: .NSSystemTimeZoneDidChange, object: nil)

        tick()
        if store.prefs.onboarded {
            if store.prefs.followLocation {
                location.startMonitoringMoves()
                backgroundRefresh(force: true)
            }
        } else {
            showOnboarding()
        }
    }

    // MARK: Ticking

    /// The current moment; `now` (published) only follows it while UI is visible.
    private var clock = Date()

    private func tick() {
        clock = Date()
        if uiVisible { now = clock }
        defer { scheduleNextTick() }
        guard let engine else {
            if phase != nil { phase = nil }
            renderStatus()
            return
        }
        let newPhase = engine.phase(at: clock)
        if newPhase != phase { phase = newPhase }
        checkEvents(engine)
        renderStatus()
        if store.prefs.followLocation && clock.timeIntervalSince(lastBackgroundRefresh) > 3 * 3600 {
            backgroundRefresh(force: false)
        }
    }

    /// Whether anything currently needs per-second updates.
    private var needsSeconds = false

    /// Wakes up only as often as needed: every second while a countdown shows seconds, the popover
    /// is open or audio plays; otherwise once a minute, exactly on the minute. Prayer times,
    /// reminders and closing warnings all fall on whole minutes, so no alert can be missed.
    private func scheduleNextTick() {
        timer?.invalidate()
        let fast = needsSeconds || uiVisible || player.isPlaying
        let t = Date().timeIntervalSince1970
        let next = fast ? t.rounded(.down) + 1 : (t / 60).rounded(.down) * 60 + 60
        let timer = Timer(fire: Date(timeIntervalSince1970: next), interval: 0, repeats: false) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = fast ? 0.05 : 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkEvents(_ engine: PrayerEngine) {
        let now = clock
        let prefs = store.prefs
        for w in engine.windows(around: now) {
            let alert = prefs.alert(for: w.kind)
            guard alert.style != .off else { continue }
            var events: [(Date, String)] = [(w.start, "start")]
            if alert.reminderMinutes > 0 { events.append((w.start.addingTimeInterval(-Double(alert.reminderMinutes) * 60), "remind")) }
            if prefs.closingWarning > 0, w.duration > Double(prefs.closingWarning) * 60 * 1.5 {
                events.append((w.end.addingTimeInterval(-Double(prefs.closingWarning) * 60), "closing"))
            }
            for (date, type) in events {
                let key = "\(w.id)-\(type)"
                // Fire only near the actual moment: never replay alerts after sleep.
                guard now >= date, now.timeIntervalSince(date) < 90, fired[key] == nil else { continue }
                fired[key] = now
                fire(type, window: w, engine: engine, alert: alert)
            }
        }
        if fired.count > 60 { fired = fired.filter { now.timeIntervalSince($0.value) < 2 * 86400 } }
    }

    private func fire(_ type: String, window w: PrayerWindow, engine: PrayerEngine, alert: PrayerAlert) {
        let name = w.kind.displayName(on: w.start, calendar: engine.calendar)
        let arabic = w.kind.displayArabic(on: w.start, calendar: engine.calendar)
        let endName = w.kind == .isha && store.prefs.ishaEnd == .midnight ? "midnight" : "the window closes"
        switch type {
        case "start":
            notifier.post(id: "\(w.id)-start", title: "\(name) · \(arabic)",
                          body: "It's time for \(name). \(endName.capitalizedFirst) at \(engine.timeString(w.end)).",
                          category: NotificationCategory.prayer, playSound: alert.style == .banner)
            switch alert.style {
            case .adhan:
                if let s = sounds.sound(alert.soundID) {
                    player.play(s, length: alert.length, volume: store.prefs.volume, label: "\(name) adhan", route: store.prefs.audioRoute)
                }
            case .chime:
                if let s = sounds.chime { player.play(s, length: .full, volume: store.prefs.volume, label: "\(name) chime", route: store.prefs.audioRoute) }
            case .banner, .off:
                break
            }
        case "remind":
            notifier.post(id: "\(w.id)-remind", title: "\(name) in \(alert.reminderMinutes) min",
                          body: "\(name) begins at \(engine.timeString(w.start)).",
                          category: NotificationCategory.prayer, playSound: true)
        case "closing":
            notifier.post(id: "\(w.id)-closing", title: "\(name) ends in \(store.prefs.closingWarning) min",
                          body: "Pray \(name) before \(engine.timeString(w.end)).",
                          category: NotificationCategory.prayer, playSound: true)
        default:
            break
        }
    }

    // MARK: Status item

    private func renderStatus() {
        guard let button = statusItem?.button else { return }
        defer { if let c = lastContent { needsSeconds = c.ticksEverySecond } }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let content = StatusRenderer.make(engine: engine, phase: phase, now: clock, prefs: store.prefs,
                                          isPlaying: player.isPlaying, darkMenuBar: dark)
        lastContent = content
        guard content.key != lastStatusKey else { return }
        lastStatusKey = content.key

        button.image = content.image
        button.contentTintColor = nil
        button.attributedTitle = NSAttributedString(string: content.title, attributes: [
            .font: StatusRenderer.font,
            .baselineOffset: 0.5,
        ])
        button.toolTip = phase.map { p in
            let n = p.window.kind.name
            return p.isOpen ? "\(n) is open" : "Next: \(n)"
        }
    }

    @objc private func statusClicked() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        now = Date()
        if popover.contentViewController == nil {
            let host = NSHostingController(rootView: PopoverView(app: self, store: store, player: player))
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        scheduleNextTick() // switch to per-second updates while open
    }

    func closePopover() { popover.performClose(nil) }

    /// Free the popover's views while it's closed.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    /// Free settings/setup windows once closed; they're rebuilt on demand.
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        DispatchQueue.main.async {
            if w === self.settingsWindow { self.settingsWindow = nil }
            if w === self.onboardingWindow { self.onboardingWindow = nil }
        }
    }

    // MARK: Windows

    func showSettings(tab: SettingsTab = .general) {
        closePopover()
        SettingsState.shared.tab = tab
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(app: self, store: store, sounds: sounds, player: player,
                                                                  location: location, notifier: notifier,
                                                                  state: SettingsState.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Nida Settings"
            w.delegate = self
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 580, height: 640))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        scheduleNextTick()
    }

    func showOnboarding() {
        closePopover()
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView(app: self, location: location, sounds: sounds,
                                                                    player: player, notifier: notifier))
            let w = NSWindow(contentViewController: host)
            w.title = store.prefs.onboarded ? "Nida Setup" : "Welcome to Nida"
            w.delegate = self
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 520, height: 600))
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        scheduleNextTick()
    }

    func finishOnboarding(with prefs: Preferences) {
        var p = prefs
        p.onboarded = true
        store.prefs = p
        onboardingWindow?.close()
        onboardingWindow = nil
        if p.followLocation { location.startMonitoringMoves() } else { location.stopMonitoringMoves() }
        lastBackgroundRefresh = Date()
        tick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showPopover() }
    }

    // MARK: Location changes

    private func backgroundRefresh(force: Bool) {
        guard store.prefs.followLocation, location.isAuthorized else { return }
        if !force && clock.timeIntervalSince(lastBackgroundRefresh) < 600 { return }
        lastBackgroundRefresh = Date()
        location.refresh()
    }

    @objc private func didWake() {
        tick()
        backgroundRefresh(force: true)
    }

    @objc private func timeZoneChanged() {
        // A time zone change is the strongest hint that you've travelled.
        backgroundRefresh(force: true)
    }

    private func handleDetected(_ detected: SavedLocation) {
        let prefs = store.prefs
        guard prefs.onboarded, prefs.followLocation else { return }
        guard let current = prefs.location else { apply(detected, announce: false); return }

        let distance = current.distance(to: detected)
        if distance < 15_000 {
            // Same area: quietly keep the time zone in sync, nothing else.
            if current.timeZoneID != detected.timeZoneID {
                var p = prefs
                p.location?.timeZoneID = detected.timeZoneID
                store.prefs = p
            }
            return
        }
        if let pending = store.pendingMove, pending.distance(to: detected) < 15_000 { return }

        switch prefs.moveBehavior {
        case .automatic:
            apply(detected, announce: true)
        case .ask:
            store.pendingMove = detected
            let rec = Conventions.convention(Conventions.recommendation(for: detected.countryCode).conventionID)
            let changesCountry = current.countryCode != detected.countryCode
            notifier.post(id: "move-\(detected.id)", title: "You're in \(detected.title)",
                          body: changesCountry ? "Update prayer times? Mosques here usually use \(rec.name)."
                                               : "Update prayer times for your new location?",
                          category: NotificationCategory.move)
        case .ignore:
            break
        }
    }

    /// Switch to a new location, adapting convention and madhab when they're on automatic.
    func apply(_ loc: SavedLocation, announce: Bool) {
        var p = store.prefs
        let previous = p.location
        p.location = loc
        let rec = Conventions.recommendation(for: loc.countryCode)
        var conventionChanged = false
        if p.conventionAuto {
            conventionChanged = p.conventionID != rec.conventionID
            p.conventionID = rec.conventionID
        } else if previous?.countryCode != loc.countryCode && rec.conventionID != p.conventionID {
            store.pendingConvention = rec.conventionID
            notifier.post(id: "conv-\(loc.id)", title: "Switch to \(Conventions.convention(rec.conventionID).name)?",
                          body: "It's the usual convention in \(loc.country.isEmpty ? loc.name : loc.country). You're using \(Conventions.convention(p.conventionID).name).",
                          category: NotificationCategory.convention)
        }
        if p.madhabAuto { p.madhabHanafi = rec.hanafi }
        store.pendingMove = nil
        store.prefs = p
        notifier.remove(category: NotificationCategory.move)
        if announce {
            let conv = Conventions.convention(p.conventionID).name
            notifier.post(id: "moved-\(loc.id)", title: "Prayer times updated for \(loc.title)",
                          body: conventionChanged ? "Now using \(conv), the usual convention here." : "Using \(conv).",
                          category: "INFO")
        }
    }

    func acceptPendingMove() {
        if let loc = store.pendingMove { apply(loc, announce: false) }
    }

    func dismissPendingMove() {
        store.pendingMove = nil
        notifier.remove(category: NotificationCategory.move)
    }

    func acceptPendingConvention() {
        guard let id = store.pendingConvention else { return }
        var p = store.prefs
        p.conventionID = id
        p.conventionAuto = true
        store.pendingConvention = nil
        store.prefs = p
    }

    func dismissPendingConvention() { store.pendingConvention = nil }

    private func handleNotificationAction(_ action: String, category: String) {
        switch action {
        case NotificationAction.stop: player.stop()
        case NotificationAction.moveAccept: acceptPendingMove()
        case NotificationAction.moveKeep: dismissPendingMove()
        case NotificationAction.conventionAccept: acceptPendingConvention()
        case NotificationAction.conventionKeep: dismissPendingConvention()
        default:
            // Tapping a prayer banner acknowledges it: stop the adhan.
            if category == NotificationCategory.prayer { player.stop() } else { showPopover() }
        }
    }

    // MARK: Helpers

    #if DEBUG
    func debugSet(now date: Date) {
        now = date
        phase = engine?.phase(at: date)
    }
    #endif


    func preview(_ soundID: String, length: AdhanLength, prefs: Preferences? = nil) {
        let p = prefs ?? store.prefs
        if let s = soundID == SoundLibrary.chimeID ? sounds.chime : sounds.sound(soundID) {
            player.play(s, length: length, volume: p.volume, label: "Preview", route: p.audioRoute)
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Nida: launch at login change failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
