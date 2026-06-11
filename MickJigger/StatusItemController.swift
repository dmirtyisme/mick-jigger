import AppKit

/// Owns the NSStatusItem and the settings popover.
/// Left click → toggle (handled by the coordinator); right click → popover.
final class StatusItemController: NSObject, NSPopoverDelegate {

    /// Fired on left mouse up over the status item.
    var onLeftClick: (() -> Void)?

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let popoverViewController: PopoverViewController

    init(controller: JigglerControlling, settings: SettingsStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popoverViewController = PopoverViewController(controller: controller, settings: settings)
        super.init()

        popover.contentViewController = popoverViewController
        popover.behavior = .transient  // closes on click outside
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        update(state: .inactive, permissionWarning: false)
    }

    // MARK: - Clicks

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            togglePopover()
        } else {
            onLeftClick?()
        }
    }

    // MARK: - Popover

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popoverViewController.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Transient popovers from a status item need the app activated to
        // reliably close on outside clicks.
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Icon

    func update(state: JigglerState, permissionWarning: Bool) {
        guard let button = statusItem.button else { return }
        button.image = Self.icon(for: state, permissionWarning: permissionWarning)
        button.toolTip = Self.toolTip(for: state, permissionWarning: permissionWarning)
    }

    private static func toolTip(for state: JigglerState, permissionWarning: Bool) -> String {
        if permissionWarning { return "Mick Jigger — Accessibility access required" }
        switch state {
        case .inactive: return "Mick Jigger — Inactive"
        case .monitoring: return "Mick Jigger — Watching for inactivity"
        case .activeManual: return "Mick Jigger — Active"
        case .activeAuto: return "Mick Jigger — Active (auto)"
        }
    }

    /// Returns the menu bar icon for the current state.
    ///
    /// All four state assets are vector template PDFs and are used in template
    /// mode — macOS tints them for the light/dark menu bar (and the pressed
    /// highlight) automatically. State is conveyed by the artwork itself:
    /// outline (inactive), outline+dot (monitoring), filled (active).
    /// The only non-template case is the permission warning, whose red badge
    /// must stay red; its base glyph is tinted with `labelColor` at draw time
    /// so it still adapts to both menu bar appearances.
    private static func icon(for state: JigglerState, permissionWarning: Bool) -> NSImage {
        let assetName: String
        switch state {
        case .inactive:     assetName = "menubar_inactive"
        case .monitoring:   assetName = "menubar_monitoring"
        case .activeManual: assetName = "menubar_active"
        case .activeAuto:   assetName = "menubar_active_auto"
        }

        guard let base = NSImage(named: assetName) else {
            return fallbackIcon(for: state, permissionWarning: permissionWarning)
        }
        base.isTemplate = true

        if permissionWarning {
            return compositeWithBadge(base, color: .systemRed)
        }
        return base
    }

    // MARK: - Icon helpers

    /// Composite a colored badge dot over a template base. The drawing handler
    /// runs at draw time with the menu bar's effective appearance, so
    /// `labelColor` resolves to the right black/white automatically even
    /// though the result can't be a template image (the badge must keep its
    /// own color).
    private static func compositeWithBadge(_ base: NSImage, color: NSColor) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let result = NSImage(size: size, flipped: false) { rect in
            // Tint the template artwork with the appearance's label color.
            base.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)

            let diameter: CGFloat = 6
            let badgeRect = NSRect(
                x: rect.maxX - diameter - 1,
                y: rect.maxY - diameter - 1,
                width: diameter,
                height: diameter
            )
            // Clear ring so the dot reads against the glyph.
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
            color.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            return true
        }
        result.isTemplate = false
        return result
    }

    /// Emergency fallback: SF Symbol, used only if the asset catalog is missing.
    private static func fallbackIcon(for state: JigglerState, permissionWarning: Bool) -> NSImage {
        let name = state.isActive ? "computermouse.fill" : "computermouse"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Mick Jigger")
            ?? NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: "Mick Jigger")!
        image.isTemplate = !permissionWarning
        return image
    }
}
