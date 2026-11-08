import AVFoundation
import Foundation

struct SoundInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let credit: String
    let duration: Double
    let phraseBreaks: [Double]
    let url: URL
    let builtIn: Bool
}

private struct SoundMeta: Codable {
    var title: String
    var credit: String
    var duration: Double
    var phraseBreaks: [Double]
}

final class SoundLibrary: ObservableObject {
    static let shared = SoundLibrary()
    static let chimeID = "chime"
    static let defaultID = "adhan-classic"
    private static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac"]

    @Published private(set) var sounds: [SoundInfo] = []

    /// Selectable adhan voices (everything except the chime).
    var voices: [SoundInfo] { sounds.filter { $0.id != Self.chimeID } }

    static var userDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nida/Sounds", isDirectory: true)
    }

    private init() { reload() }

    func reload() {
        var list: [SoundInfo] = []
        if let dir = ProcessInfo.processInfo.environment["NIDA_SOUNDS"].map({ URL(fileURLWithPath: $0) })
            ?? Bundle.main.resourceURL?.appendingPathComponent("Sounds") {
            list += scan(dir, builtIn: true)
        }
        list += scan(Self.userDirectory, builtIn: false)
        let order = ["adhan-classic": 0, "adhan-serene": 1]
        sounds = list.sorted {
            let a = order[$0.id] ?? ($0.builtIn ? 2 : 3), b = order[$1.id] ?? ($1.builtIn ? 2 : 3)
            return a != b ? a < b : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func scan(_ dir: URL, builtIn: Bool) -> [SoundInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in
            guard Self.audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let base = url.deletingPathExtension().lastPathComponent
            let metaURL = url.deletingPathExtension().appendingPathExtension("json")
            let meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(SoundMeta.self, from: $0) }
            let duration = meta?.duration ?? ((try? AVAudioPlayer(contentsOf: url))?.duration ?? 0)
            return SoundInfo(
                id: builtIn ? base : "user-\(base)",
                title: meta?.title ?? base,
                credit: meta?.credit ?? "Imported",
                duration: duration,
                phraseBreaks: meta?.phraseBreaks ?? [],
                url: url,
                builtIn: builtIn
            )
        }
    }

    func sound(_ id: String) -> SoundInfo? {
        sounds.first { $0.id == id } ?? sounds.first { $0.id == Self.defaultID } ?? voices.first
    }

    var chime: SoundInfo? { sounds.first { $0.id == Self.chimeID } }

    @discardableResult
    func importSound(from source: URL) throws -> SoundInfo? {
        let probe = try AVAudioPlayer(contentsOf: source) // throws if not playable
        let fm = FileManager.default
        try fm.createDirectory(at: Self.userDirectory, withIntermediateDirectories: true)
        let stem = UUID().uuidString.prefix(8).lowercased()
        let dest = Self.userDirectory.appendingPathComponent("\(stem).\(source.pathExtension.lowercased())")
        try fm.copyItem(at: source, to: dest)
        let meta = SoundMeta(
            title: source.deletingPathExtension().lastPathComponent,
            credit: "Imported",
            duration: probe.duration,
            phraseBreaks: []
        )
        try JSONEncoder().encode(meta).write(to: dest.deletingPathExtension().appendingPathExtension("json"))
        reload()
        return sounds.first { $0.id == "user-\(stem)" }
    }

    func delete(_ sound: SoundInfo) {
        guard !sound.builtIn else { return }
        try? FileManager.default.removeItem(at: sound.url)
        try? FileManager.default.removeItem(at: sound.url.deletingPathExtension().appendingPathExtension("json"))
        reload()
    }
}

final class AdhanPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AdhanPlayer()

    /// What is playing right now, e.g. "Asr adhan" or "Preview"; nil when silent.
    @Published private(set) var nowPlaying: String?

    private var player: AVAudioPlayer?
    private var fadeTimer: Timer?
    private var stopTimer: Timer?

    var isPlaying: Bool { nowPlaying != nil }

    /// Where the sound goes: a specific output (nil = system default), optionally raising its volume.
    struct Route {
        var outputUID: String?
        var raiseTo: Float?
        static let system = Route()
    }

    private let boost = VolumeBoost()
    /// The device actually used for the current sound (for the UI).
    @Published private(set) var playingOn: String?

    func play(_ sound: SoundInfo, length: AdhanLength, volume: Double, label: String, route: Route = .system) {
        stop(fade: false)
        guard let p = try? AVAudioPlayer(contentsOf: sound.url) else { return }
        let outputs = AudioOutputs.shared
        outputs.reload()
        // Fall back to the system default if the chosen device isn't connected right now.
        let target = outputs.device(uid: route.outputUID) ?? outputs.defaultDevice
        if let chosen = outputs.device(uid: route.outputUID) { p.currentDevice = chosen.id }
        if let level = route.raiseTo, let target { boost.apply(to: target.deviceID, atLeast: level) }
        p.delegate = self
        p.volume = Float(volume)
        p.prepareToPlay()
        p.play()
        player = p
        nowPlaying = label
        playingOn = target?.name

        if let end = Self.stopPoint(for: sound, length: length), end < p.duration - 0.5 {
            let fade = 1.6
            fadeTimer = Timer.scheduledTimer(withTimeInterval: max(0, end - fade), repeats: false) { [weak p] _ in
                p?.setVolume(0, fadeDuration: fade)
            }
            stopTimer = Timer.scheduledTimer(withTimeInterval: end, repeats: false) { [weak self, weak p] _ in
                guard let self, let p, self.player === p else { return }
                self.stop(fade: false)
            }
        }
    }

    /// Where to stop for a shortened adhan: at the end of a phrase, never mid-word.
    static func stopPoint(for sound: SoundInfo, length: AdhanLength) -> Double? {
        let breaks = sound.phraseBreaks
        switch length {
        case .full:
            return nil
        case .takbir:
            // The opening four takbīrs are usually the first two phrases.
            if breaks.count >= 2 { return breaks[1] }
            return breaks.first ?? min(20, sound.duration)
        default:
            guard let target = length.seconds else { return nil }
            if let b = breaks.first(where: { $0 >= target - 4 }), b - target <= 12 { return b }
            return target
        }
    }

    func setVolume(_ volume: Double) {
        player?.volume = Float(volume)
    }

    func stop(fade: Bool = true) {
        fadeTimer?.invalidate()
        stopTimer?.invalidate()
        fadeTimer = nil
        stopTimer = nil
        guard let p = player else { nowPlaying = nil; playingOn = nil; boost.restore(); return }
        if fade && p.isPlaying {
            p.setVolume(0, fadeDuration: 0.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [boost] in
                p.stop()
                if self.player == nil { boost.restore() }
            }
        } else {
            p.stop()
            boost.restore()
        }
        player = nil
        nowPlaying = nil
        playingOn = nil
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard self.player === p else { return }
            self.player = nil
            self.nowPlaying = nil
            self.playingOn = nil
            self.boost.restore()
        }
    }
}
