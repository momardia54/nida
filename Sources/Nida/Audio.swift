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
    /// Playback gain (≤ 1) that levels loud imported files with the built-in voices.
    var gain: Double = 1
}

private struct SoundMeta: Codable {
    var title: String
    var credit: String
    var duration: Double
    var phraseBreaks: [Double]
    var gain: Double?
}

/// Finds phrase boundaries and a leveling gain for any recording, so imported adhans
/// stop cleanly when shortened and don't play louder than the built-in voices.
enum AudioAnalysis {
    /// Average level of the voiced parts of the built-in, mastered voices (dBFS).
    static let referenceLevel = -19.5

    struct Result {
        var phraseBreaks: [Double]
        var gain: Double
        var activeLevel: Double
    }

    static func analyze(_ url: URL) -> Result? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        let hop = 0.05
        let frameLen = AVAudioFrameCount(format.sampleRate * hop)
        guard channels > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLen) else { return nil }

        var levels: [Double] = []
        while file.framePosition < file.length {
            do { try file.read(into: buffer, frameCount: frameLen) } catch { break }
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            var sum: Float = 0
            for c in 0..<channels {
                let ch = data[c]
                for i in 0..<n { sum += ch[i] * ch[i] }
            }
            let rms = sqrt(Double(sum) / Double(n * channels))
            levels.append(20 * log10(max(rms, 1e-7)))
        }
        guard levels.count > 20 else { return nil }

        let duration = Double(levels.count) * hop
        let loud = levels.sorted()[Int(Double(levels.count) * 0.9)]
        let threshold = loud - 22
        var breaks: [Double] = []
        var silenceStart: Int?
        for (i, level) in levels.enumerated() {
            if level < threshold {
                if silenceStart == nil { silenceStart = i }
            } else if let start = silenceStart {
                if Double(i - start) * hop >= 0.4 {
                    let mid = Double(start + i) / 2 * hop
                    if mid > 3 && mid < duration - 3 { breaks.append((mid * 100).rounded() / 100) }
                }
                silenceStart = nil
            }
        }
        let active = levels.filter { $0 >= threshold }
        let power = active.map { pow(10, $0 / 10) }.reduce(0, +) / Double(max(1, active.count))
        let activeLevel = 10 * log10(max(power, 1e-12))
        let gain = min(1, pow(10, (referenceLevel - activeLevel) / 20))
        return Result(phraseBreaks: breaks, gain: gain, activeLevel: activeLevel)
    }
}

final class SoundLibrary: ObservableObject {
    static let shared = SoundLibrary()
    static let chimeID = "chime"
    static let defaultID = "adhan-classic"
    private static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac", "ogg", "oga", "opus", "flac"]

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
        let order = ["adhan-classic": 0, "adhan-serene": 1, "adhan-madinah": 2, "adhan-azeez": 3, "adhan-westafrica": 4]
        sounds = list.sorted {
            let a = order[$0.id] ?? ($0.builtIn ? 50 : 100), b = order[$1.id] ?? ($1.builtIn ? 50 : 100)
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
                builtIn: builtIn,
                gain: meta?.gain ?? 1
            )
        }
    }

    func sound(_ id: String) -> SoundInfo? {
        sounds.first { $0.id == id } ?? sounds.first { $0.id == Self.defaultID } ?? voices.first
    }

    var chime: SoundInfo? { sounds.first { $0.id == Self.chimeID } }

    /// Copies a recording into Nida's library, then analyzes it in the background
    /// (phrase breaks + leveling). Throws if the file isn't playable audio.
    @discardableResult
    func importSound(from source: URL) throws -> SoundInfo? {
        let probe = try AVAudioPlayer(contentsOf: source) // throws if not playable
        let fm = FileManager.default
        try fm.createDirectory(at: Self.userDirectory, withIntermediateDirectories: true)
        let stem = UUID().uuidString.prefix(8).lowercased()
        let dest = Self.userDirectory.appendingPathComponent("\(stem).\(source.pathExtension.lowercased())")
        try fm.copyItem(at: source, to: dest)
        let metaURL = dest.deletingPathExtension().appendingPathExtension("json")
        var meta = SoundMeta(
            title: Self.niceTitle(from: source),
            credit: "Imported",
            duration: probe.duration,
            phraseBreaks: [],
            gain: nil
        )
        try JSONEncoder().encode(meta).write(to: metaURL)
        reload()
        DispatchQueue.global(qos: .userInitiated).async {
            guard let result = AudioAnalysis.analyze(dest) else { return }
            meta.phraseBreaks = result.phraseBreaks
            meta.gain = result.gain
            try? JSONEncoder().encode(meta).write(to: metaURL)
            DispatchQueue.main.async { self.reload() }
        }
        return sounds.first { $0.id == "user-\(stem)" }
    }

    /// "adhan_mishary-alafasy (1).mp3" → "Adhan Mishary Alafasy"
    private static func niceTitle(from url: URL) -> String {
        var t = url.deletingPathExtension().lastPathComponent
        t = t.replacingOccurrences(of: "[_\\-]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s*\\(\\d+\\)$", with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Imported adhan" : t.prefix(1).uppercased() + t.dropFirst()
    }

    func rename(_ sound: SoundInfo, to title: String) {
        guard !sound.builtIn else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let metaURL = sound.url.deletingPathExtension().appendingPathExtension("json")
        var meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(SoundMeta.self, from: $0) }
            ?? SoundMeta(title: trimmed, credit: "Imported", duration: sound.duration, phraseBreaks: sound.phraseBreaks, gain: nil)
        meta.title = trimmed
        try? JSONEncoder().encode(meta).write(to: metaURL)
        reload()
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
    /// ID of the sound currently playing.
    @Published private(set) var playingSoundID: String?

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
        p.volume = Float(volume * sound.gain)
        p.prepareToPlay()
        p.play()
        player = p
        nowPlaying = label
        playingOn = target?.name
        playingSoundID = sound.id

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
        guard let p = player else { nowPlaying = nil; playingOn = nil; playingSoundID = nil; boost.restore(); return }
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
        playingSoundID = nil
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard self.player === p else { return }
            self.player = nil
            self.nowPlaying = nil
            self.playingOn = nil
            self.playingSoundID = nil
            self.boost.restore()
        }
    }
}
