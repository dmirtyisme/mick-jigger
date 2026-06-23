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
        button.image = icon(for: state)
        button.toolTip = Self.toolTip(for: state, permissionWarning: permissionWarning)
        button.alphaValue = 1.0
        button.contentTintColor = permissionWarning ? .systemRed : tintColor(for: state)
    }

    private func icon(for state: JigglerState) -> NSImage {
        if let url = Bundle.main.url(forResource: "icon-menubar", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            return img
        }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        return NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
    }

    private func tintColor(for state: JigglerState) -> NSColor? {
        switch state {
        case .inactive:                  return nil
        case .monitoring:                return .systemOrange
        case .activeManual, .activeAuto: return .systemBlue
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



}
