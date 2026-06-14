import AppKit
import Carbon.HIToolbox

/// A small control that records a keyboard shortcut: click it, then press the
/// desired combo (must include ⌃, ⌥, or ⌘). Esc cancels.
final class ShortcutRecorderView: NSView {

    var shortcut: Shortcut { didSet { needsDisplay = true } }
    var onChange: ((Shortcut) -> Void)?

    private var recording = false { didSet { needsDisplay = true } }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 28) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])

        // Esc with no modifiers cancels recording.
        if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }

        // A global hotkey needs a real modifier (shift alone isn't enough).
        guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else {
            NSSound.beep()
            return
        }

        let mods = ShortcutTranslator.carbonModifiers(from: flags)
        let label = ShortcutTranslator.keyLabel(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
        let display = ShortcutTranslator.modifierSymbols(from: flags) + label

        let newShortcut = Shortcut(keyCode: UInt32(event.keyCode), carbonModifiers: mods, display: display)
        shortcut = newShortcut
        recording = false
        window?.makeFirstResponder(nil)
        onChange?(newShortcut)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)

        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? "Type shortcut…" : shortcut.display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let p = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        (text as NSString).draw(at: p, withAttributes: attrs)
    }
}
