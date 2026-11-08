import Foundation
import Adhan

struct Convention: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
}

enum Conventions {
    static let all: [Convention] = [
        Convention(id: "mwl", name: "Muslim World League", detail: "Fajr 18° · Isha 17° — Europe, Far East, general default"),
        Convention(id: "isna", name: "ISNA (North America)", detail: "Fajr 15° · Isha 15° — USA, Canada"),
        Convention(id: "moonsighting", name: "Moonsighting Committee", detail: "18° with seasonal adjustment — UK, North America"),
        Convention(id: "france", name: "UOIF (France)", detail: "Fajr 12° · Isha 12° — France"),
        Convention(id: "egypt", name: "Egyptian General Authority", detail: "Fajr 19.5° · Isha 17.5° — Egypt, Africa, Levant"),
        Convention(id: "ummalqura", name: "Umm al-Qura (Makkah)", detail: "Fajr 18.5° · Isha 90 min after Maghrib — Saudi Arabia"),
        Convention(id: "dubai", name: "Dubai (UAE)", detail: "Fajr 18.2° · Isha 18.2° — United Arab Emirates"),
        Convention(id: "qatar", name: "Qatar", detail: "Fajr 18° · Isha 90 min after Maghrib — Qatar"),
        Convention(id: "kuwait", name: "Kuwait", detail: "Fajr 18° · Isha 17.5° — Kuwait"),
        Convention(id: "karachi", name: "University of Islamic Sciences, Karachi", detail: "Fajr 18° · Isha 18° — Pakistan, India, Bangladesh"),
        Convention(id: "turkey", name: "Diyanet (Türkiye)", detail: "Approximation of the Diyanet method — Türkiye"),
        Convention(id: "morocco", name: "Ministry of Habous (Morocco)", detail: "Fajr 19° · Isha 17° — Morocco"),
        Convention(id: "algeria", name: "Ministry of Religious Affairs (Algeria)", detail: "Fajr 18° · Isha 17° — Algeria"),
        Convention(id: "tunisia", name: "Tunisia", detail: "Fajr 18° · Isha 18° — Tunisia"),
        Convention(id: "jordan", name: "Jordan", detail: "Fajr 18° · Isha 18° — Jordan, Palestine"),
        Convention(id: "singapore", name: "MUIS (Singapore)", detail: "Fajr 20° · Isha 18° — Singapore, Brunei"),
        Convention(id: "jakim", name: "JAKIM (Malaysia)", detail: "Fajr 20° · Isha 18° — Malaysia"),
        Convention(id: "kemenag", name: "Kemenag (Indonesia)", detail: "Fajr 20° · Isha 18° — Indonesia"),
        Convention(id: "tehran", name: "Institute of Geophysics, Tehran", detail: "Fajr 17.7° · Isha 14° · Maghrib 4.5° — Iran"),
        Convention(id: "russia", name: "Spiritual Administration (Russia)", detail: "Fajr 16° · Isha 15° — Russia"),
        Convention(id: "custom", name: "Custom angles", detail: "Set your own Fajr and Isha angles"),
    ]

    static func convention(_ id: String) -> Convention {
        all.first { $0.id == id } ?? all[0]
    }

    /// Conventions whose Isha is a fixed interval after Maghrib (+30 min in Ramadan).
    static func usesIshaInterval(_ id: String) -> Bool { id == "ummalqura" || id == "qatar" }

    static func parameters(id: String, prefs: Preferences) -> CalculationParameters {
        switch id {
        case "mwl": return CalculationMethod.muslimWorldLeague.params
        case "isna": return CalculationMethod.northAmerica.params
        case "moonsighting": return CalculationMethod.moonsightingCommittee.params
        case "egypt": return CalculationMethod.egyptian.params
        case "karachi": return CalculationMethod.karachi.params
        case "ummalqura": return CalculationMethod.ummAlQura.params
        case "dubai": return CalculationMethod.dubai.params
        case "kuwait": return CalculationMethod.kuwait.params
        case "qatar": return CalculationMethod.qatar.params
        case "singapore", "jakim": return CalculationMethod.singapore.params
        case "tehran": return CalculationMethod.tehran.params
        case "turkey": return CalculationMethod.turkey.params
        case "kemenag": return angles(20, 18)
        case "france": return angles(12, 12)
        case "morocco": return angles(19, 17)
        case "algeria": return angles(18, 17)
        case "tunisia": return angles(18, 18)
        case "jordan": return angles(18, 18)
        case "russia": return angles(16, 15)
        case "custom": return angles(prefs.customFajr, prefs.customIsha)
        default: return CalculationMethod.muslimWorldLeague.params
        }
    }

    private static func angles(_ fajr: Double, _ isha: Double) -> CalculationParameters {
        var p = CalculationMethod.other.params
        p.fajrAngle = fajr
        p.ishaAngle = isha
        return p
    }

    struct Recommendation {
        let conventionID: String
        let hanafi: Bool
    }

    private static let byCountry: [String: String] = [
        "US": "isna", "CA": "isna", "MX": "isna",
        "GB": "moonsighting", "IE": "moonsighting",
        "FR": "france",
        "SA": "ummalqura", "YE": "ummalqura", "BH": "ummalqura", "OM": "ummalqura",
        "AE": "dubai", "QA": "qatar", "KW": "kuwait",
        "EG": "egypt", "SD": "egypt", "LY": "egypt", "SY": "egypt", "LB": "egypt", "IQ": "egypt",
        "SS": "egypt", "ER": "egypt", "SO": "egypt", "DJ": "egypt",
        "JO": "jordan", "PS": "jordan",
        "PK": "karachi", "IN": "karachi", "BD": "karachi", "AF": "karachi", "NP": "karachi", "LK": "karachi",
        "TR": "turkey", "CY": "turkey",
        "MA": "morocco", "EH": "morocco", "DZ": "algeria", "TN": "tunisia",
        "SG": "singapore", "BN": "singapore", "MY": "jakim", "ID": "kemenag",
        "IR": "tehran",
        "RU": "russia",
    ]

    /// Countries where the Hanafi school (later Asr) predominates.
    private static let hanafiCountries: Set<String> = [
        "PK", "IN", "BD", "AF", "TR", "CY", "RU", "KZ", "UZ", "KG", "TJ", "TM", "AZ", "BA", "AL", "XK", "MK",
    ]

    static func recommendation(for countryCode: String?) -> Recommendation {
        let code = countryCode?.uppercased() ?? ""
        return Recommendation(conventionID: byCountry[code] ?? "mwl", hanafi: hanafiCountries.contains(code))
    }
}
