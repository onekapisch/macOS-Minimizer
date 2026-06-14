import AppKit

/// The single Settings window: shortcut recorder, launch-at-login, accessibility.
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    private let recorder: ShortcutRecorderView
    private let launchCheckbox = NSButton(checkboxWithTitle: "Launch Minimizer at login", target: nil, action: nil)

    /// Called whenever the user picks a new shortcut.
    var onShortcutChange: ((Shortcut) -> Void)?

    init(shortcut: Shortcut) {
        recorder = ShortcutRecorderView(shortcut: shortcut)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Minimizer Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Bring the window to front, syncing controls to current state.
    func present(currentShortcut: Shortcut) {
        recorder.shortcut = currentShortcut
        launchCheckbox.state = LoginItem.isEnabled ? .on : .off
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // App title + version.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let title = makeLabel("Minimizer", font: .systemFont(ofSize: 17, weight: .semibold))
        let subtitle = makeLabel("Minimize all windows · v\(version)", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)

        // Shortcut row.
        let shortcutLabel = makeLabel("Global shortcut", font: .systemFont(ofSize: 13))
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.onChange = { [weak self] s in self?.onShortcutChange?(s) }
        let resetButton = NSButton(title: "Restore Default", target: self, action: #selector(restoreDefault))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        let shortcutRow = NSStackView(views: [shortcutLabel, recorder, resetButton])
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 10
        shortcutRow.alignment = .centerY

        // Launch at login.
        launchCheckbox.target = self
        launchCheckbox.action = #selector(toggleLaunch(_:))
        launchCheckbox.state = LoginItem.isEnabled ? .on : .off

        let behaviorLabel = makeWrappingLabel(
            "Minimizer prioritizes restoring focus to the window you were using. macOS controls the visible window animation timing.",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )

        // Accessibility row.
        let accessLabel = makeLabel("Needs Accessibility permission to move windows.",
                                    font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        let accessButton = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibility))
        accessButton.bezelStyle = .rounded
        accessButton.controlSize = .small

        let stack = NSStackView(views: [
            title,
            subtitle,
            separator(),
            shortcutRow,
            launchCheckbox,
            behaviorLabel,
            separator(),
            accessLabel,
            accessButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22),
            behaviorLabel.widthAnchor.constraint(equalToConstant: 352),
            recorder.widthAnchor.constraint(equalToConstant: 150),
            recorder.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    // MARK: - Actions

    @objc private func restoreDefault() {
        recorder.shortcut = .default
        onShortcutChange?(.default)
    }

    @objc private func toggleLaunch(_ sender: NSButton) {
        let enable = sender.state == .on
        if let error = LoginItem.setEnabled(enable) {
            sender.state = enable ? .off : .on   // revert the checkbox
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func openAccessibility() {
        Accessibility.openSettings()
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }

    private func makeWrappingLabel(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = makeLabel(text, font: font, color: color)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 352).isActive = true
        return box
    }
}
