import Cocoa
import ApplicationServices
import QuartzCore
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var prefsController: PreferencesWindowController?
    private var onboardingController: OnboardingWindowController?

    /// UI-facing toggle state (true = windows are minimized). Read/written on the main
    /// thread only — it drives the icon and menu labels. The authoritative engine state
    /// lives in `minimizedState` (axQueue only).
    private var isMinimized = false

    /// Held for the app's lifetime to keep macOS App Nap from throttling us when idle.
    private var appNapToken: NSObjectProtocol?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Respond instantly to the minimize/restore hotkey"
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "MinimizerStatusItem"
        if let button = statusItem.button {
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()
        _ = Accessibility.requestIfNeeded(prompt: false)

        HotKeyCenter.shared.start { [weak self] in
            DispatchQueue.main.async { self?.toggle() }
        }
        applyShortcut(ShortcutStore.load())

        showOnboardingIfFirstLaunch()
    }

    // MARK: - Onboarding

    private static let onboardingKey = "didCompleteOnboarding"

    private func showOnboardingIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingKey) else { return }
        let controller = OnboardingWindowController()
        controller.onFinish = {
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        }
        onboardingController = controller
        controller.present()
    }

    // MARK: - Shortcut & Preferences

    private func applyShortcut(_ shortcut: Shortcut) {
        HotKeyCenter.shared.apply(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, display: shortcut.display)
        ShortcutStore.save(shortcut)
    }

    @objc private func openPreferences() {
        if prefsController == nil {
            let controller = PreferencesWindowController(shortcut: ShortcutStore.load())
            controller.onShortcutChange = { [weak self] shortcut in self?.applyShortcut(shortcut) }
            prefsController = controller
        }
        prefsController?.present(currentShortcut: ShortcutStore.load())
    }

    // MARK: - Status item UI

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = isMinimized ? "rectangle.stack.fill" : "rectangle.stack"
        let description = isMinimized ? "Restore all windows" : "Minimize all windows"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.toolTip = description
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Minimizer", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: isMinimized ? "Restore Windows" : "Minimize All Windows",
            action: #selector(menuToggle),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let hotkeyHint = NSMenuItem(title: "Hotkey: \(HotKeyCenter.shared.displayString)", action: nil, keyEquivalent: "")
        hotkeyHint.isEnabled = false
        menu.addItem(hotkeyHint)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Minimizer", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggle() { toggle() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Launch at Login

    @objc private func toggleLaunchAtLogin() {
        if let error = LoginItem.setEnabled(!LoginItem.isEnabled) {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - Engine state (axQueue only)

    /// One window captured at minimize time, restored on the next toggle.
    private struct CapturedWindow {
        let pid: pid_t
        let element: AXUIElement
        let wasFocused: Bool   // the originally-active window — restored & focused last
    }

    /// Serializes every minimize/restore cycle so AX/CG work never overlaps.
    private let axQueue = DispatchQueue(label: "com.equinox.Minimizer.axQueue")
    /// Authoritative engine state (axQueue only): true = a minimize is in effect.
    private var minimizedState = false
    /// Windows this toggle minimized, so restore un-minimizes exactly those.
    private var capturedWindows: [CapturedWindow] = []
    /// Native-fullscreen windows: recorded for completeness, never minimized.
    private var fullscreenWindows: [CapturedWindow] = []
    /// The app + window that was frontmost when we minimized, so restore returns focus.
    private var frontmostPID: pid_t = 0
    private var focusedWindowElement: AXUIElement?

    /// Re-entrancy guard: drops hotkey/clicks that arrive while a cycle is running, so a
    /// rapid double-press can't overwrite the capture and orphan windows.
    private var busy = false
    private let busyLock = NSLock()

    private let myPID = ProcessInfo.processInfo.processIdentifier

    // Tuning.
    private let axTimeout: Float = 0.5
    private let axTimeoutLong: Float = 2.0
    private let minimizeSettle: TimeInterval = 0.12
    private let minimizeMaxIterations = 10
    private let restoreSettle: TimeInterval = 0.08
    private let restoreMaxIterations = 18

    // MARK: - Toggle entry point (main thread)

    private func toggle() {
        guard Accessibility.isTrusted else {
            presentPermissionAlert()
            return
        }
        busyLock.lock()
        if busy { busyLock.unlock(); return }   // drop presses while a cycle runs
        busy = true
        busyLock.unlock()

        axQueue.async { [weak self] in
            guard let self else { return }
            self.runCycle()
            self.busyLock.lock(); self.busy = false; self.busyLock.unlock()
        }
    }

    /// Runs entirely on `axQueue`. Decides minimize vs. restore from the authoritative
    /// engine state, never the (async) UI state.
    private func runCycle() {
        if minimizedState {
            performRestore()
            minimizedState = false
        } else {
            if performMinimize() { minimizedState = true }
        }
    }

    // MARK: - Minimize

    /// Returns true if at least one window was minimized (so the toggle flips state).
    private func performMinimize() -> Bool {
        captureFrontmostAndFocus()

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.processIdentifier != myPID
                && !$0.isTerminated
        }

        // Ground truth: what the user actually sees right now. Also lets us detect apps
        // whose AX query fails/times out but that clearly own on-screen windows.
        let cgByPID = onScreenLayer0ByPID()

        var captured: [CapturedWindow] = []
        var fullscreen: [CapturedWindow] = []

        for app in apps {
            let pid = app.processIdentifier
            // For apps the user can see on screen, retry the AX query — some apps
            // (notably Microsoft Office) intermittently return an empty windows array,
            // which would otherwise leave that window behind.
            let windows = (cgByPID[pid] ?? 0) > 0
                ? windowsWithRetry(of: pid)
                : copyWindows(of: pid, timeout: axTimeout)
            for window in windows where isStandardWindow(window) {
                let focused = focusedWindowElement.map { CFEqual($0, window) } ?? false
                if isFullscreen(window) {
                    fullscreen.append(CapturedWindow(pid: pid, element: window, wasFocused: focused))
                } else if !isMinimizedWindow(window) {
                    // Skip windows the user already minimized — restore them exactly as-is.
                    captured.append(CapturedWindow(pid: pid, element: window, wasFocused: focused))
                }
            }
        }

        // Nothing we can minimize → keep the toggle honest (don't flip the icon).
        guard !captured.isEmpty else { return false }

        capturedWindows = captured
        fullscreenWindows = fullscreen
        flipUI(minimized: true)

        // Fire every minimize at once (apps are independent), then converge against
        // ground truth until nothing normal is left on screen.
        setMinimizedBurst(captured.map { $0.element }, true)
        convergeMinimize()
        return true
    }

    /// The completeness guarantee: re-query the on-screen window list and re-issue
    /// minimize to any app still showing a normal window — including windows that
    /// appeared mid-cycle — until the screen is clean or the budget is spent.
    private func convergeMinimize() {
        var lastCount = Int.max
        var noProgress = 0
        for _ in 0..<minimizeMaxIterations {
            Thread.sleep(forTimeInterval: minimizeSettle)
            let cgByPID = onScreenLayer0ByPID()
            let count = cgByPID.values.reduce(0, +)
            if count == 0 { return }   // fully clean — done

            let runningPIDs = Set(NSWorkspace.shared.runningApplications.map { $0.processIdentifier })
            for pid in cgByPID.keys where runningPIDs.contains(pid) {
                var toMinimize: [AXUIElement] = []
                for window in windowsWithRetry(of: pid) where isStandardWindow(window) {
                    if isFullscreen(window) || isMinimizedWindow(window) { continue }
                    toMinimize.append(window)
                    if !capturedWindows.contains(where: { CFEqual($0.element, window) }) {
                        let focused = focusedWindowElement.map { CFEqual($0, window) } ?? false
                        capturedWindows.append(CapturedWindow(pid: pid, element: window, wasFocused: focused))
                    }
                }
                setMinimizedBurst(toMinimize, true)
            }

            // Stop only when the on-screen count stops dropping for several iterations —
            // i.e. the remainder is genuinely unminimizable (non-standard panels, an app
            // with no AX). A flaky app that we successfully command resets this counter.
            if count >= lastCount { noProgress += 1 } else { noProgress = 0 }
            lastCount = count
            if noProgress >= 3 { return }
        }
    }

    /// Reads an app's AX windows, retrying because some apps (notably Microsoft Office)
    /// intermittently return an empty windows array even while clearly on screen.
    private func windowsWithRetry(of pid: pid_t, retries: Int = 3) -> [AXUIElement] {
        for attempt in 0...retries {
            let windows = copyWindows(of: pid, timeout: attempt == 0 ? axTimeout : axTimeoutLong)
            if !windows.isEmpty { return windows }
            if attempt < retries { Thread.sleep(forTimeInterval: 0.04) }
        }
        return []
    }

    // MARK: - Restore

    private func performRestore() {
        let captured = capturedWindows
        let focusedEl = focusedWindowElement
        let frontPID = frontmostPID

        flipUI(minimized: false)

        let runningPIDs = Set(NSWorkspace.shared.runningApplications.map { $0.processIdentifier })

        // Phase 1: un-minimize the background windows first (everything but the target).
        let background = captured.filter { w in
            runningPIDs.contains(w.pid)
                && !(focusedEl.map { CFEqual($0, w.element) } ?? false)
        }
        setMinimizedBurst(background.map { $0.element }, false)

        // Phase 2: settle via truth — wait until the background windows actually report
        // un-minimized and the on-screen count is stable, so nothing pops up after we
        // set focus (kills the focus bounce).
        settleRestore(background.map { $0.element })

        // Phase 3: bring the originally-active window up last, exactly once.
        if let focusedEl, runningPIDs.contains(frontPID) {
            AXUIElementSetMessagingTimeout(focusedEl, axTimeout)
            AXUIElementSetAttributeValue(focusedEl, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        focusTarget(pid: frontPID, window: focusedEl)

        capturedWindows = []
        fullscreenWindows = []
        focusedWindowElement = nil
        frontmostPID = 0
    }

    /// Poll until the background windows report un-minimized AND the on-screen window
    /// count is stable across two consecutive polls (bounded).
    private func settleRestore(_ background: [AXUIElement]) {
        var lastCG = -1
        var stable = 0
        for _ in 0..<restoreMaxIterations {
            Thread.sleep(forTimeInterval: restoreSettle)
            let allUp = background.allSatisfy { !isMinimizedWindow($0) }
            let cg = onScreenLayer0Count()
            if cg == lastCG { stable += 1 } else { stable = 0; lastCG = cg }
            if allUp && stable >= 1 { return }
        }
    }

    /// Focus the originally-active app + window once, via AX (reliable from a background
    /// agent where `activate()` alone can be ignored by focus-stealing prevention).
    private func focusTarget(pid: pid_t, window: AXUIElement?) {
        guard pid != 0 else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, axTimeout)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let window {
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        DispatchQueue.main.async {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    // MARK: - Capture helpers

    private func captureFrontmostAndFocus() {
        frontmostPID = 0
        focusedWindowElement = nil

        var target: NSRunningApplication?
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != myPID {
            target = front
        } else {
            // Our own Settings/Onboarding window is frontmost — fall back to the most
            // recently active regular app that isn't us.
            let regulars = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular && $0.processIdentifier != myPID && !$0.isTerminated
            }
            target = regulars.first { $0.isActive } ?? regulars.first { !$0.isHidden }
        }
        guard let app = target else { return }

        frontmostPID = app.processIdentifier
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, axTimeout)
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let element = value, CFGetTypeID(element) == AXUIElementGetTypeID() {
            focusedWindowElement = unsafeDowncast(element, to: AXUIElement.self)
        }
    }

    // MARK: - AX / CG primitives

    private func copyWindows(of pid: pid_t, timeout: Float) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, timeout)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    private func isStandardWindow(_ window: AXUIElement) -> Bool {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value) == .success,
              let subrole = value as? String else { return false }
        return subrole == (kAXStandardWindowSubrole as String)
    }

    private func isMinimizedWindow(_ window: AXUIElement) -> Bool {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
            && (value as? Bool) == true
    }

    /// `kAXFullScreenAttribute` isn't exported as a Swift symbol — use the literal.
    private func isFullscreen(_ window: AXUIElement) -> Bool {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success
            && (value as? Bool) == true
    }

    /// Fire `kAXMinimized = value` on every element at once. Each app is independent, so
    /// a concurrent burst is the snappiest path; the cycle stays serialized on axQueue.
    private func setMinimizedBurst(_ elements: [AXUIElement], _ minimized: Bool) {
        guard !elements.isEmpty else { return }
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        DispatchQueue.concurrentPerform(iterations: elements.count) { index in
            let window = elements[index]
            AXUIElementSetMessagingTimeout(window, axTimeout)
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
        }
    }

    /// Permission-independent ground truth: on-screen, layer-0 (normal) windows grouped
    /// by owning pid, excluding ourselves.
    private func onScreenLayer0ByPID() -> [pid_t: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var result: [pid_t: Int] = [:]
        for info in infos {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pidInt = info[kCGWindowOwnerPID as String] as? Int else { continue }
            let pid = pid_t(pidInt)
            if pid == myPID { continue }
            result[pid, default: 0] += 1
        }
        return result
    }

    private func onScreenLayer0Count() -> Int {
        onScreenLayer0ByPID().values.reduce(0, +)
    }

    // MARK: - UI sync

    private func flipUI(minimized: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMinimized = minimized
            self.updateIcon()
            self.animateIcon(restoring: !minimized)
        }
    }

    // MARK: - Icon animation

    private func animateIcon(restoring: Bool) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        let center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        func transform(_ scale: CGFloat) -> NSValue {
            var t = CATransform3DIdentity
            t = CATransform3DTranslate(t, center.x, center.y, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            t = CATransform3DTranslate(t, -center.x, -center.y, 0)
            return NSValue(caTransform3D: t)
        }

        let anim = CAKeyframeAnimation(keyPath: "transform")
        if restoring {
            anim.values = [transform(1.0), transform(1.14), transform(1.0)]
        } else {
            anim.values = [transform(1.0), transform(0.8), transform(1.0)]
        }
        anim.keyTimes = [0, 0.45, 1]
        anim.duration = 0.18
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "iconPulse")
    }

    // MARK: - Accessibility prompt

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility access needed"
        alert.informativeText = """
        Minimizer needs Accessibility permission to minimize and restore your windows.

        Open System Settings → Privacy & Security → Accessibility, then enable Minimizer.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Accessibility.openSettings()
        }
    }
}
