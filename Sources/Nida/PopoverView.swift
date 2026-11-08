import SwiftUI

struct PopoverView: View {
    @ObservedObject var app: AppController
    @ObservedObject var store: Store
    @ObservedObject var player: AdhanPlayer

    var body: some View {
        VStack(spacing: 0) {
            header
            if player.isPlaying { playingBar }
            if let move = store.pendingMove { moveBanner(move) }
            if let conv = store.pendingConvention { conventionBanner(conv) }
            if let engine = app.engine {
                if engine.usesNearestLatitude(on: app.now) {
                    Label("The sun doesn't rise or set here today — using times from the nearest latitude where it does.",
                          systemImage: "globe.europe.africa")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.bottom, 6)
                }
                hero(engine)
                Divider().padding(.horizontal, 14)
                prayerList(engine)
                Divider().padding(.horizontal, 14)
                footer(engine)
            } else {
                noLocation
            }
        }
        .frame(width: 310)
        .background(.regularMaterial)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: store.prefs.followLocation ? "location.fill" : "mappin.and.ellipse")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(store.prefs.location?.title ?? "No location")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text(conventionLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Settings…") { app.showSettings() }
                Button("Run setup again…") { app.showOnboarding() }
                Divider()
                Button("Quit Nida") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var conventionLine: String {
        let p = store.prefs
        let conv = Conventions.convention(p.conventionID).name
        return "\(conv) · \(p.madhabHanafi ? "Ḥanafī" : "Standard") Asr"
    }

    // MARK: Banners

    private var playingBar: some View {
        HStack {
            Image(systemName: "speaker.wave.2.fill").symbolRenderingMode(.hierarchical)
            Text(player.nowPlaying ?? "").font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Stop") { player.stop() }
                .keyboardShortcut(.space, modifiers: [])
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.14)))
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    private func moveBanner(_ loc: SavedLocation) -> some View {
        banner(icon: "location.circle.fill",
               title: "You're in \(loc.title)",
               message: "Update prayer times for this location?",
               accept: "Update", acceptAction: app.acceptPendingMove,
               dismiss: "Keep", dismissAction: app.dismissPendingMove)
    }

    private func conventionBanner(_ id: String) -> some View {
        banner(icon: "globe",
               title: "\(Conventions.convention(id).name)?",
               message: "It's the usual convention here.",
               accept: "Switch", acceptAction: app.acceptPendingConvention,
               dismiss: "Keep mine", dismissAction: app.dismissPendingConvention)
    }

    private func banner(icon: String, title: String, message: String,
                        accept: String, acceptAction: @escaping () -> Void,
                        dismiss: String, dismissAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
            }
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(dismiss, action: dismissAction).controlSize(.small)
                Button(accept, action: acceptAction).controlSize(.small).keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    // MARK: Hero

    @ViewBuilder
    private func hero(_ engine: PrayerEngine) -> some View {
        if let phase = app.phase {
            let w = phase.window
            let name = w.kind.displayName(on: w.start, calendar: engine.calendar)
            let arabic = w.kind.displayArabic(on: w.start, calendar: engine.calendar)
            let tint: Color = phase.isOpen && store.prefs.colorize ? Urgency.color(for: w, at: app.now) : .secondary
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(phase.isOpen ? "NOW" : "NEXT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                    Spacer()
                    Text(arabic).font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
                }
                HStack(alignment: .lastTextBaseline) {
                    Image(systemName: w.kind.symbol)
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(phase.isOpen ? tint : .primary)
                    Text(name).font(.system(size: 26, weight: .semibold, design: .rounded))
                    Spacer()
                    if phase.isOpen {
                        Text("\(Format.duration(w.remaining(at: app.now))) left")
                            .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(tint)
                    } else {
                        Text("in \(Format.countdown(w.start.timeIntervalSince(app.now), showSeconds: true))")
                            .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if phase.isOpen {
                    WindowBar(fraction: w.fractionRemaining(at: app.now), tint: tint)
                    Text(endLine(w, engine))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let next = engine.windows(around: app.now).first(where: { $0.start > app.now }) {
                        Text("Next: \(next.kind.displayName(on: next.start, calendar: engine.calendar)) in \(Format.countdown(next.start.timeIntervalSince(app.now), showSeconds: true)) · at \(engine.timeString(next.start))")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Begins at \(engine.timeString(w.start))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func endLine(_ w: PrayerWindow, _ engine: PrayerEngine) -> String {
        let end = engine.timeString(w.end)
        switch w.kind {
        case .fajr: return "Started \(engine.timeString(w.start)) · ends at sunrise \(end)"
        case .isha where store.prefs.ishaEnd == .midnight: return "Started \(engine.timeString(w.start)) · ends at midnight \(end)"
        default: return "Started \(engine.timeString(w.start)) · ends \(end)"
        }
    }

    // MARK: List

    private func prayerList(_ engine: PrayerEngine) -> some View {
        let today = engine.windows(for: app.now)
        let sunrise = engine.times(for: app.now)?.sunrise
        return VStack(spacing: 2) {
            ForEach(today) { w in
                row(w, engine)
                if w.kind == .fajr, let sunrise {
                    sunriseRow(sunrise, engine)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
    }

    private func row(_ w: PrayerWindow, _ engine: PrayerEngine) -> some View {
        let isOpen = w.contains(app.now)
        let isNext = app.phase.map { !$0.isOpen && $0.window == w } ?? false
        let isPast = w.end <= app.now
        let tint: Color = isOpen && store.prefs.colorize ? Urgency.color(for: w, at: app.now) : .accentColor
        let alert = store.prefs.alert(for: w.kind)
        return HStack(spacing: 10) {
            Circle()
                .fill(isOpen ? tint : (isNext ? Color.accentColor.opacity(0.7) : Color.clear))
                .frame(width: 6, height: 6)
            Image(systemName: w.kind.symbol)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18)
                .foregroundStyle(isPast ? .tertiary : .secondary)
            Text(w.kind.displayName(on: w.start, calendar: engine.calendar))
                .font(.system(size: 13, weight: isOpen || isNext ? .semibold : .regular))
            Spacer()
            Text(engine.timeString(w.start))
                .font(.system(size: 13, weight: isOpen || isNext ? .semibold : .regular).monospacedDigit())
            Button {
                var p = store.prefs
                var a = alert
                a.style = a.style.next
                p.setAlert(a, for: w.kind)
                store.prefs = p
            } label: {
                Image(systemName: alert.style.symbol)
                    .font(.system(size: 11))
                    .frame(width: 18)
                    .foregroundStyle(alert.style == .off ? .tertiary : .secondary)
            }
            .buttonStyle(.borderless)
            .help("\(alert.style.label) — click to change")
        }
        .foregroundStyle(isPast && !isOpen ? .secondary : .primary)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isOpen ? tint.opacity(0.14) : (isNext ? Color.accentColor.opacity(0.08) : .clear))
        )
    }

    private func sunriseRow(_ sunrise: Date, _ engine: PrayerEngine) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.clear).frame(width: 6, height: 6)
            Image(systemName: "sunrise").frame(width: 18)
            Text("Sunrise").font(.system(size: 12))
            Spacer()
            Text(engine.timeString(sunrise)).font(.system(size: 12).monospacedDigit())
            Color.clear.frame(width: 18, height: 1)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8).padding(.vertical, 3)
    }

    // MARK: Footer

    private func footer(_ engine: PrayerEngine) -> some View {
        HStack(spacing: 10) {
            Text(engine.hijriString(app.now))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var noLocation: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Nida needs a location to calculate prayer times.")
                .font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Set location…") {
                if store.prefs.onboarded { app.showSettings(tab: .location) } else { app.showOnboarding() }
            }
            .keyboardShortcut(.defaultAction)
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.system(size: 11))
            }
        }
        .padding(16)
    }
}

/// Remaining-time bar: full and green when the window opens, draining toward red.
struct WindowBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .animation(.easeInOut(duration: 0.6), value: fraction)
    }
}
