import AppKit
import ApplicationServices

/// Accessibility (TCC) permission helpers.
///
/// Per APP_STORE_READINESS.md: on macOS 13+ do not pass `prompt = true` to
/// `AXIsProcessTrustedWithOptions` — open System Settings directly instead.
enum AccessibilityPermission {

    static var isGranted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
