import AppKit

/// Makes installing and updating one click: open the DMG, double-click Nida, choose Install.
enum Installer {
    static let destination = URL(fileURLWithPath: "/Applications/Nida.app")

    static var isRunningFromDiskImage: Bool { Bundle.main.bundlePath.hasPrefix("/Volumes/") }

    /// Other running copies of Nida (an older version, or one started from a disk image).
    static var otherInstances: [NSRunningApplication] {
        guard let id = Bundle.main.bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Returns true when this process is about to quit (installed copy is relaunching).
    static func handleLaunch() -> Bool {
        if isRunningFromDiskImage {
            return offerInstall()
        }
        // Only one Nida in the menu bar: the copy just launched (usually the newer one) wins.
        quitOtherInstances()
        return false
    }

    private static func version(at url: URL) -> String? {
        Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static func offerInstall() -> Bool {
        let mine = version(at: Bundle.main.bundleURL) ?? "?"
        let installed = FileManager.default.fileExists(atPath: destination.path) ? version(at: destination) : nil

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        if let installed {
            alert.messageText = installed == mine ? "Reinstall Nida \(mine)?" : "Update Nida \(installed) to \(mine)?"
            alert.informativeText = "This replaces the copy in your Applications folder. Your settings are kept."
            alert.addButton(withTitle: installed == mine ? "Reinstall" : "Update")
        } else {
            alert.messageText = "Install Nida in Applications?"
            alert.informativeText = "Nida is running from the disk image. Install it so it keeps running after you eject the disk and can open at login."
            alert.addButton(withTitle: "Install")
        }
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            quitOtherInstances()
            return false
        }

        quitOtherInstances()
        do {
            let fm = FileManager.default
            let staging = destination.deletingLastPathComponent().appendingPathComponent(".Nida-installing.app")
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: Bundle.main.bundleURL, to: staging)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: destination)
            }
        } catch {
            let fail = NSAlert()
            fail.alertStyle = .warning
            fail.messageText = "Couldn't install automatically"
            fail.informativeText = "\(error.localizedDescription)\n\nDrag Nida onto the Applications folder in the disk image window instead."
            fail.runModal()
            return false
        }

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }

    private static func quitOtherInstances() {
        let others = otherInstances
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(4)
        while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }
}
