import AppKit

/// Owns the NSStatusItem and the settings popover.
/// Left click → toggle (handled by the coordinator); right click → popover.
final class StatusItemController: NSObject, NSPopoverDelegate {

    /// Fired on right mouse up — toggle active ↔ inactive.
    var onRightClick: (() -> Void)?

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
            onRightClick?()
        } else {
            togglePopover()
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
        button.contentTintColor = nil  // let template image handle dark/light automatically
        if permissionWarning {
            button.alphaValue = 1.0
        } else {
            switch state {
            case .inactive:              button.alphaValue = 0.5
            case .monitoring:            button.alphaValue = 0.7
            case .activeManual, .activeAuto: button.alphaValue = 1.0
            }
        }
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

    /// Returns the menu bar icon. State is communicated by alphaValue, not artwork.
    private static func icon(for state: JigglerState, permissionWarning: Bool) -> NSImage {
        let base = loadMenuBarIcon()
        if permissionWarning {
            return compositeWithBadge(base, color: .systemRed)
        }
        return base
    }

    /// Loads the white-on-transparent MJ glyph as a template image.
    /// Tries the bundled PNG resource first, falls back to xcassets, then SF Symbol.
    private static func loadMenuBarIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "icon-menubar", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }
        if let image = NSImage(named: "menubar_active") {
            image.isTemplate = true
            return image
        }
        let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mick Jigger")
            ?? NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: "Mick Jigger")!
        image.isTemplate = true
        return image
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


}
