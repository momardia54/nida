import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, Hashable {
    case general, location, calculation, adhan, about
}

final class SettingsState: ObservableObject {
    static let shared = SettingsState()
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var app: AppController
    @ObservedObject var store: Store
    @ObservedObject var sounds: SoundLibrary
    @ObservedObject var player: AdhanPlayer
    @ObservedObject var location: LocationService
    @ObservedObject var notifier: Notifier
    @ObservedObject var state: SettingsState

    var body: some View {
        TabView(selection: $state.tab) {
            GeneralTab(app: app, store: store, notifier: notifier)
                .tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            LocationTab(app: app, store: store, location: location)
                .tabItem { Label("Location", systemImage: "location") }.tag(SettingsTab.location)
            CalculationTab(app: app, store: store)
                .tabItem { Label("Calculation", systemImage: "function") }.tag(SettingsTab.calculation)
            AdhanTab(app: app, store: store, sounds: sounds, player: player)
                .tabItem { Label("Adhan", systemImage: "speaker.wave.2") }.tag(SettingsTab.adhan)
            AboutTab(sounds: sounds)
                .tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .padding(.top, 8)
        .frame(width: 580, height: 640)
        .onAppear { notifier.refreshStatus() }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var app: AppController
    @ObservedObject var store: Store
    @ObservedObject var notifier: Notifier

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show", selection: $store.prefs.menuStyle) {
                    ForEach(MenuStyle.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Color the current prayer window", isOn: $store.prefs.colorize)
                if store.prefs.colorize {
                    HStack(spacing: 10) {
                        UrgencyLegend()
                        Text("Green when a prayer's time begins, turning red as its window closes.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Prayer windows") {
                Picker("Isha window ends at", selection: $store.prefs.ishaEnd) {
                    ForEach(IshaEnd.allCases) { Text($0.label).tag($0) }
                }
                Picker("Warn before a window closes", selection: $store.prefs.closingWarning) {
                    Text("Never").tag(0)
                    ForEach([10, 15, 20, 30, 45], id: \.self) { Text("\($0) minutes before").tag($0) }
                }
            }
            Section("System") {
                Toggle("Open Nida at login", isOn: Binding(get: { app.launchAtLogin }, set: { app.launchAtLogin = $0 }))
                HStack {
                    Text("Notifications")
                    Spacer()
                    if notifier.authorized {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { notifier.requestAuthorization() }
                    }
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Button("Run setup again…") { app.showOnboarding() }
            }
        }
        .formStyle(.grouped)
    }
}

struct UrgencyLegend: View {
    var body: some View {
        let start = Date(timeIntervalSince1970: 0)
        let w = PrayerWindow(kind: .asr, start: start, end: start.addingTimeInterval(3 * 3600))
        HStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { i in
                Rectangle().fill(Urgency.color(for: w, at: start.addingTimeInterval(Double(i) * 900)))
            }
        }
        .frame(width: 90, height: 8)
        .clipShape(Capsule())
    }
}

// MARK: - Location

private struct LocationTab: View {
    @ObservedObject var app: AppController
    @ObservedObject var store: Store
    @ObservedObject var location: LocationService

    var body: some View {
        Form {
            Section("Current location") {
                if let loc = store.prefs.location {
                    LabeledContent("Place", value: loc.title)
                    LabeledContent("Coordinates", value: String(format: "%.4f, %.4f", loc.latitude, loc.longitude))
                    LabeledContent("Time zone", value: loc.timeZoneID.replacingOccurrences(of: "_", with: " "))
                } else {
                    Text("No location set").foregroundStyle(.secondary)
                }
            }
            Section("Change location") {
                LocationPicker(location: location) { loc, isCurrent in
                    store.prefs.followLocation = isCurrent
                    app.apply(loc, announce: false)
                    if isCurrent { location.startMonitoringMoves() } else { location.stopMonitoringMoves() }
                }
            }
            Section {
                Toggle("Follow my location automatically", isOn: Binding(
                    get: { store.prefs.followLocation },
                    set: { on in
                        store.prefs.followLocation = on
                        if on {
                            location.startMonitoringMoves()
                            location.refresh()
                        } else {
                            location.stopMonitoringMoves()
                        }
                    }))
                Picker("When I travel", selection: $store.prefs.moveBehavior) {
                    ForEach(MoveBehavior.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!store.prefs.followLocation)
            } header: {
                Text("Travel")
            } footer: {
                Text("Nida checks your location when your Mac wakes, when the time zone changes, and every few hours. Moves under 15 km are ignored. With automatic convention, it also switches to the method mosques use in the new country.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Calculation

private struct CalculationTab: View {
    @ObservedObject var app: AppController
    @ObservedObject var store: Store

    private var recommendation: Conventions.Recommendation {
        Conventions.recommendation(for: store.prefs.location?.countryCode)
    }

    var body: some View {
        Form {
            Section {
                Picker("Convention", selection: conventionBinding) {
                    Text("Automatic — \(Conventions.convention(recommendation.conventionID).name)").tag("auto")
                    Divider()
                    ForEach(Conventions.all) { Text($0.name).tag($0.id) }
                }
                Text(Conventions.convention(store.prefs.conventionID).detail)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if store.prefs.conventionID == "custom" {
                    Stepper(value: $store.prefs.customFajr, in: 6...22, step: 0.5) {
                        LabeledContent("Fajr angle", value: String(format: "%.1f°", store.prefs.customFajr))
                    }
                    Stepper(value: $store.prefs.customIsha, in: 6...22, step: 0.5) {
                        LabeledContent("Isha angle", value: String(format: "%.1f°", store.prefs.customIsha))
                    }
                }
                Picker("Asr", selection: madhabBinding) {
                    Text("Automatic — \(recommendation.hanafi ? "Ḥanafī" : "Standard")").tag("auto")
                    Divider()
                    Text("Standard (Shāfiʿī, Mālikī, Ḥanbalī)").tag("shafi")
                    Text("Ḥanafī (later Asr)").tag("hanafi")
                }
                if Conventions.usesIshaInterval(store.prefs.conventionID) {
                    Toggle("Add 30 minutes to Isha in Ramadan", isOn: $store.prefs.ramadanIsha)
                }
            } header: {
                Text("Method")
            } footer: {
                Text("High-latitude locations use the recommended rule automatically.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section {
                ForEach(PrayerKind.allCases) { kind in
                    Stepper(value: offsetBinding(kind), in: -30...30) {
                        HStack {
                            Text(kind.name)
                            Spacer()
                            let v = store.prefs.offset(for: kind)
                            Text(v == 0 ? "—" : String(format: "%+d min", v))
                                .monospacedDigit()
                                .foregroundStyle(v == 0 ? .secondary : .primary)
                        }
                    }
                }
                Button("Reset offsets") { store.prefs.offsets = [:] }
                    .disabled(store.prefs.offsets.values.allSatisfy { $0 == 0 })
            } header: {
                Text("Adjust to match your mosque")
            } footer: {
                Text("Mosques often round or shift times by a few minutes. Nudge each prayer to match.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if let engine = app.engine {
                Section("Today with these settings") {
                    let windows = engine.windows(for: app.now)
                    HStack {
                        ForEach(windows) { w in
                            VStack(spacing: 2) {
                                Text(w.kind.name).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(engine.timeString(w.start)).font(.system(size: 12, weight: .medium).monospacedDigit())
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var conventionBinding: Binding<String> {
        Binding(
            get: { store.prefs.conventionAuto ? "auto" : store.prefs.conventionID },
            set: { v in
                var p = store.prefs
                if v == "auto" {
                    p.conventionAuto = true
                    p.conventionID = recommendation.conventionID
                } else {
                    p.conventionAuto = false
                    p.conventionID = v
                }
                store.pendingConvention = nil
                store.prefs = p
            })
    }

    private var madhabBinding: Binding<String> {
        Binding(
            get: { store.prefs.madhabAuto ? "auto" : (store.prefs.madhabHanafi ? "hanafi" : "shafi") },
            set: { v in
                var p = store.prefs
                p.madhabAuto = v == "auto"
                p.madhabHanafi = v == "auto" ? recommendation.hanafi : v == "hanafi"
                store.prefs = p
            })
    }

    private func offsetBinding(_ kind: PrayerKind) -> Binding<Int> {
        Binding(get: { store.prefs.offset(for: kind) }, set: { store.prefs.offsets[kind.rawValue] = $0 })
    }
}

// MARK: - Adhan

private struct AdhanTab: View {
    @ObservedObject var app: AppController
    @ObservedObject var store: Store
    @ObservedObject var sounds: SoundLibrary
    @ObservedObject var player: AdhanPlayer
    @ViewState private var importError: String?

    var body: some View {
        Form {
            Section("Sound") {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { store.prefs.volume },
                                          set: { store.prefs.volume = $0; player.setVolume($0) }), in: 0.05...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Copy Dhuhr settings to Asr, Maghrib & Isha") { copyDhuhrToOthers() }
                    Spacer()
                    if player.isPlaying {
                        Button { player.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    }
                }
            }

            Section("Output") {
                OutputSettingsView(prefs: $store.prefs, outputs: .shared, player: player, app: app)
            }

            ForEach(PrayerKind.allCases) { kind in
                PrayerAlertSection(kind: kind, app: app, store: store, sounds: sounds, player: player)
            }

            Section {
                ForEach(sounds.voices.filter { !$0.builtIn }) { s in
                    HStack {
                        Image(systemName: "waveform")
                        Text(s.title)
                        Spacer()
                        Text(durationText(s.duration)).foregroundStyle(.secondary).monospacedDigit()
                        Button(role: .destructive) { sounds.delete(s) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Import adhan audio…", action: importSound)
                if let importError {
                    Text(importError).font(.system(size: 11)).foregroundStyle(.red)
                }
            } header: {
                Text("Your recordings")
            } footer: {
                Text("Add any MP3, M4A, WAV or AIFF — for example a Fajr adhan with “aṣ-ṣalātu khayrun min an-nawm”, or your local mosque's muezzin.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func copyDhuhrToOthers() {
        var p = store.prefs
        let source = p.alert(for: .dhuhr)
        for k in [PrayerKind.asr, .maghrib, .isha] { p.setAlert(source, for: k) }
        store.prefs = p
    }

    private func importSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose adhan recordings to add to Nida"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        importError = nil
        for url in panel.urls {
            do { try sounds.importSound(from: url) } catch {
                importError = "Couldn't import \(url.lastPathComponent): not a playable audio file."
            }
        }
    }
}

private func durationText(_ s: Double) -> String {
    let t = Int(s.rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
}

private struct PrayerAlertSection: View {
    let kind: PrayerKind
    @ObservedObject var app: AppController
    @ObservedObject var store: Store
    @ObservedObject var sounds: SoundLibrary
    @ObservedObject var player: AdhanPlayer

    private var alert: Binding<PrayerAlert> {
        Binding(get: { store.prefs.alert(for: kind) }, set: { store.prefs.setAlert($0, for: kind) })
    }

    var body: some View {
        Section {
            Picker("At prayer time", selection: alert.style) {
                ForEach(AlertStyle.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            if alert.wrappedValue.style == .adhan {
                Picker("Voice", selection: alert.soundID) {
                    ForEach(sounds.voices) { s in
                        Text("\(s.title)  ·  \(durationText(s.duration))").tag(s.id)
                    }
                }
                Picker("Length", selection: alert.length) {
                    ForEach(AdhanLength.allCases) { Text($0.label).tag($0) }
                }
            }
            if alert.wrappedValue.style != .off {
                Picker("Reminder", selection: alert.reminderMinutes) {
                    Text("None").tag(0)
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) minutes before").tag($0) }
                }
            }
        } header: {
            HStack {
                Image(systemName: kind.symbol).symbolRenderingMode(.hierarchical)
                Text(kind.name)
                Text(kind.arabic).foregroundStyle(.secondary)
                Spacer()
                if alert.wrappedValue.style == .adhan || alert.wrappedValue.style == .chime {
                    Button {
                        if player.nowPlaying == "Preview" { player.stop() } else {
                            let a = alert.wrappedValue
                            app.preview(a.style == .chime ? SoundLibrary.chimeID : a.soundID, length: a.length)
                        }
                    } label: {
                        Label(player.nowPlaying == "Preview" ? "Stop" : "Preview",
                              systemImage: player.nowPlaying == "Preview" ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    @ObservedObject var sounds: SoundLibrary

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Nida").font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("نداء · the call").foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Prayer times are calculated on your Mac — no account, no server, works offline.")
                .font(.system(size: 12)).multilineTextAlignment(.center).frame(maxWidth: 380)
            Divider().frame(width: 300)
            VStack(alignment: .leading, spacing: 6) {
                Text("Credits").font(.system(size: 12, weight: .semibold))
                Text("Prayer calculation: Adhan Swift by Batoul Apps (MIT)").font(.system(size: 11))
                ForEach(sounds.sounds.filter(\.builtIn)) { s in
                    Text("\(s.title): \(s.credit)").font(.system(size: 11))
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: 420, alignment: .leading)
            Spacer()
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    }
}
