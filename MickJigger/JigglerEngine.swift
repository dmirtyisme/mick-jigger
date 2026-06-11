import AppKit
import CoreGraphics

/// Tag for our synthetic CGEventSource ("MJIGG"). The `.hidSystemState`
/// isolation already keeps our events out of idle queries; the tag defends
/// against future edge cases where our events could be misread.
let kMickJiggerSyntheticTag: Int64 = 0x4D4A494747

/// Screen bounds minus configurable margins, computed in CGEvent coordinate
/// space (top-left origin). All cursor math happens in this space —
/// NSScreen / NSEvent use bottom-left origin and must be converted.
struct SafeArea {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat

    /// The safe area never shrinks below this (PRODUCT_SPEC edge case:
    /// "Safe area too small → clamp to 100×100px minimum; show inline warning").
    static let minimumSide: CGFloat = 100

    init(settings: SettingsStore) {
        top = CGFloat(settings.marginTop)
        bottom = CGFloat(settings.marginBottom)
        left = CGFloat(settings.marginLeft)
        right = CGFloat(settings.marginRight)
    }

    /// Raw screen-minus-margins rect in CGEvent space, before the minimum-size clamp.
    func rawCGBounds(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        // NSScreen uses bottom-left origin; convert via total desktop height.
        let screenHeight = NSScreen.screens
            .map { $0.frame.maxY }
            .max() ?? frame.height

        let cgTop = screenHeight - frame.maxY + top
        let cgBottom = screenHeight - frame.minY - bottom

        return CGRect(
            x: frame.minX + left,
            y: cgTop,
            width: frame.width - left - right,
            height: cgBottom - cgTop
        )
    }

    /// Effective bounds: raw bounds clamped to a 100×100 minimum, centered
    /// on the screen when the margins leave no valid movement zone.
    func cgBounds(for screen: NSScreen) -> CGRect {
        var bounds = rawCGBounds(for: screen)
        let frame = screen.frame
        let screenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? frame.height
        let cgScreen = CGRect(
            x: frame.minX,
            y: screenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
        if bounds.width < Self.minimumSide {
            bounds.origin.x = cgScreen.midX - Self.minimumSide / 2
            bounds.size.width = Self.minimumSide
        }
        if bounds.height < Self.minimumSide {
            bounds.origin.y = cgScreen.midY - Self.minimumSide / 2
            bounds.size.height = Self.minimumSide
        }
        return bounds
    }

    /// True when the configured margins are too large for the screen and the
    /// 100×100 minimum clamp is in effect. Drives the inline popover warning.
    func isClampedToMinimum(for screen: NSScreen) -> Bool {
        let raw = rawCGBounds(for: screen)
        return raw.width < Self.minimumSide || raw.height < Self.minimumSide
    }

    func contains(_ point: CGPoint, on screen: NSScreen) -> Bool {
        cgBounds(for: screen).contains(point)
    }

    func clamp(_ point: CGPoint, on screen: NSScreen) -> CGPoint {
        let bounds = cgBounds(for: screen)
        return CGPoint(
            x: max(bounds.minX, min(bounds.maxX, point.x)),
            y: max(bounds.minY, min(bounds.maxY, point.y))
        )
    }
}

/// Owns the jiggle timer and performs jiggle cycles: tagged CGEvent cursor
/// movement within the safe area, with return-to-origin.
final class JigglerEngine {

    private let settings: SettingsStore
    private let queue = DispatchQueue(label: "com.local.MickJigger.engine", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var clickTimer: DispatchSourceTimer?
    private var settingsObserver: NSObjectProtocol?

    private(set) var isRunning = false

    init(settings: SettingsStore) {
        self.settings = settings
        // The engine reconfigures its own timers when V2 interaction settings
        // change mid-run (the coordinator only restarts on interval changes).
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleSettingsChange(notification)
        }
    }

    // MARK: - Timers

    func start() {
        stop()
        isRunning = true
        scheduleJiggleTimer()
        if settings.clickEnabled {
            startClickTimer()
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        clickTimer?.cancel()
        clickTimer = nil
        isRunning = false
    }

    /// Picks up a changed interval without changing run state.
    func restartIfRunning() {
        if isRunning { start() }
    }

    /// Fixed repeating timer normally; one-shot + reschedule when random
    /// interval mode is on, so each cycle gets fresh ±30% jitter.
    private func scheduleJiggleTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        if settings.randomInterval {
            t.schedule(deadline: .now() + nextJiggleInterval(), leeway: .seconds(1))
            t.setEventHandler { [weak self] in
                self?.performJiggleCycle()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isRunning else { return }
                    self.scheduleJiggleTimer()
                }
            }
        } else {
            let interval = TimeInterval(settings.interval)
            t.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
            t.setEventHandler { [weak self] in
                self?.performJiggleCycle()
            }
        }
        t.resume()
        timer = t
    }

    private func nextJiggleInterval() -> TimeInterval {
        let base = TimeInterval(settings.interval)
        guard settings.randomInterval else { return base }
        return base * Double.random(in: 0.7...1.3)
    }

    /// Independent click timer — separate cadence from cursor movement.
    private func startClickTimer() {
        clickTimer?.cancel()
        let interval = TimeInterval(settings.clickInterval)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
        t.setEventHandler { [weak self] in
            self?.performClickCycle()
        }
        t.resume()
        clickTimer = t
    }

    private func stopClickTimer() {
        clickTimer?.cancel()
        clickTimer = nil
    }

    private func handleSettingsChange(_ notification: Notification) {
        guard isRunning, let key = notification.userInfo?["key"] as? String else { return }
        switch key {
        case SettingsStore.Key.clickEnabled:
            settings.clickEnabled ? startClickTimer() : stopClickTimer()
        case SettingsStore.Key.clickInterval:
            if clickTimer != nil { startClickTimer() }
        case SettingsStore.Key.randomInterval:
            scheduleJiggleTimer()
        default:
            break
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        stop()
    }

    // MARK: - Jiggle cycle

    /// Cursor position (CG space), safe-area bounds, and movement distance,
    /// read on the main thread — AppKit screen geometry is not safe to touch
    /// from the engine queue. Returns nil when no screen is available.
    private func currentCursorContext() -> (origin: CGPoint, bounds: CGRect, distance: CGFloat)? {
        var result: (CGPoint, CGRect, CGFloat)?
        DispatchQueue.main.sync { [settings] in
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            let origin = Self.cocoaToCGPoint(NSEvent.mouseLocation)
            let bounds = SafeArea(settings: settings).cgBounds(for: screen)
            result = (origin, bounds, CGFloat(settings.movementDistance))
        }
        return result
    }

    private func performJiggleCycle() {
        // Guard 1: skip the cycle entirely if real HID input occurred within
        // the last 3 seconds — the "pause when user is active" safety guard.
        guard PollingLoop.physicalIdleSeconds() >= 3.0 else { return }

        // Guard 2: never attempt a CGEvent post without permission.
        guard AccessibilityPermission.isGranted else { return }

        guard let (cgOrigin, bounds, distance) = currentCursorContext() else { return }

        // Guard 3: if the cursor is already outside the safe area
        // (e.g. user left it on a toolbar), skip this tick.
        guard bounds.contains(cgOrigin) else { return }

        // Compute target within safe area bounds.
        var target = CGPoint(
            x: cgOrigin.x + CGFloat.random(in: -distance...distance),
            y: cgOrigin.y + CGFloat.random(in: -distance...distance)
        )
        target.x = max(bounds.minX, min(bounds.maxX, target.x))
        target.y = max(bounds.minY, min(bounds.maxY, target.y))

        // Ensure the cycle always produces actual movement.
        if target == cgOrigin {
            target.x = cgOrigin.x + distance <= bounds.maxX
                ? cgOrigin.x + distance
                : cgOrigin.x - distance
        }

        postMouseMove(to: target)
        Thread.sleep(forTimeInterval: 0.15)
        postMouseMove(to: cgOrigin)

        // V2 opt-in: net-zero scroll (down then up) after the cursor is back
        // at origin, same safe-area constraint as the movement itself.
        if settings.scrollEnabled {
            performScroll()
        }
    }

    /// V2 opt-in: single left-click at the current cursor position, on its own
    /// independent timer. Fires only within the safe area and only when the
    /// user has been idle — same guards as the jiggle cycle.
    private func performClickCycle() {
        guard settings.clickEnabled else { return }
        guard PollingLoop.physicalIdleSeconds() >= 3.0 else { return }
        guard AccessibilityPermission.isGranted else { return }
        guard let (cgOrigin, bounds, _) = currentCursorContext() else { return }
        guard bounds.contains(cgOrigin) else { return }

        let source = taggedSource()
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: cgOrigin,
            mouseButton: .left
        )
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        down?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.06)
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: cgOrigin,
            mouseButton: .left
        )
        up?.setIntegerValueField(.mouseEventClickState, value: 1)
        up?.post(tap: .cghidEventTap)
    }

    /// Net-zero scroll: 3 lines down, then 3 lines up. The cursor position and
    /// total scroll delta are unchanged after the gesture.
    private func performScroll() {
        let source = taggedSource()
        let down = CGEvent(
            scrollWheelEvent2Source: source,
            units: .line, wheelCount: 1,
            wheel1: -3, wheel2: 0, wheel3: 0
        )
        down?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        let up = CGEvent(
            scrollWheelEvent2Source: source,
            units: .line, wheelCount: 1,
            wheel1: 3, wheel2: 0, wheel3: 0
        )
        up?.post(tap: .cghidEventTap)
    }

    /// CGEventSource tagged with our synthetic marker — used by every event
    /// this app posts (move, click, scroll).
    private func taggedSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = kMickJiggerSyntheticTag
        return source
    }

    /// Posts a mouse-moved CGEvent from the tagged source.
    private func postMouseMove(to point: CGPoint) {
        let event = CGEvent(
            mouseEventSource: taggedSource(),
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
    }

    // MARK: - Coordinates

    /// Cocoa (bottom-left origin) → CGEvent (top-left origin).
    static func cocoaToCGPoint(_ point: NSPoint) -> CGPoint {
        let screenHeight = NSScreen.screens
            .map { $0.frame.maxY }
            .max() ?? 0
        return CGPoint(x: point.x, y: screenHeight - point.y)
    }
}
