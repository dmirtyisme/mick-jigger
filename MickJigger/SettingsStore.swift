import Foundation

extension Notification.Name {
    /// Posted after any setting write. userInfo["key"] holds the UserDefaults key.
    static let settingsDidChange = Notification.Name("mjv1.settingsDidChange")
}

/// UserDefaults-backed settings. Keys and defaults from PRODUCT_SPEC.md / TECH_NOTES.md.
/// `isActive` / `currentState` are intentionally NOT persisted.
final class SettingsStore {

    enum Key {
        static let interval           = "mjv1.interval"            // Int, seconds
        static let movementDistance   = "mjv1.movementDistance"    // Int, pixels
        static let autoStartEnabled   = "mjv1.autoStartEnabled"    // Bool
        static let autoStartThreshold = "mjv1.autoStartThreshold"  // Int, seconds
        static let marginTop          = "mjv1.marginTop"           // Int, pixels
        static let marginBottom       = "mjv1.marginBottom"        // Int, pixels
        static let marginLeft         = "mjv1.marginLeft"          // Int, pixels
        static let marginRight        = "mjv1.marginRight"         // Int, pixels
        static let launchAtLogin      = "mjv1.launchAtLogin"       // Bool
        // V2 interaction features — all opt-in, default OFF.
        static let clickEnabled       = "mjv1.clickEnabled"        // Bool
        static let scrollEnabled      = "mjv1.scrollEnabled"       // Bool
        static let randomInterval     = "mjv1.randomInterval"      // Bool, ±30% jitter
        static let clickInterval      = "mjv1.clickInterval"       // Int, seconds
    }

    /// Selectable values, in segmented-control order.
    static let intervalOptions = [30, 60, 120, 300]
    static let distanceOptions = [5, 20, 50]
    static let distanceLabels = ["Small", "Medium", "Large"]
    static let autoStartThresholdOptions = [30, 60, 300, 600]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.interval: 60,
            Key.movementDistance: 20,
            Key.autoStartEnabled: false,
            Key.autoStartThreshold: 300,
            Key.marginTop: 60,
            Key.marginBottom: 80,
            Key.marginLeft: 20,
            Key.marginRight: 20,
            Key.launchAtLogin: false,
            Key.clickEnabled: false,
            Key.scrollEnabled: false,
            Key.randomInterval: false,
            Key.clickInterval: 60,
        ])
    }

    var interval: Int {
        get { defaults.integer(forKey: Key.interval) }
        set { set(newValue, forKey: Key.interval) }
    }

    var movementDistance: Int {
        get { defaults.integer(forKey: Key.movementDistance) }
        set { set(newValue, forKey: Key.movementDistance) }
    }

    var autoStartEnabled: Bool {
        get { defaults.bool(forKey: Key.autoStartEnabled) }
        set { set(newValue, forKey: Key.autoStartEnabled) }
    }

    var autoStartThreshold: Int {
        get { defaults.integer(forKey: Key.autoStartThreshold) }
        set { set(newValue, forKey: Key.autoStartThreshold) }
    }

    var marginTop: Int {
        get { defaults.integer(forKey: Key.marginTop) }
        set { set(newValue, forKey: Key.marginTop) }
    }

    var marginBottom: Int {
        get { defaults.integer(forKey: Key.marginBottom) }
        set { set(newValue, forKey: Key.marginBottom) }
    }

    var marginLeft: Int {
        get { defaults.integer(forKey: Key.marginLeft) }
        set { set(newValue, forKey: Key.marginLeft) }
    }

    var marginRight: Int {
        get { defaults.integer(forKey: Key.marginRight) }
        set { set(newValue, forKey: Key.marginRight) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { set(newValue, forKey: Key.launchAtLogin) }
    }

    var clickEnabled: Bool {
        get { defaults.bool(forKey: Key.clickEnabled) }
        set { set(newValue, forKey: Key.clickEnabled) }
    }

    var scrollEnabled: Bool {
        get { defaults.bool(forKey: Key.scrollEnabled) }
        set { set(newValue, forKey: Key.scrollEnabled) }
    }

    var randomInterval: Bool {
        get { defaults.bool(forKey: Key.randomInterval) }
        set { set(newValue, forKey: Key.randomInterval) }
    }

    var clickInterval: Int {
        get { defaults.integer(forKey: Key.clickInterval) }
        set { set(newValue, forKey: Key.clickInterval) }
    }

    private func set(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(
            name: .settingsDidChange, object: self, userInfo: ["key": key]
        )
    }

    /// "30s", "1min", "2min", "5min", "10min" — labels used in segmented
    /// controls and status sublines.
    static func label(forSeconds seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds == 60 { return "1min" }
        return "\(seconds / 60)min"
    }

    /// Subline form: PRODUCT_SPEC shows "Jiggling every 60s" for the 1min interval.
    static func sublineLabel(forSeconds seconds: Int) -> String {
        if seconds <= 60 { return "\(seconds)s" }
        return "\(seconds / 60)min"
    }
}
