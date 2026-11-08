import AppKit

// Diagnostic: `Nida --times <lat> <lon> <timeZoneID> <conventionID> [hanafi] [yyyy-mm-dd]`
// prints the windows for one day and exits. Used to verify calculations.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--times"), args.count >= i + 5,
   let lat = Double(args[i + 1]), let lon = Double(args[i + 2]) {
    var prefs = Preferences()
    prefs.conventionID = args[i + 4]
    prefs.madhabHanafi = args.dropFirst(i + 5).contains("hanafi")
    let loc = SavedLocation(name: "test", country: "", countryCode: nil, latitude: lat, longitude: lon, timeZoneID: args[i + 3])
    let engine = PrayerEngine(prefs: prefs, location: loc)
    var day = Date()
    if let ds = args.dropFirst(i + 5).first(where: { $0.contains("-") }) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = loc.timeZone
        day = f.date(from: ds).map { $0.addingTimeInterval(12 * 3600) } ?? day
    }
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = loc.timeZone
    if let t = engine.times(for: day) {
        print("fajr=\(f.string(from: t.fajr)) sunrise=\(f.string(from: t.sunrise)) dhuhr=\(f.string(from: t.dhuhr)) asr=\(f.string(from: t.asr)) maghrib=\(f.string(from: t.maghrib)) isha=\(f.string(from: t.isha)) midnight=\(f.string(from: t.midnight))")
    } else {
        print("no times")
    }
    exit(0)
}

#if DEBUG
if let i = args.firstIndex(of: "--import-test"), args.count > i + 1 {
    let lib = SoundLibrary.shared
    do {
        let s = try lib.importSound(from: URL(fileURLWithPath: args[i + 1]))
        print("imported: \(s?.title ?? "?") id=\(s?.id ?? "?") dir=\(SoundLibrary.userDirectory.path)")
        RunLoop.main.run(until: Date().addingTimeInterval(8))
        if let again = lib.voices.first(where: { $0.id == s?.id }) {
            print("after analysis: breaks=\(again.phraseBreaks.count) gain=\(String(format: "%.2f", again.gain)) 60s-stop=\(AdhanPlayer.stopPoint(for: again, length: .s60).map { String(format: "%.1f", $0) } ?? "-")")
            lib.rename(again, to: "My Test Voice")
            print("renamed: \(lib.voices.first(where: { $0.id == again.id })?.title ?? "?")")
        }
    } catch { print("import failed: \(error)") }
    exit(0)
}
if let i = args.firstIndex(of: "--analyze") {
    for path in args.dropFirst(i + 1) {
        if let r = AudioAnalysis.analyze(URL(fileURLWithPath: path)) {
            print(String(format: "%@  level %.1f dB  gain %.2f  breaks %d: %@", (path as NSString).lastPathComponent,
                         r.activeLevel, r.gain, r.phraseBreaks.count, r.phraseBreaks.prefix(6).map { String(format: "%.1f", $0) }.joined(separator: ", ")))
        }
    }
    exit(0)
}
// `Nida --route-test <deviceUID> <level>`: plays the chime on one output with the volume raised,
// printing the device volume before, during and after.
if let i = args.firstIndex(of: "--route-test"), args.count > i + 2, let level = Float(args[i + 2]) {
    let uid = args[i + 1]
    let outputs = AudioOutputs.shared
    for d in outputs.devices { print("output: \(d.name) uid=\(d.id) volume=\(AudioOutputs.volume(of: d.deviceID).map { String($0) } ?? "n/a")\(d.id == outputs.defaultUID ? " (default)" : "")") }
    guard let dev = outputs.device(uid: uid), let chime = SoundLibrary.shared.chime else { print("device or chime missing"); exit(1) }
    func vol() -> String { AudioOutputs.volume(of: dev.deviceID).map { String(format: "%.2f", $0) } ?? "n/a" }
    print("before: \(vol())")
    AdhanPlayer.shared.play(chime, length: .full, volume: 0.8, label: "test",
                            route: AdhanPlayer.Route(outputUID: uid, raiseTo: level))
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    print("during: \(vol())  playingOn=\(AdhanPlayer.shared.playingOn ?? "-")")
    RunLoop.main.run(until: Date().addingTimeInterval(6))
    print("after:  \(vol())  stillPlaying=\(AdhanPlayer.shared.isPlaying)")
    exit(0)
}
if let i = args.firstIndex(of: "--readme"), args.count > i + 1 {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    ReadmeShots.run(outDir: args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    Snapshot.run(outDir: args[i + 1])
    exit(0)
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
