import AppKit
import CoreGraphics

/// 1-second polling loop — the single source of truth for auto-start logic.
/// Runs only while the app is in MONITORING or ACTIVE (auto); the coordinator
/// (AppDelegate) starts and stops it on state transitions.
final class PollingLoop {

    /// Time since last PHYSICAL user input. Uses `.hidSystemState`, so
    /// synthetic events posted by this app do NOT affect the counter —
    /// our own jiggling cannot trigger auto-stop detection.
    /// No Accessibility permission required.
    static func physicalIdleSeconds() -> TimeInterval {
        let mouseIdle  = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        let keyIdle    = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        let clickIdle  = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
        let scrollIdle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .scrollWheel)
        return min(mouseIdle, keyIdle, clickIdle, scrollIdle)
    }

    /// Called every second on the main queue with the current physical idle time.
    var onTick: ((TimeInterval) -> Void)?

    private var timer: DispatchSourceTimer?

    var isRunning: Bool { timer != nil }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.onTick?(Self.physicalIdleSeconds())
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Clean stop + start, used after sleep/wake so the timer never sits
    /// in a suspended or double-firing state.
    func restart() {
        if isRunning { start() }
    }

    deinit {
        stop()
    }
}
