import SwiftUI

struct OnboardingView: View {
    let app: AppController
    @ObservedObject var location: LocationService
    @ObservedObject var sounds: SoundLibrary
    @ObservedObject var player: AdhanPlayer
    @ObservedObject var notifier: Notifier

    private enum Step: Int, CaseIterable { case welcome, location, method, adhan, output, finish }

    @ViewState private var step: Step = .welcome

    init(app: AppController, location: LocationService, sounds: SoundLibrary, player: AdhanPlayer,
         notifier: Notifier, startStep: Int = 0) {
        self.app = app
        self.location = location
        self.sounds = sounds
        self.player = player
        self.notifier = notifier
        _step = ViewState(initialValue: Step(rawValue: startStep) ?? .welcome)

        // Re-running setup starts from the current settings.
        let prefs = Store.shared.prefs
        isRerun = prefs.onboarded
        if prefs.onboarded {
            let reference = prefs.alert(for: .dhuhr)
            _adhanFor = ViewState(initialValue: Set(PrayerKind.allCases.filter { prefs.alert(for: $0).style == .adhan }))
            _voice = ViewState(initialValue: reference.soundID)
            _length = ViewState(initialValue: reference.length)
            _launchAtLogin = ViewState(initialValue: app.launchAtLogin)
            initialVoice = reference.soundID
            initialLength = reference.length
        } else {
            initialVoice = SoundLibrary.defaultID
            initialLength = .full
        }
    }

    private let isRerun: Bool
    private let initialVoice: String
    private let initialLength: AdhanLength
    @ViewState private var draft = Store.shared.prefs
    @ViewState private var picked: SavedLocation? = Store.shared.prefs.location
    @ViewState private var pickedIsCurrent = Store.shared.prefs.followLocation
    @ViewState private var adhanFor: Set<PrayerKind> = Set(PrayerKind.allCases)
    @ViewState private var voice = SoundLibrary.defaultID
    @ViewState private var length: AdhanLength = .full
    @ViewState private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: welcome
                case .location: locationStep
                case .method: methodStep
                case .adhan: adhanStep
                case .output: outputStep
                case .finish: finishStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .transition(.opacity)

            footer
        }
        .frame(width: 520, height: 600)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.30, blue: 0.27).opacity(0.18), .clear],
                           startPoint: .top, endPoint: .center)
        )
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            Text("Nida").font(.system(size: 34, weight: .semibold, design: .rounded))
            Text("نداء").font(.system(size: 22)).foregroundStyle(.secondary)
            Text("Prayer times in your menu bar, with the adhan when it's time.\nEverything is calculated on your Mac — no account, works offline.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 10) {
                feature("location.fill", "Finds your location and the right calculation method")
                feature("paintpalette.fill", "Green when a prayer begins, red as its time runs out")
                feature("airplane", "Adapts automatically when you travel")
            }
            .padding(.top, 14)
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Color.accentColor)
            Text(text).font(.system(size: 13))
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Where are you?", "Your location sets the prayer times. It stays on your Mac.")
            LocationPicker(location: location) { loc, isCurrent in
                picked = loc
                pickedIsCurrent = isCurrent
                applyRecommendation(for: loc)
            }
            if let picked {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(picked.title).font(.system(size: 14, weight: .semibold))
                        Text(pickedIsCurrent ? "Your current location · followed when you travel" : "Chosen manually")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.1)))
            }
        }
    }

    private var methodStep: some View {
        let rec = Conventions.recommendation(for: picked?.countryCode)
        let recName = Conventions.convention(rec.conventionID).name
        return VStack(alignment: .leading, spacing: 14) {
            stepTitle("Calculation method", "Different regions calculate Fajr and Isha differently.")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text("Mosques in \(picked.map { $0.country.isEmpty ? $0.name : $0.country } ?? "your area") usually use **\(recName)**.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.1)))

            Picker("Convention", selection: $draft.conventionID) {
                ForEach(Conventions.all.filter { $0.id != "custom" }) { Text($0.name).tag($0.id) }
            }
            Text(Conventions.convention(draft.conventionID).detail)
                .font(.system(size: 11)).foregroundStyle(.secondary)

            Picker("Asr", selection: $draft.madhabHanafi) {
                Text("Standard").tag(false)
                Text("Ḥanafī").tag(true)
            }
            .pickerStyle(.segmented)
            Text("Standard: Shāfiʿī, Mālikī, Ḥanbalī. Ḥanafī places Asr later in the afternoon.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            if let loc = picked {
                let engine = PrayerEngine(prefs: draft, location: loc)
                HStack {
                    ForEach(engine.windows(for: Date())) { w in
                        VStack(spacing: 3) {
                            Text(w.kind.name).font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(engine.timeString(w.start)).font(.system(size: 13, weight: .medium).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                Text("Today's times with this method. You can fine-tune each prayer later in Settings.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var adhanStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("The adhan", "Choose a voice and when it plays. The others get a notification.")
            VStack(spacing: 4) {
                ForEach(sounds.voices) { s in
                    HStack(spacing: 10) {
                        Image(systemName: voice == s.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(voice == s.id ? Color.accentColor : .secondary)
                        Text(s.title).font(.system(size: 13, weight: .medium))
                        Text(String(format: "%d:%02d", Int(s.duration.rounded()) / 60, Int(s.duration.rounded()) % 60))
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            if player.playingSoundID == s.id { player.stop() } else {
                                voice = s.id
                                app.preview(s.id, length: length == .full ? .s30 : length, prefs: draft)
                            }
                        } label: {
                            Image(systemName: player.playingSoundID == s.id ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 19))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { voice = s.id }
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(voice == s.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
                }
            }
            Text("You can add more voices any time in Settings › Adhan.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            Text("Play the adhan for").font(.system(size: 12, weight: .medium)).padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(PrayerKind.allCases) { k in
                    let on = adhanFor.contains(k)
                    Button {
                        if on { adhanFor.remove(k) } else { adhanFor.insert(k) }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: k.symbol).symbolRenderingMode(.hierarchical)
                            Text(k.name).font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
                        .foregroundStyle(on ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("Length", selection: $length) {
                ForEach(AdhanLength.allCases) { Text($0.label).tag($0) }
            }
            Text("Shortened adhans stop at the end of a phrase and fade out gently.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var outputStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Where should the adhan play?",
                      "Pick a speaker so the adhan is heard even when your other sound goes to headphones.")
            Form {
                OutputSettingsView(prefs: $draft, outputs: .shared, player: player, app: app)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -20)
            .frame(maxHeight: 330)
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("Almost done", "A couple of permissions so Nida can do its job.")
            HStack {
                Image(systemName: "bell.badge.fill").frame(width: 24).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications").font(.system(size: 13, weight: .medium))
                    Text("Banners at prayer time, with a Stop button").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if notifier.authorized {
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Allow") { notifier.requestAuthorization() }
                }
            }
            Toggle(isOn: $launchAtLogin) {
                HStack {
                    Image(systemName: "power").frame(width: 24).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at login").font(.system(size: 13, weight: .medium))
                        Text("So you never miss a prayer after a restart").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            if pickedIsCurrent {
                HStack {
                    Image(systemName: "airplane").frame(width: 24).foregroundStyle(Color.accentColor)
                    Text("When I travel").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $draft.moveBehavior) {
                        ForEach(MoveBehavior.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
        }
        .onAppear { notifier.refreshStatus() }
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if step != .welcome {
                Button("Back") { player.stop(); step = Step(rawValue: step.rawValue - 1)! }
            }
            Button(step == .finish ? (isRerun ? "Save" : "Start Nida") : (step == .welcome ? (isRerun ? "Start" : "Get started") : "Continue")) {
                player.stop()
                if step == .finish { finish() } else { step = Step(rawValue: step.rawValue + 1)! }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(step == .location && picked == nil)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    // MARK: Logic

    private func applyRecommendation(for loc: SavedLocation) {
        let rec = Conventions.recommendation(for: loc.countryCode)
        draft.conventionID = rec.conventionID
        draft.madhabHanafi = rec.hanafi
    }

    private func finish() {
        guard let loc = picked else { return }
        let rec = Conventions.recommendation(for: loc.countryCode)
        var p = draft
        p.location = loc
        p.followLocation = pickedIsCurrent
        p.conventionAuto = p.conventionID == rec.conventionID
        p.madhabAuto = p.madhabHanafi == rec.hanafi
        for k in PrayerKind.allCases {
            var a = p.alert(for: k)
            if adhanFor.contains(k) {
                a.style = .adhan
            } else if a.style == .adhan {
                a.style = .banner
            } // a chime, notification-only or off choice made in Settings is kept
            // On a re-run, only overwrite per-prayer voice/length if they were changed here.
            if !isRerun || voice != initialVoice { a.soundID = voice }
            if !isRerun || length != initialLength { a.length = length }
            p.setAlert(a, for: k)
        }
        if launchAtLogin != app.launchAtLogin { app.launchAtLogin = launchAtLogin }
        if !notifier.authorized { notifier.requestAuthorization() }
        app.finishOnboarding(with: p)
    }
}
