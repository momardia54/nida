import AudioToolbox
import CoreAudio
import Foundation

struct AudioOutput: Identifiable, Hashable {
    let id: String          // CoreAudio device UID: stable across reconnects
    let deviceID: AudioDeviceID
    let name: String
    let transport: UInt32
    let hasVolume: Bool

    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "headphones"
        case kAudioDeviceTransportTypeUSB: "cable.connector"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: "display"
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeBuiltIn:
            name.localizedCaseInsensitiveContains("headphone") ? "headphones" : "hifispeaker"
        default: "speaker.wave.2"
        }
    }
}

/// Lists output devices and controls their volume, keeping the list current as devices come and go.
final class AudioOutputs: ObservableObject {
    static let shared = AudioOutputs()

    @Published private(set) var devices: [AudioOutput] = []
    @Published private(set) var defaultUID: String?

    private init() {
        reload()
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { [weak self] _, _ in
                self?.reload()
            }
        }
    }

    func reload() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return }

        devices = ids.compactMap { id in
            guard Self.hasOutputStreams(id), let uid = Self.string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let transport = Self.uint32(id, kAudioDevicePropertyTransportType) ?? 0
            // Virtual/aggregate devices (meeting apps, loopback drivers) only add clutter.
            if transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate { return nil }
            return AudioOutput(id: uid, deviceID: id, name: Self.string(id, kAudioObjectPropertyName) ?? uid,
                               transport: transport, hasVolume: Self.volume(of: id) != nil)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if let def = Self.uint32(system, kAudioHardwarePropertyDefaultOutputDevice) {
            defaultUID = Self.string(AudioDeviceID(def), kAudioDevicePropertyDeviceUID)
        }
    }

    func device(uid: String?) -> AudioOutput? {
        guard let uid else { return nil }
        return devices.first { $0.id == uid }
    }

    var defaultDevice: AudioOutput? { device(uid: defaultUID) }

    // MARK: Volume

    static func volume(of id: AudioDeviceID) -> Float? {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    @discardableResult
    static func setVolume(_ value: Float, of id: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return false }
        var v = Float32(min(1, max(0, value)))
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    static func isMuted(_ id: AudioDeviceID) -> Bool? {
        var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr ? v != 0 : nil
    }

    @discardableResult
    static func setMuted(_ muted: Bool, _ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return false }
        var v: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = address(selector)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// Raises (and unmutes) a device for the adhan, then puts things back exactly as they were —
/// unless the user changed the volume themselves in the meantime.
final class VolumeBoost {
    private var deviceID: AudioDeviceID?
    private var originalVolume: Float?
    private var appliedVolume: Float?
    private var wasMuted = false

    func apply(to id: AudioDeviceID, atLeast level: Float) {
        restore()
        deviceID = id
        if AudioOutputs.isMuted(id) == true, AudioOutputs.setMuted(false, id) { wasMuted = true }
        if let current = AudioOutputs.volume(of: id), current < level, AudioOutputs.setVolume(level, of: id) {
            originalVolume = current
            appliedVolume = AudioOutputs.volume(of: id) ?? level
        }
    }

    func restore() {
        guard let id = deviceID else { return }
        if let original = originalVolume, let applied = appliedVolume,
           let now = AudioOutputs.volume(of: id), abs(now - applied) < 0.02 {
            AudioOutputs.setVolume(original, of: id)
        }
        if wasMuted { AudioOutputs.setMuted(true, id) }
        deviceID = nil
        originalVolume = nil
        appliedVolume = nil
        wasMuted = false
    }
}
