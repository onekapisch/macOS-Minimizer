import Carbon.HIToolbox

/// Minimal systemwide hotkey registration via the Carbon Hot Key API.
/// Works regardless of which app is focused, consumes the keystroke, and
/// needs no special permission. Single hotkey, re-registerable at runtime.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerInstalled = false
    private var handler: (() -> Void)?

    private init() {}

    /// Human-readable label for the currently registered combo.
    private(set) var displayString = ""

    /// False if the last `apply(...)` failed to register (combo taken by the system or
    /// another app), so the hotkey is silently dead and callers can warn.
    private(set) var isRegistered = false

    /// Install the one-time Carbon event handler and remember the callback.
    func start(handler: @escaping () -> Void) {
        self.handler = handler
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                HotKeyCenter.shared.handler?()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    /// (Re)register the active hotkey to the given combo.
    @discardableResult
    func apply(keyCode: UInt32, modifiers: UInt32, display: String) -> Bool {
        displayString = display
        unregister()
        let hotKeyID = EventHotKeyID(signature: 0x4D4E4D5A /* "MNMZ" */, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = (status == noErr && hotKeyRef != nil)
        return isRegistered
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
