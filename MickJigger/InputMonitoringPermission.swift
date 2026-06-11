import AppKit
import CoreGraphics

/// Input Monitoring (TCC) permission helpers — required for the listen-only
/// CGEventTap in ActivityTracker. Same pattern as AccessibilityPermission:
/// never prompt at launch; check silently, prompt only from explicit UI.
enum InputMonitoringPermission {

    static var isGranted: Bool {
        CGPreflightListenEventAccess()
    }

    /// Triggers the system permission prompt (first call only) and registers
    /// the app in System Settings → Privacy & Security → Input Monitoring.
    /// Returns true if access is already (or becomes) granted.
    @discardableResult
    static func request() -> Bool {
        CGRequestListenEventAccess()
    }

    /// Opens System Settings → Privacy & Security → Input Monitoring.
    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
