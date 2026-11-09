import Carbon.HIToolbox
import Foundation

/// One system-wide keyboard shortcut, registered through Carbon's hot key API.
/// Unlike a global event monitor this needs no Accessibility permission, and macOS only wakes
/// Nida when the exact combination is pressed.
final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func set(_ shortcut: MarkShortcut) {
        unregister()
        guard let (key, mods) = Self.combo(shortcut) else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4E494441), id: 1) // "NIDA"
        let status = RegisterEventHotKey(key, mods, id, GetEventDispatcherTarget(), 0, &ref)
        if status != noErr {
            ref = nil
            NSLog("Nida: couldn't register \(shortcut.label) (\(status)); another app may be using it.")
        }
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private static func combo(_ s: MarkShortcut) -> (UInt32, UInt32)? {
        let p = UInt32(kVK_ANSI_P)
        switch s {
        case .off: return nil
        case .ctrlOptP: return (p, UInt32(controlKey | optionKey))
        case .ctrlOptCmdP: return (p, UInt32(controlKey | optionKey | cmdKey))
        case .ctrlShiftP: return (p, UInt32(controlKey | shiftKey))
        case .optShiftP: return (p, UInt32(optionKey | shiftKey))
        }
    }
}
