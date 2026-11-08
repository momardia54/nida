import AppKit

/// Builds the menu bar item's content.
///
/// macOS draws status item text and template images in monochrome, so colors set on them don't
/// reliably show. The current prayer is therefore drawn as a non-template image (a colored pill),
/// which the menu bar displays in full color. The rest is ordinary text that follows the menu bar's
/// own light/dark styling.
enum StatusRenderer {
    struct Content {
        var image: NSImage?
        var title: String
        var key: String          // changes only when the rendering changes
        var ticksEverySecond = false
    }

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private static let pillFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    static func make(engine: PrayerEngine?, phase: PrayerPhase?, now: Date, prefs: Preferences,
                     isPlaying: Bool, darkMenuBar: Bool) -> Content {
        guard let engine, let phase else {
            let text = prefs.location == nil ? (prefs.onboarded ? "Set location" : "Nida") : "Nida"
            return Content(image: symbol("moon.stars.fill"), title: " \(text)", key: "none|\(text)")
        }
        let w = phase.window
        let name = w.kind.displayName(on: w.start, calendar: engine.calendar)
        let next = engine.windows(around: now).first { $0.start > now && $0 != w }
        let nextName = next.map { $0.kind.displayName(on: $0.start, calendar: engine.calendar) }

        switch phase {
        case .open:
            let left = Format.duration(w.remaining(at: now))
            let color = Urgency.nsColor(for: w, at: now)
            let hueKey = String(format: "%.2f", color.hueComponent)
            let nextRemaining = next.map { $0.start.timeIntervalSince(now) } ?? .infinity
            let nextSeconds = prefs.menuStyle == .time && prefs.menuBarShowsSeconds(remaining: nextRemaining)
            let nextText = next.map { " \(nextName!) in \(Format.countdown($0.start.timeIntervalSince(now), showSeconds: nextSeconds))" } ?? ""

            if !prefs.colorize {
                let text: String
                switch prefs.menuStyle {
                case .time: text = " \(name) · \(left) left ·\(nextText)"
                case .countdown: text = " \(name) · \(left) left"
                case .icon: text = ""
                }
                let img = symbol(isPlaying ? "speaker.wave.2.fill" : w.kind.symbol)
                return Content(image: img, title: text, key: "plain|\(text)|\(isPlaying)", ticksEverySecond: nextSeconds)
            }

            let pillText: String
            switch prefs.menuStyle {
            case .time: pillText = "\(name) · \(left) left"
            case .countdown: pillText = "\(name) \(left)"
            case .icon: pillText = ""
            }
            let image = pill(text: pillText, color: color, playing: isPlaying)
            let title = prefs.menuStyle == .time ? nextText : ""
            return Content(image: image, title: title,
                           key: "pill|\(pillText)|\(hueKey)|\(title)|\(isPlaying)|\(darkMenuBar)",
                           ticksEverySecond: nextSeconds)

        case .waiting:
            let remaining = w.start.timeIntervalSince(now)
            let seconds = prefs.menuStyle != .icon && prefs.menuBarShowsSeconds(remaining: remaining)
            let until = Format.countdown(remaining, showSeconds: seconds)
            let text: String
            switch prefs.menuStyle {
            case .time: text = " \(name) in \(until)"
            case .countdown: text = " \(name) in \(until)"
            case .icon: text = ""
            }
            let img = symbol(isPlaying ? "speaker.wave.2.fill" : w.kind.symbol)
            return Content(image: img, title: text, key: "wait|\(text)|\(isPlaying)", ticksEverySecond: seconds)
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Nida")?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// A rounded pill filled with the urgency color; text picks black or white for contrast.
    static func pill(text: String, color: NSColor, playing: Bool) -> NSImage {
        let fill = color.usingColorSpace(.sRGB) ?? color
        let luminance = 0.2126 * fill.redComponent + 0.7152 * fill.greenComponent + 0.0722 * fill.blueComponent
        let ink: NSColor = luminance > 0.55 ? NSColor(white: 0.08, alpha: 0.9) : .white

        let attrs: [NSAttributedString.Key: Any] = [.font: pillFont, .foregroundColor: ink]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = text.isEmpty ? .zero : str.size()
        let iconSize: CGFloat = playing ? 12 : 0
        let height: CGFloat = 18
        let hPad: CGFloat = text.isEmpty && !playing ? 0 : 8
        let gap: CGFloat = playing && !text.isEmpty ? 4 : 0
        let width = text.isEmpty && !playing ? height : ceil(textSize.width + iconSize + gap + hPad * 2)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            var x = hPad
            if playing,
               let sym = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) {
                let tinted = NSImage(size: sym.size, flipped: false) { r in
                    sym.draw(in: r)
                    ink.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: x, y: (height - sym.size.height) / 2, width: sym.size.width, height: sym.size.height))
                x += iconSize + gap
            }
            if !text.isEmpty {
                str.draw(at: NSPoint(x: x, y: (height - textSize.height) / 2 + 0.5))
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
