import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut, stored as a virtual key code + Carbon modifier mask.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_M),
        carbonModifiers: UInt32(controlKey | optionKey),
        display: "⌃⌥M"
    )
}

/// Persists the chosen shortcut in UserDefaults.
enum ShortcutStore {
    private static let keyCodeKey = "hotkey.keyCode"
    private static let modsKey = "hotkey.carbonModifiers"
    private static let dispKey = "hotkey.display"

    static func load() -> Shortcut {
        let d = UserDefaults.standard
        guard d.object(forKey: keyCodeKey) != nil else { return .default }
        return Shortcut(
            keyCode: UInt32(d.integer(forKey: keyCodeKey)),
            carbonModifiers: UInt32(d.integer(forKey: modsKey)),
            display: d.string(forKey: dispKey) ?? Shortcut.default.display
        )
    }

    static func save(_ s: Shortcut) {
        let d = UserDefaults.standard
        d.set(Int(s.keyCode), forKey: keyCodeKey)
        d.set(Int(s.carbonModifiers), forKey: modsKey)
        d.set(s.display, forKey: dispKey)
    }
}

/// Converts AppKit key events into Carbon modifiers + a readable label.
enum ShortcutTranslator {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.control) { c |= UInt32(controlKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        return c
    }

    static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "↩",
        UInt16(kVK_ANSI_KeypadEnter): "⌅",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
    ]

    static func keyLabel(keyCode: UInt16, characters: String?) -> String {
        if let s = specialKeys[keyCode] { return s }
        if let c = characters, let scalar = c.unicodeScalars.first, scalar.value >= 32 {
            return c.uppercased()
        }
        return "Key \(keyCode)"
    }
}
