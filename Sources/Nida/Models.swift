import Foundation
import CoreLocation

// MARK: - Prayers

enum PrayerKind: String, CaseIterable, Codable, Identifiable {
    case fajr, dhuhr, asr, maghrib, isha

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    var arabic: String {
        switch self {
        case .fajr: "الفجر"
        case .dhuhr: "الظهر"
        case .asr: "العصر"
        case .maghrib: "المغرب"
        case .isha: "العشاء"
        }
    }

    var symbol: String {
        switch self {
        case .fajr: "sun.haze.fill"
        case .dhuhr: "sun.max.fill"
        case .asr: "sun.min.fill"
        case .maghrib: "sunset.fill"
        case .isha: "moon.stars.fill"
        }
    }

    /// Dhuhr is shown as Jumuʿah on Fridays.
    func displayName(on date: Date, calendar: Calendar) -> String {
        if self == .dhuhr && calendar.component(.weekday, from: date) == 6 { return "Jumuʿah" }
        return name
    }

    func displayArabic(on date: Date, calendar: Calendar) -> String {
        if self == .dhuhr && calendar.component(.weekday, from: date) == 6 { return "الجمعة" }
        return arabic
    }
}

// MARK: - Alert settings

enum AlertStyle: String, Codable, CaseIterable, Identifiable {
    case adhan, chime, banner, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .adhan: "Adhan"
        case .chime: "Gentle chime"
        case .banner: "Notification only"
        case .off: "Off"
        }
    }
    var symbol: String {
        switch self {
        case .adhan: "speaker.wave.2.fill"
        case .chime: "bell.fill"
        case .banner: "bell.badge"
        case .off: "bell.slash"
        }
    }
    var next: AlertStyle {
        let all = AlertStyle.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

enum AdhanLength: String, Codable, CaseIterable, Identifiable {
    case full, takbir, s30, s60, s90, s120
    var id: String { rawValue }
    var label: String {
        switch self {
        case .full: "Full adhan"
        case .takbir: "Opening takbīr only"
        case .s30: "About 30 seconds"
        case .s60: "About 1 minute"
        case .s90: "About 1½ minutes"
        case .s120: "About 2 minutes"
        }
    }
    var seconds: Double? {
        switch self {
        case .full, .takbir: nil
        case .s30: 30
        case .s60: 60
        case .s90: 90
        case .s120: 120
        }
    }
}

struct PrayerAlert: Codable, Equatable {
    var style: AlertStyle = .adhan
    var soundID: String = "adhan-classic"
    var length: AdhanLength = .full
    var reminderMinutes: Int = 0
}

enum MenuStyle: String, Codable, CaseIterable, Identifiable {
    case time, countdown, icon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .time: "Time left + next prayer"
        case .countdown: "Time left only"
        case .icon: "Color only"
        }
    }
}

enum SecondsMode: String, Codable, CaseIterable, Identifiable {
    case always, final, never
    static let finalWindow: TimeInterval = 10 * 60
    var id: String { rawValue }
    var label: String {
        switch self {
        case .always: "Always"
        case .final: "Final 10 minutes"
        case .never: "Never"
        }
    }
}

enum IshaEnd: String, Codable, CaseIterable, Identifiable {
    case midnight, fajr
    var id: String { rawValue }
    var label: String {
        switch self {
        case .midnight: "Islamic midnight"
        case .fajr: "Fajr"
        }
    }
}

enum MoveBehavior: String, Codable, CaseIterable, Identifiable {
    case automatic, ask, ignore
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Update automatically"
        case .ask: "Ask me first"
        case .ignore: "Do nothing"
        }
    }
}

// MARK: - Location

struct SavedLocation: Codable, Equatable, Identifiable {
    var name: String
    var country: String
    var countryCode: String?
    var latitude: Double
    var longitude: Double
    var timeZoneID: String

    var id: String { "\(latitude),\(longitude)" }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var title: String { country.isEmpty || country == name ? name : "\(name), \(country)" }
    var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    func distance(to other: SavedLocation) -> CLLocationDistance {
        clLocation.distance(from: other.clLocation)
    }

    static func from(_ placemark: CLPlacemark?, fallback: CLLocation) -> SavedLocation {
        let loc = placemark?.location ?? fallback
        let name = placemark?.locality
            ?? placemark?.subAdministrativeArea
            ?? placemark?.administrativeArea
            ?? placemark?.name
            ?? String(format: "%.3f, %.3f", loc.coordinate.latitude, loc.coordinate.longitude)
        return SavedLocation(
            name: name,
            country: placemark?.country ?? "",
            countryCode: placemark?.isoCountryCode,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            timeZoneID: placemark?.timeZone?.identifier ?? TimeZone.current.identifier
        )
    }
}

// MARK: - Preferences

struct Preferences: Codable, Equatable {
    var onboarded = false

    var location: SavedLocation? = nil
    var followLocation = true
    var moveBehavior: MoveBehavior = .automatic

    var conventionID = "mwl"
    var conventionAuto = true
    var madhabHanafi = false
    var madhabAuto = true
    var customFajr = 18.0
    var customIsha = 17.0
    var offsets: [String: Int] = [:]
    var ishaEnd: IshaEnd = .midnight
    var ramadanIsha = true

    var alerts: [String: PrayerAlert] = [:]
    var volume = 0.8
    /// CoreAudio UID of the output the adhan always plays on; nil = system default.
    var outputUID: String? = nil
    /// Name of that output, shown while it's disconnected.
    var outputName: String = ""
    /// Temporarily raise (and unmute) the output for the adhan, then restore it.
    var raiseVolume = false
    var raiseVolumeLevel = 0.6
    var closingWarning = 0

    var menuStyle: MenuStyle = .time
    var colorize = true
    /// When the menu bar countdown ticks in seconds. Each menu bar redraw costs CPU,
    /// so by default seconds appear only in the final minutes before a prayer.
    var secondsMode: SecondsMode = .final

    func menuBarShowsSeconds(remaining: TimeInterval) -> Bool {
        switch secondsMode {
        case .always: true
        case .final: remaining <= SecondsMode.finalWindow
        case .never: false
        }
    }

    func alert(for kind: PrayerKind) -> PrayerAlert { alerts[kind.rawValue] ?? PrayerAlert() }
    mutating func setAlert(_ alert: PrayerAlert, for kind: PrayerKind) { alerts[kind.rawValue] = alert }
    func offset(for kind: PrayerKind) -> Int { offsets[kind.rawValue] ?? 0 }

    var audioRoute: AdhanPlayer.Route {
        AdhanPlayer.Route(outputUID: outputUID, raiseTo: raiseVolume ? Float(raiseVolumeLevel) : nil)
    }
}

final class Store: ObservableObject {
    static let shared = Store()
    private static let key = "preferences.v1"

    @Published var prefs: Preferences {
        didSet { if prefs != oldValue { save() } }
    }
    /// A detected move the user hasn't confirmed yet (move behavior = ask).
    @Published var pendingMove: SavedLocation?
    /// A convention suggested for a new country while the user has a manual convention.
    @Published var pendingConvention: String?

    private init() { prefs = Self.load() }

    /// Off in snapshot mode so rendering sample data never touches real preferences.
    static var persist = true

    private func save() {
        guard Self.persist else { return }
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Decodes stored preferences, filling any keys added in newer versions from defaults.
    private static func load() -> Preferences {
        let defaults = Preferences()
        guard let data = UserDefaults.standard.data(forKey: key) else { return defaults }
        if let p = try? JSONDecoder().decode(Preferences.self, from: data) { return p }
        guard
            let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let baseData = try? JSONEncoder().encode(defaults),
            var base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any]
        else { return defaults }
        base.merge(stored) { _, new in new }
        guard
            let merged = try? JSONSerialization.data(withJSONObject: base),
            let p = try? JSONDecoder().decode(Preferences.self, from: merged)
        else { return defaults }
        return p
    }
}
