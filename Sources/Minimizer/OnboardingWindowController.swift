import AppKit

/// First-run welcome window: explains what Minimizer does and walks the user
/// through granting Accessibility permission. Premium, centered, native layout.
final class OnboardingWindowController: NSWindowController {

    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var pollTimer: Timer?
    var onFinish: (() -> Void)?

    private let contentWidth: CGFloat = 460

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func present() {
        refreshStatus()
        startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // App icon with a soft shadow.
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.shadow = softShadow()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let title = label("Welcome to Minimizer", .systemFont(ofSize: 26, weight: .bold), .labelColor)
        title.alignment = .center

        let tagline = wrappingLabel(
            "One click hides every open window. Click again and they all come back, exactly as they were.",
            .systemFont(ofSize: 13.5), .secondaryLabelColor)
        tagline.alignment = .center

        let hotkey = ShortcutStore.load().display
        let features = NSStackView(views: [
            featureRow("menubar.rectangle", "Click the menu-bar icon, or press \(hotkey)"),
            featureRow("arrow.down.right.and.arrow.up.left", "Minimizes everything · click again to restore"),
            featureRow("macwindow.on.rectangle", "Returns focus to your active window; macOS controls the animation"),
            featureRow("lock.shield", "Stays on your Mac — nothing is collected or sent"),
        ])
        features.orientation = .vertical
        features.alignment = .leading
        features.spacing = 12

        // Accessibility card.
        let card = makeAccessibilityCard()

        // Primary action.
        let getStarted = NSButton(title: "Get Started", target: self, action: #selector(finish))
        getStarted.bezelStyle = .rounded
        getStarted.controlSize = .large
        getStarted.keyEquivalent = "\r"   // default (accent) button
        getStarted.translatesAutoresizingMaskIntoConstraints = false
        getStarted.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        let root = NSStackView(views: [icon, title, tagline, features, card, getStarted])
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 22
        root.setCustomSpacing(14, after: icon)
        root.setCustomSpacing(10, after: title)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
            root.widthAnchor.constraint(equalToConstant: contentWidth),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -28),
            features.widthAnchor.constraint(equalTo: root.widthAnchor),
            card.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func makeAccessibilityCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor

        let title = label("Enable Accessibility", .systemFont(ofSize: 14, weight: .semibold), .labelColor)
        let body = wrappingLabel(
            "macOS requires Accessibility access for Minimizer to move your windows. That's the only permission it ever needs.",
            .systemFont(ofSize: 12), .secondaryLabelColor)

        let enableButton = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(grant))
        enableButton.bezelStyle = .rounded
        enableButton.controlSize = .regular

        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let statusRow = NSStackView(views: [statusIcon, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .centerY

        let inner = NSStackView(views: [title, body, enableButton, statusRow])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)

        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            body.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])
        return card
    }

    private func featureRow(_ symbol: String, _ text: String) -> NSView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.contentTintColor = .controlAccentColor
        image.translatesAutoresizingMaskIntoConstraints = false
        image.widthAnchor.constraint(equalToConstant: 22).isActive = true
        image.heightAnchor.constraint(equalToConstant: 20).isActive = true
        image.imageScaling = .scaleProportionallyUpOrDown

        let textLabel = label(text, .systemFont(ofSize: 13), .labelColor)
        let row = NSStackView(views: [image, textLabel])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    // MARK: - Actions

    @objc private func grant() {
        Accessibility.requestIfNeeded(prompt: true)
        Accessibility.openSettings()
    }

    @objc private func finish() {
        stopPolling()
        onFinish?()
        window?.close()
    }

    // MARK: - Status polling

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }
    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    private func refreshStatus() {
        if Accessibility.isTrusted {
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            statusLabel.stringValue = "Accessibility enabled — you're all set."
            statusLabel.textColor = .systemGreen
        } else {
            statusIcon.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
            statusIcon.contentTintColor = .tertiaryLabelColor
            statusLabel.stringValue = "Waiting for permission…"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Helpers

    private func label(_ text: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color
        return l
    }

    private func wrappingLabel(_ text: String, _ font: NSFont, _ color: NSColor) -> NSTextField {
        let l = label(text, font, color)
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 0
        l.preferredMaxLayoutWidth = contentWidth - 40
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        return l
    }

    private func softShadow() -> NSShadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.25)
        s.shadowBlurRadius = 12
        s.shadowOffset = NSSize(width: 0, height: -3)
        return s
    }
}
