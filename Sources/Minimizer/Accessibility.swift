import AppKit
import ApplicationServices

/// Centralized Accessibility (AX) permission helpers.
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Returns whether we're trusted; pass prompt:true to show the system dialog.
    @discardableResult
    static func requestIfNeeded(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
