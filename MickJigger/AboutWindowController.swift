import AppKit

final class AboutWindowController: NSWindowController {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "About Mick Jigger"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func buildContent() {
        guard let window else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 28, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        // App icon.
        let iconView = NSImageView()
        iconView.image = NSImage(named: "AppIcon")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        root.addArrangedSubview(iconView)

        // App name.
        let nameLabel = NSTextField(labelWithString: "Mick Jigger")
        nameLabel.font = .systemFont(ofSize: 18, weight: .bold)
        nameLabel.textColor = .labelColor
        nameLabel.alignment = .center
        root.addArrangedSubview(nameLabel)

        // Version.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        root.addArrangedSubview(versionLabel)

        // Divider.
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        root.setCustomSpacing(16, after: versionLabel)
        root.addArrangedSubview(divider)
        root.setCustomSpacing(16, after: divider)

        // Website button.
        let websiteButton = NSButton(title: "mickjigger.app", target: self, action: #selector(openWebsite))
        websiteButton.bezelStyle = .rounded
        websiteButton.keyEquivalent = ""
        root.addArrangedSubview(websiteButton)

        // Close button.
        let closeButton = NSButton(title: "Close", target: self, action: #selector(close))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"
        root.addArrangedSubview(closeButton)

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(equalToConstant: 300),
            container.heightAnchor.constraint(equalToConstant: 320),
        ])
        window.contentView = container
    }

    @objc private func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://mickjigger.app")!)
    }
}
