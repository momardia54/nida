import AppKit
import CoreLocation
import UserNotifications
import Intents

// MARK: - Notifications

enum NotificationAction {
    static let stop = "STOP_ADHAN"
    static let moveAccept = "MOVE_ACCEPT"
    static let moveKeep = "MOVE_KEEP"
    static let conventionAccept = "CONV_ACCEPT"
    static let conventionKeep = "CONV_KEEP"
    static let prayed = "MARK_PRAYED"
}

enum NotificationCategory {
    static let prayer = "PRAYER"
    /// Before a prayer begins: nothing to stop or mark yet.
    static let reminder = "REMINDER"
    static let move = "MOVE"
    static let convention = "CONVENTION"
}

final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    @Published private(set) var authorized = false
    /// Called on the main thread with (action identifier, category, notification identifier).
    var onAction: ((String, String, String) -> Void)?

    private var center: UNUserNotificationCenter { .current() }
    /// UNUserNotificationCenter throws outside an app bundle (e.g. the bare debug binary).
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func setUp() {
        guard available else { return }
        center.delegate = self
        let stop = UNNotificationAction(identifier: NotificationAction.stop, title: "Stop adhan", options: [])
        let accept = UNNotificationAction(identifier: NotificationAction.moveAccept, title: "Update times", options: [])
        let keep = UNNotificationAction(identifier: NotificationAction.moveKeep, title: "Keep current", options: [])
        let convAccept = UNNotificationAction(identifier: NotificationAction.conventionAccept, title: "Switch", options: [])
        let convKeep = UNNotificationAction(identifier: NotificationAction.conventionKeep, title: "Keep mine", options: [])
        let prayed = UNNotificationAction(identifier: NotificationAction.prayed, title: "Prayed ✓", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: NotificationCategory.prayer, actions: [prayed, stop], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.reminder, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.move, actions: [accept, keep], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.convention, actions: [convAccept, convKeep], intentIdentifiers: []),
        ])
        refreshStatus()
    }

    func refreshStatus() {
        guard available else { return }
        center.getNotificationSettings { settings in
            let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { self.authorized = ok }
        }
    }

    func requestAuthorization(_ done: ((Bool) -> Void)? = nil) {
        guard available else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.authorized = granted
                done?(granted)
            }
        }
    }

    func post(id: String, title: String, body: String, category: String, playSound: Bool = false) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        if playSound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(category: String) {
        guard available else { return }
        center.getDeliveredNotifications { delivered in
            let ids = delivered.filter { $0.request.content.categoryIdentifier == category }.map(\.request.identifier)
            self.center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let id = response.notification.request.identifier
        DispatchQueue.main.async { self.onAction?(action, category, id) }
        completionHandler()
    }
}

// MARK: - Location

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isLocating = false
    @Published var lastError: String?

    /// Locations detected in the background (significant changes, wake, time zone change).
    var onBackgroundLocation: ((SavedLocation) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var pending: [(Result<SavedLocation, Error>) -> Void] = []
    private var wantsLocationAfterAuth = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        switch authorization {
        case .notDetermined, .denied, .restricted: false
        default: true
        }
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// One-shot current location. Completion runs on the main thread.
    func requestCurrent(_ completion: @escaping (Result<SavedLocation, Error>) -> Void) {
        pending.append(completion)
        startRequest()
    }

    /// Background refresh; result goes to `onBackgroundLocation`.
    func refresh() {
        guard isAuthorized else { return }
        startRequest()
    }

    private func startRequest() {
        lastError = nil
        if authorization == .notDetermined {
            wantsLocationAfterAuth = true
            manager.requestWhenInUseAuthorization()
            return
        }
        guard isAuthorized else {
            fail(NSError(domain: "Nida", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Location access is off. Enable it in System Settings › Privacy & Security › Location Services, or search for your city."]))
            return
        }
        isLocating = true
        manager.requestLocation()
    }

    func startMonitoringMoves() {
        guard isAuthorized, CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopMonitoringMoves() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    func search(_ query: String, completion: @escaping ([SavedLocation]) -> Void) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { completion([]); return }
        geocoder.cancelGeocode()
        geocoder.geocodeAddressString(q) { placemarks, _ in
            let results = (placemarks ?? []).compactMap { pm -> SavedLocation? in
                guard let loc = pm.location else { return nil }
                return SavedLocation.from(pm, fallback: loc)
            }
            DispatchQueue.main.async { completion(results) }
        }
    }

    private func fail(_ error: Error) {
        isLocating = false
        lastError = error.localizedDescription
        let callbacks = pending
        pending.removeAll()
        callbacks.forEach { $0(.failure(error)) }
    }

    private func deliver(_ location: SavedLocation) {
        isLocating = false
        let callbacks = pending
        pending.removeAll()
        if callbacks.isEmpty {
            onBackgroundLocation?(location)
        } else {
            callbacks.forEach { $0(.success(location)) }
        }
    }

    // CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorization = manager.authorizationStatus
            if self.wantsLocationAfterAuth && self.authorization != .notDetermined {
                self.wantsLocationAfterAuth = false
                self.startRequest()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
            let saved = SavedLocation.from(placemarks?.first, fallback: loc)
            DispatchQueue.main.async { self.deliver(saved) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            if (error as? CLError)?.code == .locationUnknown, self.pending.isEmpty { self.isLocating = false; return }
            self.fail(NSError(domain: "Nida", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Couldn't determine your location. Check Wi-Fi is on, or search for your city instead."]))
        }
    }
}

// MARK: - Quiet times (Focus, Do Not Disturb, muted output)


/// Tells whether the Mac is meant to be quiet right now: a Focus (including Do Not Disturb) is on,
/// or the output the adhan would play on is muted.
final class SilenceMonitor: ObservableObject {
    static let shared = SilenceMonitor()

    enum Reason: Equatable {
        case focus, muted
        var label: String {
            switch self {
            case .focus: "Focus is on"
            case .muted: "the sound is muted"
            }
        }
    }

    @Published private(set) var focusAuthorized = false

    private var focusCenter: INFocusStatusCenter { .default }
    /// INFocusStatusCenter needs an app bundle (like notifications).
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    init() { refreshAuthorization() }

    func refreshAuthorization() {
        guard available else { return }
        focusAuthorized = focusCenter.authorizationStatus == .authorized
    }

    /// Asks once; macOS remembers the answer (Settings › Privacy & Security › Focus).
    func requestFocusAccess(_ done: ((Bool) -> Void)? = nil) {
        guard available else { done?(false); return }
        focusCenter.requestAuthorization { status in
            DispatchQueue.main.async {
                self.focusAuthorized = status == .authorized
                done?(self.focusAuthorized)
            }
        }
    }

    /// Whether any Focus is on, or nil when Nida isn't allowed to know.
    var isFocused: Bool? {
        guard available, focusCenter.authorizationStatus == .authorized else { return nil }
        return focusCenter.focusStatus.isFocused
    }

    /// Why the adhan should stay quiet on this output right now, or nil to play it.
    func reason(outputUID: String?) -> Reason? {
        if isFocused == true { return .focus }
        let outputs = AudioOutputs.shared
        outputs.reload()
        if let target = outputs.device(uid: outputUID) ?? outputs.defaultDevice {
            if AudioOutputs.isMuted(target.deviceID) == true { return .muted }
            if let v = AudioOutputs.volume(of: target.deviceID), v < 0.01 { return .muted }
        }
        return nil
    }
}
