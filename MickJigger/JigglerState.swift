import Foundation

/// The four discrete application states from PRODUCT_SPEC.md.
enum JigglerState: Equatable {
    /// App is idle. No jiggling, no monitoring. Manual activation only.
    case inactive
    /// Auto-start is enabled. Watching physical input. No jiggling yet.
    case monitoring
    /// User explicitly activated via left-click or toggle. Jiggling runs.
    case activeManual
    /// Jiggling started automatically after inactivity threshold was reached.
    case activeAuto

    /// ACTIVE (auto) and ACTIVE (manual) are behaviorally identical for jiggling.
    var isActive: Bool {
        self == .activeManual || self == .activeAuto
    }

    /// The 1-second polling loop runs only in MONITORING and ACTIVE (auto).
    var needsPollingLoop: Bool {
        self == .monitoring || self == .activeAuto
    }
}

extension Notification.Name {
    /// Posted by the coordinator whenever the state machine transitions
    /// or the permission-warning flag changes. UI observes this.
    static let jigglerStateDidChange = Notification.Name("mjv1.stateDidChange")
}
