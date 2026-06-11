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
    /// The four asset-catalog PDFs are vector template images — macOS handles
    /// light/dark menu bar tinting automatically. Active states get an accent
    /// colour tint at draw time; the badge overlay for permission warnings is
    /// composited on top at runtime so we don't need a fifth PDF.
    private static func icon(for state: JigglerState, permissionWarning: Bool) -> NSImage {
        // Choose the base PDF asset.
        let assetName: String
        switch state {
        case .inactive:    assetName = "menubar_inactive"
        case .monitoring:  assetName = "menubar_monitoring"
        case .activeManual, .activeAuto:
                           assetName = "menubar_active"
        }

        // If no badge is needed and we're not active, the template PDF is used
        // as-is — NSImage(named:) loads it and isTemplate handles tinting.
        guard let base = NSImage(named: assetName) else {
            return fallbackIcon(for: state, permissionWarning: permissionWarning)
        }
        base.isTemplate = (state == .inactive || state == .monitoring) && !permissionWarning

        // Active states: tint with the system accent colour.
        if state.isActive && !permissionWarning {
            return tinted(base, color: .controlAccentColor)
        }

        // Badges (permission warning or monitoring dot) need a composite image.
        if permissionWarning {
            return compositeWithBadge(base, color: .systemRed)
        }
        if state == .monitoring {
            return compositeWithBadge(base, color: .systemOrange)
        }

        return base
    }

    // MARK: - Icon helpers

    /// Tint a template image with a solid colour.
    private static func tinted(_ source: NSImage, color: NSColor) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let result = NSImage(size: size, flipped: false) { rect in
            color.set()
            let mask = source
            mask.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        result.isTemplate = false
        return result
    }

    /// Composite a badge dot over a base image.
    private static func compositeWithBadge(_ base: NSImage, color: NSColor) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let result = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let diameter: CGFloat = 5
            let badgeRect = NSRect(
                x: rect.maxX - diameter - 1,
                y: rect.maxY - diameter - 1,
                width: diameter,
                height: diameter
            )
            // Clear ring so the dot reads against the symbol.
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
        image.isTemplate = !state.isActive && !permissionWarning
        return image
    }
}
