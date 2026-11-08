import AppKit
import SwiftUI
import Adhan

struct DayTimes {
    let fajr, sunrise, dhuhr, asr, maghrib, isha: Date
    let nextFajr: Date
    let midnight: Date
    let lastThird: Date

    func start(_ kind: PrayerKind) -> Date {
        switch kind {
        case .fajr: fajr
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }
}

/// The time during which a prayer can be performed: from its start until the next boundary.
struct PrayerWindow: Equatable, Identifiable {
    let kind: PrayerKind
    let start: Date
    let end: Date

    var id: String { "\(kind.rawValue)-\(Int(start.timeIntervalSince1970))" }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    func contains(_ date: Date) -> Bool { date >= start && date < end }
    func remaining(at date: Date) -> TimeInterval { max(0, end.timeIntervalSince(date)) }
    func fractionRemaining(at date: Date) -> Double {
        duration > 0 ? min(1, max(0, remaining(at: date) / duration)) : 0
    }
}

enum PrayerPhase: Equatable {
    case open(PrayerWindow)
    case waiting(PrayerWindow)

    var window: PrayerWindow {
        switch self {
        case .open(let w), .waiting(let w): w
        }
    }
    var isOpen: Bool { if case .open = self { true } else { false } }
}

/// Holds computed days so each day is calculated once, not every second.
final class DayCache {
    var times: [Int: DayTimes?] = [:]
    var windows: [Int: [PrayerWindow]] = [:]
    var polar: [Int: Bool] = [:]

    func trim() {
        if times.count > 8 { times.removeAll(); windows.removeAll(); polar.removeAll() }
    }
}

struct PrayerEngine {
    let prefs: Preferences
    let location: SavedLocation
    let calendar: Calendar
    private let cache = DayCache()

    private func dayKey(_ date: Date) -> Int { Int(calendar.startOfDay(for: date).timeIntervalSince1970) }

    init(prefs: Preferences, location: SavedLocation) {
        self.prefs = prefs
        self.location = location
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = location.timeZone
        self.calendar = cal
    }

    var coordinates: Coordinates { Coordinates(latitude: location.latitude, longitude: location.longitude) }

    func isRamadan(_ date: Date) -> Bool {
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = location.timeZone
        return hijri.component(.month, from: date) == 9
    }

    func parameters(for day: Date) -> CalculationParameters {
        var p = Conventions.parameters(id: prefs.conventionID, prefs: prefs)
        p.madhab = prefs.madhabHanafi ? .hanafi : .shafi
        var isha = prefs.offset(for: .isha)
        if prefs.ramadanIsha && Conventions.usesIshaInterval(prefs.conventionID) && isRamadan(day) {
            isha += 30
        }
        p.adjustments = PrayerAdjustments(
            fajr: prefs.offset(for: .fajr),
            sunrise: 0,
            dhuhr: prefs.offset(for: .dhuhr),
            asr: prefs.offset(for: .asr),
            maghrib: prefs.offset(for: .maghrib),
            isha: isha
        )
        return p
    }

    private func prayerTimes(for day: Date) -> PrayerTimes? {
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        let params = parameters(for: day)
        if let t = PrayerTimes(coordinates: coordinates, date: comps, calculationParameters: params) { return t }
        // Polar day/night: the sun doesn't rise or set. Use the nearest latitude where it does
        // (the "aqrab al-bilād" approach), keeping the same longitude.
        let sign: Double = location.latitude >= 0 ? 1 : -1
        for lat in stride(from: min(abs(location.latitude), 66.0), through: 60.0, by: -0.5) {
            let c = Coordinates(latitude: sign * lat, longitude: location.longitude)
            if let t = PrayerTimes(coordinates: c, date: comps, calculationParameters: params) { return t }
        }
        return nil
    }

    /// True when the sun doesn't rise or set here today and times come from a nearer latitude.
    func usesNearestLatitude(on day: Date) -> Bool {
        let key = dayKey(day)
        if let hit = cache.polar[key] { return hit }
        let result = computeNearestLatitude(day)
        cache.polar[key] = result
        return result
    }

    private func computeNearestLatitude(_ day: Date) -> Bool {
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        return PrayerTimes(coordinates: coordinates, date: comps, calculationParameters: parameters(for: day)) == nil
    }

    func times(for day: Date) -> DayTimes? {
        let key = dayKey(day)
        if let hit = cache.times[key] { return hit }
        cache.trim()
        let result = computeTimes(day)
        cache.times[key] = result
        return result
    }

    private func computeTimes(_ day: Date) -> DayTimes? {
        guard
            let t = prayerTimes(for: day),
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day),
            let n = prayerTimes(for: tomorrow)
        else { return nil }
        let sunnah = SunnahTimes(from: t)
        return DayTimes(
            fajr: t.fajr, sunrise: t.sunrise, dhuhr: t.dhuhr, asr: t.asr, maghrib: t.maghrib, isha: t.isha,
            nextFajr: n.fajr,
            midnight: sunnah?.middleOfTheNight ?? n.fajr,
            lastThird: sunnah?.lastThirdOfTheNight ?? n.fajr
        )
    }

    func windows(for day: Date) -> [PrayerWindow] {
        let key = dayKey(day)
        if let hit = cache.windows[key] { return hit }
        let result = computeWindows(day)
        cache.windows[key] = result
        return result
    }

    private func computeWindows(_ day: Date) -> [PrayerWindow] {
        guard let t = times(for: day) else { return [] }
        let ishaEnd = prefs.ishaEnd == .midnight ? t.midnight : t.nextFajr
        return [
            PrayerWindow(kind: .fajr, start: t.fajr, end: t.sunrise),
            PrayerWindow(kind: .dhuhr, start: t.dhuhr, end: t.asr),
            PrayerWindow(kind: .asr, start: t.asr, end: t.maghrib),
            PrayerWindow(kind: .maghrib, start: t.maghrib, end: t.isha),
            PrayerWindow(kind: .isha, start: t.isha, end: max(ishaEnd, t.isha.addingTimeInterval(60))),
        ]
    }

    /// Windows from yesterday through tomorrow, so the night-spanning Isha window is covered.
    func windows(around date: Date) -> [PrayerWindow] {
        (-1...1).flatMap { offset in
            calendar.date(byAdding: .day, value: offset, to: date).map(windows(for:)) ?? []
        }
    }

    func phase(at now: Date) -> PrayerPhase? {
        let all = windows(around: now)
        if let open = all.last(where: { $0.contains(now) }) { return .open(open) }
        if let next = all.first(where: { $0.start > now }) { return .waiting(next) }
        return nil
    }

    // Date formatters are expensive to create, so one per time zone is kept.
    private static var timeFormatters: [String: DateFormatter] = [:]
    private static var hijriFormatters: [String: DateFormatter] = [:]

    func timeString(_ date: Date) -> String {
        let id = location.timeZoneID
        let f = Self.timeFormatters[id] ?? {
            let f = DateFormatter()
            f.timeZone = location.timeZone
            f.timeStyle = .short
            f.dateStyle = .none
            Self.timeFormatters[id] = f
            return f
        }()
        return f.string(from: date)
    }

    func hijriString(_ date: Date) -> String {
        let id = location.timeZoneID
        let f = Self.hijriFormatters[id] ?? {
            let f = DateFormatter()
            var cal = Calendar(identifier: .islamicUmmAlQura)
            cal.timeZone = location.timeZone
            f.calendar = cal
            f.timeZone = location.timeZone
            f.setLocalizedDateFormatFromTemplate("d MMMM y")
            Self.hijriFormatters[id] = f
            return f
        }()
        return f.string(from: date)
    }
}

// MARK: - Colors

enum Urgency {
    /// Green while most of the window remains, through amber, to red as it closes.
    static func nsColor(for window: PrayerWindow, at now: Date) -> NSColor {
        let r = window.fractionRemaining(at: now)
        var t = min(1, max(0, (0.55 - r) / 0.45))      // 0 = plenty of time, 1 = closing
        if window.remaining(at: now) < 10 * 60 { t = max(t, 0.92) }
        let hue = 0.37 * (1 - t)                       // 133° green → 0° red
        return NSColor(calibratedHue: hue, saturation: 0.78, brightness: 0.86, alpha: 1)
    }

    static func color(for window: PrayerWindow, at now: Date) -> Color {
        Color(nsColor: nsColor(for: window, at: now))
    }
}


enum Format {
    /// Live countdown: "55:42", "5:12:08", or "1h 12m" without seconds.
    static func countdown(_ seconds: TimeInterval, showSeconds: Bool) -> String {
        guard showSeconds else { return duration(seconds) }
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

}
