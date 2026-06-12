import AppKit
import ServiceManagement

/// Interface the popover (and status item) use to drive the state machine.
/// Implemented by AppDelegate.
protocol JigglerControlling: AnyObject {
    var state: JigglerState { get }
    /// True when an activation was blocked (or permission revoked) and the
    /// inline Accessibility prompt should be visible.
    var permissionWarningVisible: Bool { get }
    /// User intent: turn jiggling on (header toggle / left click).
    func requestActivateManual()
    /// User intent: turn jiggling off (header toggle).
    func requestDeactivate()
    /// Auto-start master toggle changed in the popover.
    func autoStartToggled(_ enabled: Bool)
    /// Re-check Accessibility; clears the warning if access was granted.
    /// Called on popover open so the app "detects grant on next popover open".
    func recheckPermission()
}

/// Programmatic AppKit popover content. Layout follows PRODUCT_SPEC.md.
/// Hotkeys are out of MVP scope and intentionally absent.
final class PopoverViewController: NSViewController, NSTextFieldDelegate {

    private weak var controller: JigglerControlling?
    private let settings: SettingsStore

    private static let contentWidth: CGFloat = 320

    // MARK: Controls

    private let statusDotLabel = NSTextField(labelWithString: "")
    private let activeSwitch = NSSwitch()
    private let sublineLabel = NSTextField(labelWithString: "")

    private let permissionBanner = NSStackView()
    private let permissionTextLabel = NSTextField(wrappingLabelWithString:
        "⚠ Accessibility access required\nMick Jigger needs Accessibility permission to simulate mouse activity.")

    private let intervalControl = NSSegmentedControl(
        labels: SettingsStore.intervalOptions.map(SettingsStore.label(forSeconds:)),
        trackingMode: .selectOne, target: nil, action: nil)
    private let randomIntervalSwitch = NSSwitch()
    private let distanceControl = NSSegmentedControl(
        labels: SettingsStore.distanceLabels,
        trackingMode: .selectOne, target: nil, action: nil)

    // V2 interaction (opt-in, default OFF)
    private let clickSwitch = NSSwitch()
    private let scrollSwitch = NSSwitch()
    private let clickIntervalRow = NSStackView()
    private let clickIntervalControl = NSSegmentedControl(
        labels: SettingsStore.intervalOptions.map(SettingsStore.label(forSeconds:)),
        trackingMode: .selectOne, target: nil, action: nil)
    private let interactionWarningLabel = NSTextField(wrappingLabelWithString:
        "⚠ Click or scroll simulation can interact with whatever is under the cursor. Events fire only while you're away and only inside the safe area.")

    private let autoStartSwitch = NSSwitch()
    private let thresholdRow = NSStackView()
    private let thresholdControl = NSSegmentedControl(
        labels: SettingsStore.autoStartThresholdOptions.map(SettingsStore.label(forSeconds:)),
        trackingMode: .selectOne, target: nil, action: nil)

    private let marginsHeaderButton = NSButton()
    private var marginsExpanded = false
    private let marginsContainer = NSStackView()
    private let marginTopField = NSTextField()
    private let marginBottomField = NSTextField()
    private let marginLeftField = NSTextField()
    private let marginRightField = NSTextField()
    private let marginsWarningLabel = NSTextField(wrappingLabelWithString:
        "⚠ Margins too large for this screen — using a minimum 100×100 px area.")

    // Activity tracking quick stats (today: clicks · distance · active time).
    private let activityStatsLabel = NSTextField(labelWithString: "")

    private let launchAtLoginSwitch = NSSwitch()

    init(controller: JigglerControlling, settings: SettingsStore) {
        self.controller = controller
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - View construction

    override func loadView() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false

        // Permission banner (hidden unless an activation was blocked).
        buildPermissionBanner()
        root.addArrangedSubview(permissionBanner)

        // Header: title + status dot + master toggle.
        let titleLabel = NSTextField(labelWithString: "Mick Jigger")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusDotLabel.font = .systemFont(ofSize: 11, weight: .medium)
        activeSwitch.target = self
        activeSwitch.action = #selector(activeSwitchChanged)
        let header = row(titleLabel, spacer(), statusDotLabel, activeSwitch)
        root.addArrangedSubview(header)

        sublineLabel.font = .systemFont(ofSize: 11)
        sublineLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(sublineLabel)

        root.addArrangedSubview(separator())

        // Jiggle interval.
        root.addArrangedSubview(sectionLabel("Jiggle interval"))
        intervalControl.target = self
        intervalControl.action = #selector(intervalChanged)
        root.addArrangedSubview(intervalControl)

        // Random interval mode: ±30% jitter around the base interval.
        let randomLabel = NSTextField(labelWithString: "Randomize interval (±30%)")
        randomLabel.font = .systemFont(ofSize: 12)
        randomIntervalSwitch.target = self
        randomIntervalSwitch.action = #selector(randomIntervalChanged)
        let randomRow = row(randomLabel, spacer(), randomIntervalSwitch)
        root.addArrangedSubview(randomRow)

        root.addArrangedSubview(separator())

        // Movement distance.
        root.addArrangedSubview(sectionLabel("Movement distance"))
        distanceControl.target = self
        distanceControl.action = #selector(distanceChanged)
        root.addArrangedSubview(distanceControl)

        root.addArrangedSubview(separator())

        // Interaction (V2): click + scroll simulation, strictly opt-in.
        root.addArrangedSubview(sectionLabel("Interaction"))

        let clickLabel = NSTextField(labelWithString: "Simulate clicks")
        clickLabel.font = .systemFont(ofSize: 12)
        clickSwitch.target = self
        clickSwitch.action = #selector(clickToggled)
        let clickRow = row(clickLabel, spacer(), clickSwitch)
        root.addArrangedSubview(clickRow)

        // "Click every" — collapsed entirely while click simulation is OFF.
        let clickEveryLabel = NSTextField(labelWithString: "Click every:")
        clickEveryLabel.font = .systemFont(ofSize: 11)
        clickEveryLabel.textColor = .secondaryLabelColor
        clickIntervalControl.target = self
        clickIntervalControl.action = #selector(clickIntervalChanged)
        clickIntervalRow.orientation = .vertical
        clickIntervalRow.alignment = .leading
        clickIntervalRow.spacing = 4
        clickIntervalRow.addArrangedSubview(clickEveryLabel)
        clickIntervalRow.addArrangedSubview(clickIntervalControl)
        root.addArrangedSubview(clickIntervalRow)

        let scrollLabel = NSTextField(labelWithString: "Simulate scrolling")
        scrollLabel.font = .systemFont(ofSize: 12)
        scrollSwitch.target = self
        scrollSwitch.action = #selector(scrollToggled)
        let scrollRow = row(scrollLabel, spacer(), scrollSwitch)
        root.addArrangedSubview(scrollRow)

        interactionWarningLabel.font = .systemFont(ofSize: 10)
        interactionWarningLabel.textColor = .systemOrange
        interactionWarningLabel.isHidden = true
        root.addArrangedSubview(interactionWarningLabel)

        root.addArrangedSubview(separator())

        // Auto-start after inactivity.
        let autoStartLabel = NSTextField(labelWithString: "Auto-start after inactivity")
        autoStartLabel.font = .systemFont(ofSize: 12)
        autoStartSwitch.target = self
        autoStartSwitch.action = #selector(autoStartSwitchChanged)
        let autoStartRow = row(autoStartLabel, spacer(), autoStartSwitch)
        root.addArrangedSubview(autoStartRow)

        // "Start after" — fully collapsed (not greyed out) when auto-start is OFF.
        let startAfterLabel = NSTextField(labelWithString: "Start after:")
        startAfterLabel.font = .systemFont(ofSize: 11)
        startAfterLabel.textColor = .secondaryLabelColor
        thresholdControl.target = self
        thresholdControl.action = #selector(thresholdChanged)
        thresholdRow.orientation = .vertical
        thresholdRow.alignment = .leading
        thresholdRow.spacing = 4
        thresholdRow.addArrangedSubview(startAfterLabel)
        thresholdRow.addArrangedSubview(thresholdControl)
        root.addArrangedSubview(thresholdRow)

        root.addArrangedSubview(separator())

        // Safe area margins (disclosure section). The header is one borderless
        // NSButton spanning the full popover width — chevron + label in a
        // single row, every point of which is clickable.
        marginsHeaderButton.title = " Safe area margins"
        marginsHeaderButton.font = .systemFont(ofSize: 12)
        marginsHeaderButton.image = Self.chevronImage(expanded: false)
        marginsHeaderButton.imagePosition = .imageLeading
        marginsHeaderButton.alignment = .left
        marginsHeaderButton.isBordered = false
        marginsHeaderButton.setButtonType(.momentaryChange)
        marginsHeaderButton.contentTintColor = .labelColor
        marginsHeaderButton.target = self
        marginsHeaderButton.action = #selector(marginsHeaderClicked)
        root.addArrangedSubview(marginsHeaderButton)

        buildMarginsContainer()
        marginsContainer.isHidden = true
        root.addArrangedSubview(marginsContainer)

        root.addArrangedSubview(separator())

        // Activity tracking: today's quick stats + window button.
        root.addArrangedSubview(sectionLabel("Activity"))
        activityStatsLabel.font = .systemFont(ofSize: 11)
        activityStatsLabel.textColor = .secondaryLabelColor
        let activityButton = NSButton(
            title: "Activity…", target: self, action: #selector(openActivityWindow))
        activityButton.bezelStyle = .rounded
        activityButton.controlSize = .small
        let activityRow = row(activityStatsLabel, spacer(), activityButton)
        root.addArrangedSubview(activityRow)

        root.addArrangedSubview(separator())

        // Launch at login (SMAppService-backed).
        let launchLabel = NSTextField(labelWithString: "Launch at login")
        launchLabel.font = .systemFont(ofSize: 12)
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginToggled)
        let launchRow = row(launchLabel, spacer(), launchAtLoginSwitch)
        root.addArrangedSubview(launchRow)

        // Quit.
        let quitButton = NSButton(title: "Quit Mick Jigger", target: self, action: #selector(quit))
        quitButton.bezelStyle = .inline
        quitButton.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(quitButton)

        // Pin widths so the stack lays out at a fixed popover width.
        for item in [permissionBanner, header, sublineLabel, intervalControl,
                     randomRow, distanceControl, clickRow, clickIntervalRow,
                     scrollRow, interactionWarningLabel, autoStartRow,
                     thresholdRow, marginsHeaderButton, marginsContainer,
                     activityRow, launchRow] {
            item.widthAnchor.constraint(
                equalTo: root.widthAnchor, constant: -28).isActive = true
        }

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])
        view = container
    }

    private func buildPermissionBanner() {
        permissionBanner.orientation = .vertical
        permissionBanner.alignment = .leading
        permissionBanner.spacing = 6
        permissionTextLabel.font = .systemFont(ofSize: 11)
        permissionTextLabel.textColor = .systemOrange
        let openButton = NSButton(
            title: "Open System Settings",
            target: self,
            action: #selector(openAccessibilitySettings))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        permissionBanner.addArrangedSubview(permissionTextLabel)
        permissionBanner.addArrangedSubview(openButton)
        permissionBanner.isHidden = true
    }

    private func buildMarginsContainer() {
        marginsContainer.orientation = .vertical
        marginsContainer.alignment = .leading
        marginsContainer.spacing = 6

        let grid = NSGridView(views: [
            marginRow("Top", marginTopField),
            marginRow("Bottom", marginBottomField),
            marginRow("Left", marginLeftField),
            marginRow("Right", marginRightField),
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        marginsContainer.addArrangedSubview(grid)

        marginsWarningLabel.font = .systemFont(ofSize: 10)
        marginsWarningLabel.textColor = .systemOrange
        marginsWarningLabel.isHidden = true
        marginsContainer.addArrangedSubview(marginsWarningLabel)
    }

    private func marginRow(_ title: String, _ field: NSTextField) -> [NSView] {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 2000
        field.formatter = formatter
        field.font = .systemFont(ofSize: 12)
        field.alignment = .right
        field.delegate = self
        field.target = self
        field.action = #selector(marginFieldChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let px = NSTextField(labelWithString: "px")
        px.font = .systemFont(ofSize: 11)
        px.textColor = .secondaryLabelColor
        return [label, field, px]
    }

    // MARK: - Row helpers

    private func row(_ items: NSView...) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        for view in items {
            stack.addArrangedSubview(view)
        }
        return stack
    }

    /// Empty view that absorbs leftover horizontal space in a row.
    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return view
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: Self.contentWidth - 28).isActive = true
        return box
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self, selector: #selector(stateDidChange),
            name: .jigglerStateDidChange, object: nil)
        refresh()
    }

    @objc private func stateDidChange() {
        refresh()
    }

    // MARK: - Refresh

    /// Re-reads state + settings and updates every control. Called on popover
    /// open and on every state transition while visible.
    func refresh() {
        controller?.recheckPermission()
        guard let controller else { return }
        let state = controller.state
        let permissionWarning = controller.permissionWarningVisible

        // Header.
        activeSwitch.state = state.isActive ? .on : .off
        statusDotLabel.attributedStringValue = Self.statusBadge(for: state)

        // Subline.
        if permissionWarning {
            sublineLabel.stringValue = "⚠ Accessibility access required"
            sublineLabel.textColor = .systemOrange
        } else {
            sublineLabel.textColor = .secondaryLabelColor
            let intervalLabel = SettingsStore.sublineLabel(forSeconds: settings.interval)
            switch state {
            case .inactive:
                sublineLabel.stringValue = "Inactive"
            case .monitoring:
                let threshold = SettingsStore.label(forSeconds: settings.autoStartThreshold)
                sublineLabel.stringValue = "Watching — starts after \(threshold) idle"
            case .activeManual:
                sublineLabel.stringValue = "Jiggling every \(intervalLabel)"
            case .activeAuto:
                sublineLabel.stringValue = "Auto-active — jiggling every \(intervalLabel)"
            }
        }

        permissionBanner.isHidden = !permissionWarning

        // Settings controls.
        intervalControl.selectedSegment =
            SettingsStore.intervalOptions.firstIndex(of: settings.interval) ?? 1
        randomIntervalSwitch.state = settings.randomInterval ? .on : .off
        distanceControl.selectedSegment =
            SettingsStore.distanceOptions.firstIndex(of: settings.movementDistance) ?? 1

        // Interaction (V2).
        clickSwitch.state = settings.clickEnabled ? .on : .off
        scrollSwitch.state = settings.scrollEnabled ? .on : .off
        clickIntervalRow.isHidden = !settings.clickEnabled
        clickIntervalControl.selectedSegment =
            SettingsStore.intervalOptions.firstIndex(of: settings.clickInterval) ?? 1
        interactionWarningLabel.isHidden = !(settings.clickEnabled || settings.scrollEnabled)

        autoStartSwitch.state = settings.autoStartEnabled ? .on : .off
        thresholdRow.isHidden = !settings.autoStartEnabled
        thresholdControl.selectedSegment =
            SettingsStore.autoStartThresholdOptions.firstIndex(of: settings.autoStartThreshold) ?? 2

        // Activity quick stats. Also picks up a fresh Input Monitoring grant
        // on popover open, mirroring the Accessibility detection flow.
        let activity = ActivityService.shared
        if !activity.isTracking && InputMonitoringPermission.isGranted {
            activity.start()
        }
        if activity.isTracking {
            let today = activity.todaySnapshot()
            activityStatsLabel.stringValue =
                "\(ActivityService.formatCount(today.clicks)) clicks · "
                + "\(ActivityService.formatDistance(px: today.distancePx)) · "
                + "\(ActivityService.formatDuration(today.activeSeconds)) active"
        } else {
            activityStatsLabel.stringValue = "Tracking off — needs Input Monitoring"
        }

        // Launch at login. SMAppService is the source of truth — the user can
        // also remove the login item from System Settings behind our back.
        let loginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginSwitch.state = loginEnabled ? .on : .off
        if settings.launchAtLogin != loginEnabled {
            settings.launchAtLogin = loginEnabled
        }

        // Margins.
        marginTopField.integerValue = settings.marginTop
        marginBottomField.integerValue = settings.marginBottom
        marginLeftField.integerValue = settings.marginLeft
        marginRightField.integerValue = settings.marginRight
        refreshMarginsWarning()

        updatePreferredSize()
    }

    private func refreshMarginsWarning() {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            marginsWarningLabel.isHidden =
                !SafeArea(settings: settings).isClampedToMinimum(for: screen)
        } else {
            marginsWarningLabel.isHidden = true
        }
    }

    private func updatePreferredSize() {
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    private static func statusBadge(for state: JigglerState) -> NSAttributedString {
        let (text, color): (String, NSColor)
        switch state {
        case .inactive: (text, color) = ("Inactive", .secondaryLabelColor)
        case .monitoring: (text, color) = ("Watching", .systemOrange)
        case .activeManual, .activeAuto: (text, color) = ("Active", .controlAccentColor)
        }
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: color]))
        result.append(NSAttributedString(
            string: text, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        return result
    }

    // MARK: - Actions

    @objc private func activeSwitchChanged() {
        if activeSwitch.state == .on {
            controller?.requestActivateManual()
        } else {
            controller?.requestDeactivate()
        }
        refresh()  // activation may have been blocked by missing permission
    }

    @objc private func intervalChanged() {
        let index = intervalControl.selectedSegment
        guard SettingsStore.intervalOptions.indices.contains(index) else { return }
        settings.interval = SettingsStore.intervalOptions[index]
        refresh()
    }

    @objc private func distanceChanged() {
        let index = distanceControl.selectedSegment
        guard SettingsStore.distanceOptions.indices.contains(index) else { return }
        settings.movementDistance = SettingsStore.distanceOptions[index]
    }

    @objc private func randomIntervalChanged() {
        settings.randomInterval = randomIntervalSwitch.state == .on
    }

    @objc private func clickToggled() {
        settings.clickEnabled = clickSwitch.state == .on
        refresh()
    }

    @objc private func clickIntervalChanged() {
        let index = clickIntervalControl.selectedSegment
        guard SettingsStore.intervalOptions.indices.contains(index) else { return }
        settings.clickInterval = SettingsStore.intervalOptions[index]
    }

    @objc private func scrollToggled() {
        settings.scrollEnabled = scrollSwitch.state == .on
        refresh()
    }

    @objc private func autoStartSwitchChanged() {
        controller?.autoStartToggled(autoStartSwitch.state == .on)
        refresh()
    }

    @objc private func thresholdChanged() {
        let index = thresholdControl.selectedSegment
        guard SettingsStore.autoStartThresholdOptions.indices.contains(index) else { return }
        settings.autoStartThreshold = SettingsStore.autoStartThresholdOptions[index]
        refresh()
    }

    @objc private func marginsHeaderClicked() {
        marginsExpanded.toggle()
        // NSStackView detaches hidden arranged subviews, so the collapsed
        // fields are genuinely removed from layout, not just invisible.
        marginsContainer.isHidden = !marginsExpanded
        marginsHeaderButton.image = Self.chevronImage(expanded: marginsExpanded)
        updatePreferredSize()
    }

    /// "chevron.right" SF Symbol: as-is when collapsed (0°), or re-rendered
    /// into a -90°-rotated NSImage (pointing down) when expanded. The rotated
    /// rendition stays a template image so it tints with the button.
    private static func chevronImage(expanded: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        guard let base = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: expanded ? "Collapse" : "Expand")?
            .withSymbolConfiguration(config)
        else { return nil }
        guard expanded else { return base }

        let size = NSSize(width: max(base.size.width, base.size.height),
                          height: max(base.size.width, base.size.height))
        let rotated = NSImage(size: size, flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: rect.width / 2, yBy: rect.height / 2)
            transform.rotate(byDegrees: -90)
            transform.translateX(by: -rect.width / 2, yBy: -rect.height / 2)
            transform.concat()
            base.draw(in: NSRect(
                x: (rect.width - base.size.width) / 2,
                y: (rect.height - base.size.height) / 2,
                width: base.size.width, height: base.size.height))
            return true
        }
        rotated.isTemplate = true
        return rotated
    }

    @objc private func launchAtLoginToggled() {
        let enable = launchAtLoginSwitch.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enable
        } catch {
            // Registration can fail (e.g. app not in /Applications on some
            // configurations). Revert the switch so UI reflects reality.
            NSLog("Launch at login change failed: \(error.localizedDescription)")
            launchAtLoginSwitch.state = enable ? .off : .on
        }
    }

    @objc private func marginFieldChanged(_ sender: NSTextField) {
        commitMargin(from: sender)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            commitMargin(from: field)
        }
    }

    private func commitMargin(from field: NSTextField) {
        let value = max(0, field.integerValue)
        switch field {
        case marginTopField: settings.marginTop = value
        case marginBottomField: settings.marginBottom = value
        case marginLeftField: settings.marginLeft = value
        case marginRightField: settings.marginRight = value
        default: return
        }
        refreshMarginsWarning()
        updatePreferredSize()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func openActivityWindow() {
        ActivityService.shared.showActivityWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
