import SwiftUI

/// "Play adhan on" + "Raise the volume" controls, shared by Settings and onboarding.
struct OutputSettingsView: View {
    @Binding var prefs: Preferences
    @ObservedObject var outputs: AudioOutputs
    @ObservedObject var player: AdhanPlayer
    let app: AppController

    private var chosen: AudioOutput? { outputs.device(uid: prefs.outputUID) }
    private var isDisconnected: Bool { prefs.outputUID != nil && chosen == nil }
    /// The device the adhan would play on right now.
    private var target: AudioOutput? { chosen ?? outputs.defaultDevice }

    var body: some View {
        Group {
            Picker("Play adhan on", selection: uidBinding) {
                Text("System default (\(outputs.defaultDevice?.name ?? "current output"))").tag("")
                Divider()
                ForEach(outputs.devices) { d in
                    Label(d.name, systemImage: d.symbol).tag(d.id)
                }
                if isDisconnected, let uid = prefs.outputUID {
                    Text("\(prefs.outputName.isEmpty ? "Saved device" : prefs.outputName) (not connected)").tag(uid)
                }
            }
            if isDisconnected {
                note("\(prefs.outputName) isn't connected. Until it's back, the adhan plays on the system default.",
                     icon: "exclamationmark.triangle.fill", color: .orange)
            } else if chosen != nil {
                note("The adhan always plays here, even while your other sound goes somewhere else.", icon: "checkmark.circle")
            }

            Toggle("Raise the volume for the adhan", isOn: $prefs.raiseVolume)
            if prefs.raiseVolume {
                if let target, !target.hasVolume {
                    note("\(target.name) doesn't let apps control its volume, so the adhan plays at its current level.",
                         icon: "exclamationmark.triangle.fill", color: .orange)
                } else {
                    HStack {
                        Text("To at least")
                        Slider(value: $prefs.raiseVolumeLevel, in: 0.2...1, step: 0.05)
                        Text("\(Int((prefs.raiseVolumeLevel * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    note(prefs.respectSilence
                         ? "Your volume is put back when the adhan ends, unless you changed it yourself meanwhile. A muted output stays muted (see Quiet times)."
                         : "Unmutes the output if needed. Your volume is put back when the adhan ends, unless you changed it yourself meanwhile.",
                         icon: "arrow.uturn.backward")
                }
            }

            HStack {
                Text(target.map { "Test on \($0.name)" } ?? "Test")
                Spacer()
                Button {
                    if player.nowPlaying == "Preview" { player.stop() } else {
                        app.preview(SoundLibrary.chimeID, length: .full, prefs: prefs)
                    }
                } label: {
                    Label(player.nowPlaying == "Preview" ? "Stop" : "Play chime",
                          systemImage: player.nowPlaying == "Preview" ? "stop.fill" : "play.fill")
                }
            }
        }
        .onAppear { outputs.reload() }
    }

    private var uidBinding: Binding<String> {
        Binding(
            get: { prefs.outputUID ?? "" },
            set: { uid in
                if uid.isEmpty {
                    prefs.outputUID = nil
                    prefs.outputName = ""
                } else {
                    prefs.outputUID = uid
                    prefs.outputName = outputs.device(uid: uid)?.name ?? prefs.outputName
                }
            })
    }

    private func note(_ text: String, icon: String, color: Color = .secondary) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
