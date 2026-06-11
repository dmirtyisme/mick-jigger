import Foundation

/// Auto-detects work sessions from real HID input.
///
/// A session starts on the first real input after ≥5 minutes of idle
/// (equivalently: any real input while no session is open, since sessions
/// close after 5 idle minutes). A session ends after 5 minutes without real
/// input — the session's `end` is the last real input, not the cutoff tick.
///
/// Runs its own 1-second timer; deliberately independent from PollingLoop
/// (which belongs to the jiggler state machine and must not be touched).
final class SessionDetector {

    /// 5 minutes of no real input closes the session.
    static let idleCutoff: TimeInterval = 300

    /// Fired when a session closes (idle cutoff reached).
    var onSessionEnd: ((ActivitySession) -> Void)?

    private var sessionStart: Date?
    private var lastRealInput: Date?
    private var clicks = 0
    private var scrolls = 0
    private var distancePx = 0.0

    private var timer: Timer?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called by ActivityTracker for every real (non-synthetic) input event.
    func registerRealEvent(kind: RealEventKind, distancePx: Double, at date: Date) {
        if sessionStart == nil {
            sessionStart = date
            clicks = 0
            scrolls = 0
            self.distancePx = 0
        }
        lastRealInput = date

        switch kind {
        case .click, .doubleClick:
            clicks += 1
        case .scroll:
            scrolls += 1
        case .move:
            break
        }
        self.distancePx += distancePx
    }

    /// The currently open session, if any — used for live "Active Time".
    func openSession(now: Date = Date()) -> (start: Date, lastInput: Date)? {
        guard let start = sessionStart, let last = lastRealInput else { return nil }
        // If we've already crossed the cutoff but the timer hasn't ticked yet,
        // don't report a phantom open session.
        guard now.timeIntervalSince(last) < Self.idleCutoff else { return nil }
        return (start, last)
    }

    /// Force-closes the open session (app termination). Returns it for storage.
    func closeOpenSession() -> ActivitySession? {
        guard let session = buildSession() else { return nil }
        sessionStart = nil
        lastRealInput = nil
        return session
    }

    private func checkIdle() {
        guard let last = lastRealInput, sessionStart != nil else { return }
        guard Date().timeIntervalSince(last) >= Self.idleCutoff else { return }
        if let session = buildSession() {
            sessionStart = nil
            lastRealInput = nil
            onSessionEnd?(session)
        }
    }

    private func buildSession() -> ActivitySession? {
        guard let start = sessionStart, let end = lastRealInput, end > start else {
            // Single instantaneous event — not a meaningful session.
            sessionStart = nil
            lastRealInput = nil
            return nil
        }
        return ActivitySession(
            start: start, end: end,
            clicks: clicks, scrolls: scrolls, distancePx: distancePx)
    }

    deinit {
        stop()
    }
}
