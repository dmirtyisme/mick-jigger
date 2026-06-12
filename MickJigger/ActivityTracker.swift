import AppKit
import CoreGraphics
import QuartzCore

// MARK: - Shared types

/// Kinds of real user input forwarded to the session detector.
enum RealEventKind {
    case click
    case doubleClick
    case scroll
    case move
}

/// In-memory accumulator for activity counters between database flushes.
/// "Real" = physical user input; "synthetic" = events tagged with
/// `kMickJiggerSyntheticTag` posted by JigglerEngine.
struct ActivityDeltas {
    var realClicks = 0
    var realDoubleClicks = 0
    var realScrolls = 0
    var realDistancePx = 0.0
    var synEvents = 0           // synthetic cursor moves
    var synClicks = 0
    var synScrolls = 0
    var synDistancePx = 0.0
    var maxSpeedPxPerSec = 0.0
    var lastActivity: Date?
    /// Real event count per hour of day — feeds the Activity Timeline
    /// and "most active hour" insight.
    var hourBins = [Int](repeating: 0, count: 24)

    var isEmpty: Bool {
        realClicks == 0 && realDoubleClicks == 0 && realScrolls == 0
            && realDistancePx == 0 && synEvents == 0 && synClicks == 0
            && synScrolls == 0 && synDistancePx == 0 && lastActivity == nil
    }
}

/// One sampled real cursor position for the Trail view. Coordinates are in
/// CGEvent global desktop space (top-left origin).
struct TrailPoint {
    let x: Double
    let y: Double
    /// Cursor speed at this sample in px/s (0 when unknown).
    let speed: Double
    /// Seconds since reference date — used to break the trail across idle gaps.
    let time: TimeInterval
}

// MARK: - ActivityService (module entry point)

/// Facade wiring tracker → detector → store. The only object the rest of the
/// app talks to: AppDelegate calls `start()`/`stop()`, the popover reads
/// `todaySnapshot()` and calls `showActivityWindow()`.
///
/// Permission flow mirrors the Accessibility flow: never prompts at launch;
/// tracking starts silently if Input Monitoring is already granted, otherwise
/// the Activity window shows an inline prompt with a System Settings link.
final class ActivityService {

    static let shared = ActivityService()

    let store: ActivityStore
    let tracker: ActivityTracker
    let detector: SessionDetector

    private var flushTimer: Timer?
    private var windowController: ActivityWindowController?

    private(set) var isTracking = false

    private init() {
        store = ActivityStore()
        tracker = ActivityTracker()
        detector = SessionDetector()
        tracker.onRealEvent = { [weak self] kind, distance, date in
            self?.detector.registerRealEvent(kind: kind, distancePx: distance, at: date)
        }
        detector.onSessionEnd = { [weak self] session in
            self?.store.record(session: session)
        }
    }

    /// Starts tracking if Input Monitoring is granted. Safe to call repeatedly.
    @discardableResult
    func start() -> Bool {
        guard !isTracking else { return true }
        guard InputMonitoringPermission.isGranted else { return false }
        guard tracker.startTap() else { return false }
        detector.start()
        isTracking = true
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.flush()
        }
        return true
    }

    /// Flushes pending counters, closes any open session, and tears down the tap.
    func stop() {
        guard isTracking else { return }
        flush()
        if let open = detector.closeOpenSession() {
            store.record(session: open)
        }
        detector.stop()
        tracker.stopTap()
        flushTimer?.invalidate()
        flushTimer = nil
        isTracking = false
    }

    /// Moves pending in-memory counters into the daily SQLite aggregate.
    func flush() {
        let deltas = tracker.takeDeltas()
        guard !deltas.isEmpty else { return }
        store.addDailyDeltas(deltas, day: ActivityStore.dayKey(Date()))
    }

    // MARK: Activity window

    func showActivityWindow() {
        if windowController == nil {
            windowController = ActivityWindowController(service: self)
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Today's sampled real cursor positions for the Trail tab.
    func trailPoints() -> [TrailPoint] {
        tracker.trailSnapshot()
    }

    // MARK: Aggregated stats

    struct TodayStats {
        var clicks = 0
        var doubleClicks = 0
        var scrolls = 0
        var distancePx = 0.0
        var synEvents = 0
        var synClicks = 0
        var synScrolls = 0
        var synDistancePx = 0.0
        var maxSpeedPxPerSec = 0.0
        var activeSeconds = 0.0
        var idleSeconds = 0.0
        var longestSessionSeconds = 0.0
        var lastActivity: Date?
        var hourBins = [Int](repeating: 0, count: 24)
        var score = 0
        var firstInput: Date?
        var lastSessionEnd: Date?
    }

    /// Today's totals: persisted daily row + unflushed deltas + live session.
    func todaySnapshot(now: Date = Date()) -> TodayStats {
        var stats = TodayStats()
        let startOfDay = Calendar.current.startOfDay(for: now)

        if let row = store.dailyRow(day: ActivityStore.dayKey(now)) {
            stats.clicks = row.realClicks
            stats.doubleClicks = row.realDoubleClicks
            stats.scrolls = row.realScrolls
            stats.distancePx = row.realDistancePx
            stats.synEvents = row.synEvents
            stats.synClicks = row.synClicks
            stats.synScrolls = row.synScrolls
            stats.synDistancePx = row.synDistancePx
            stats.maxSpeedPxPerSec = row.maxSpeedPxPerSec
            stats.lastActivity = row.lastActivity
            stats.hourBins = row.hourBins
        }

        let pending = tracker.peekDeltas()
        stats.clicks += pending.realClicks
        stats.doubleClicks += pending.realDoubleClicks
        stats.scrolls += pending.realScrolls
        stats.distancePx += pending.realDistancePx
        stats.synEvents += pending.synEvents
        stats.synClicks += pending.synClicks
        stats.synScrolls += pending.synScrolls
        stats.synDistancePx += pending.synDistancePx
        stats.maxSpeedPxPerSec = max(stats.maxSpeedPxPerSec, pending.maxSpeedPxPerSec)
        if let pendingLast = pending.lastActivity {
            stats.lastActivity = max(stats.lastActivity ?? .distantPast, pendingLast)
        }
        for i in 0..<24 { stats.hourBins[i] += pending.hourBins[i] }

        // Sessions: closed sessions overlapping today, clipped to today.
        let sessions = store.sessions(from: startOfDay, to: now)
        for session in sessions {
            let clippedStart = max(session.start, startOfDay)
            stats.activeSeconds += session.end.timeIntervalSince(clippedStart)
            stats.longestSessionSeconds = max(stats.longestSessionSeconds, session.duration)
            stats.lastSessionEnd = max(stats.lastSessionEnd ?? .distantPast, session.end)
            stats.firstInput = min(stats.firstInput ?? .distantFuture, clippedStart)
        }
        // Live (still-open) session.
        if let open = detector.openSession(now: now) {
            let clippedStart = max(open.start, startOfDay)
            let liveDuration = open.lastInput.timeIntervalSince(clippedStart)
            stats.activeSeconds += max(0, liveDuration)
            stats.longestSessionSeconds = max(stats.longestSessionSeconds, max(0, liveDuration))
            stats.firstInput = min(stats.firstInput ?? .distantFuture, clippedStart)
            stats.lastSessionEnd = nil  // day hasn't "ended" — session still running
        }

        stats.idleSeconds = max(0, now.timeIntervalSince(startOfDay) - stats.activeSeconds)
        stats.score = Self.activityScore(
            distancePx: stats.distancePx,
            clicks: stats.clicks,
            scrolls: stats.scrolls,
            activeSeconds: stats.activeSeconds)
        return stats
    }

    struct PeriodStats {
        var clicks = 0
        var doubleClicks = 0
        var scrolls = 0
        var distancePx = 0.0
        var synEvents = 0
        var synClicks = 0
        var synScrolls = 0
        var synDistancePx = 0.0
        var activeSeconds = 0.0
        var sessionCount = 0
        var longestSessionSeconds = 0.0
        var daysWithData = 0
        var avgActiveSecondsPerDay = 0.0
        var avgScore = 0
        /// Per-day rows (day key, distance px, clicks, active seconds, score) — newest first.
        var perDay: [(day: String, distancePx: Double, clicks: Int, activeSeconds: Double, score: Int)] = []
    }

    /// Aggregate over the last `days` calendar days (including today), or all
    /// time when `days` is nil. Includes unflushed in-memory deltas for today.
    func periodStats(lastDays days: Int?, now: Date = Date()) -> PeriodStats {
        var stats = PeriodStats()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        let rows: [ActivityStore.DailyRow]
        let sessionsFrom: Date
        if let days {
            let from = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday)!
            rows = store.dailyRows(from: ActivityStore.dayKey(from), to: ActivityStore.dayKey(now))
            sessionsFrom = from
        } else {
            rows = store.allDailyRows()
            sessionsFrom = .distantPast
        }

        var byDay: [String: (distance: Double, clicks: Int)] = [:]
        for row in rows {
            stats.clicks += row.realClicks
            stats.doubleClicks += row.realDoubleClicks
            stats.scrolls += row.realScrolls
            stats.distancePx += row.realDistancePx
            stats.synEvents += row.synEvents
            stats.synClicks += row.synClicks
            stats.synScrolls += row.synScrolls
            stats.synDistancePx += row.synDistancePx
            byDay[row.day] = (row.realDistancePx, row.realClicks)
        }

        // Fold in unflushed counters for today.
        let pending = tracker.peekDeltas()
        if !pending.isEmpty {
            stats.clicks += pending.realClicks
            stats.doubleClicks += pending.realDoubleClicks
            stats.scrolls += pending.realScrolls
            stats.distancePx += pending.realDistancePx
            stats.synEvents += pending.synEvents
            stats.synClicks += pending.synClicks
            stats.synScrolls += pending.synScrolls
            stats.synDistancePx += pending.synDistancePx
            let todayKey = ActivityStore.dayKey(now)
            var today = byDay[todayKey] ?? (0, 0)
            today.distance += pending.realDistancePx
            today.clicks += pending.realClicks
            byDay[todayKey] = today
        }

        // Sessions grouped per day for active time.
        var activeByDay: [String: TimeInterval] = [:]
        var sessions = store.sessions(from: sessionsFrom, to: now)
        if let open = detector.openSession(now: now) {
            sessions.append(ActivitySession(
                start: open.start, end: open.lastInput,
                clicks: 0, scrolls: 0, distancePx: 0))
        }
        for session in sessions {
            stats.sessionCount += 1
            stats.activeSeconds += session.duration
            stats.longestSessionSeconds = max(stats.longestSessionSeconds, session.duration)
            let key = ActivityStore.dayKey(session.start)
            activeByDay[key, default: 0] += session.duration
        }

        let allDays = Set(byDay.keys).union(activeByDay.keys)
        stats.daysWithData = allDays.count
        if stats.daysWithData > 0 {
            stats.avgActiveSecondsPerDay = stats.activeSeconds / Double(stats.daysWithData)
        }

        var scoreSum = 0
        for day in allDays.sorted(by: >) {
            let counters = byDay[day] ?? (0, 0)
            let active = activeByDay[day] ?? 0
            let score = Self.activityScore(
                distancePx: counters.distance, clicks: counters.clicks,
                scrolls: 0, activeSeconds: active)
            scoreSum += score
            stats.perDay.append((day, counters.distance, counters.clicks, active, score))
        }
        if stats.daysWithData > 0 {
            stats.avgScore = scoreSum / stats.daysWithData
        }
        return stats
    }

    struct PersonalRecords {
        var maxDistanceDay: (day: String, distancePx: Double)?
        var maxClicksDay: (day: String, clicks: Int)?
        var longestSession: ActivitySession?
        var mostActiveDay: (day: String, score: Int)?
    }

    func personalRecords() -> PersonalRecords {
        var records = PersonalRecords()
        records.maxDistanceDay = store.maxDistanceDay()
        records.maxClicksDay = store.maxClicksDay()
        records.longestSession = store.longestSessionEver()
        // Most active day = highest daily activity score.
        let all = periodStats(lastDays: nil)
        if let best = all.perDay.max(by: { $0.score < $1.score }), best.score > 0 {
            records.mostActiveDay = (best.day, best.score)
        }
        return records
    }

    /// Insight strings for the Today tab (per ACTIVITY_TRACKING.md examples).
    func insightsToday(now: Date = Date()) -> [String] {
        var insights: [String] = []
        let today = todaySnapshot(now: now)

        if today.distancePx > 0 {
            insights.append("Today your cursor traveled \(Self.formatDistance(px: today.distancePx)).")
            let yesterdayKey = ActivityStore.dayKey(
                Calendar.current.date(byAdding: .day, value: -1, to: now)!)
            if let yesterday = store.dailyRow(day: yesterdayKey), yesterday.realDistancePx > 0 {
                let change = (today.distancePx - yesterday.realDistancePx)
                    / yesterday.realDistancePx * 100
                let direction = change >= 0 ? "more" : "less"
                insights.append(String(
                    format: "That's %.0f%% %@ than yesterday.", abs(change), direction))
            }
        }
        if let peak = today.hourBins.enumerated().max(by: { $0.element < $1.element }),
           peak.element > 0 {
            insights.append(String(
                format: "Most active hour: %02d:00–%02d:00.", peak.offset, (peak.offset + 1) % 24))
        }
        if today.longestSessionSeconds > 60 {
            insights.append(
                "Longest continuous session: \(Self.formatDuration(today.longestSessionSeconds)).")
        }
        return insights
    }

    // MARK: Activity Score

    /// Daily normalization targets — a day hitting all four targets scores 100.
    /// Weights per spec: distance 40%, clicks 30%, scrolls 20%, session 10%.
    enum ScoreTarget {
        static let distancePx = 5_000.0 * 1_000 / 0.2646  // ≈5 km in px at ~96 dpi
        static let clicks = 5_000.0
        static let scrolls = 1_000.0
        static let activeSeconds = 6.0 * 3600
    }

    static func activityScore(
        distancePx: Double, clicks: Int, scrolls: Int, activeSeconds: Double
    ) -> Int {
        let d = min(distancePx / ScoreTarget.distancePx, 1.0)
        let c = min(Double(clicks) / ScoreTarget.clicks, 1.0)
        let s = min(Double(scrolls) / ScoreTarget.scrolls, 1.0)
        let t = min(activeSeconds / ScoreTarget.activeSeconds, 1.0)
        return Int((0.4 * d + 0.3 * c + 0.2 * s + 0.1 * t) * 100.0)
    }

    // MARK: Formatting helpers

    /// Pixels → physical meters using the main display's real dimensions,
    /// falling back to ~96 dpi when unavailable.
    static func metersFromPixels(_ px: Double) -> Double {
        let display = CGMainDisplayID()
        let sizeMM = CGDisplayScreenSize(display)
        let pixelsWide = Double(CGDisplayPixelsWide(display))
        guard sizeMM.width > 0, pixelsWide > 0 else {
            return px * 0.2646 / 1000  // 96 dpi: 1 px ≈ 0.2646 mm
        }
        let mmPerPixel = Double(sizeMM.width) / pixelsWide
        return px * mmPerPixel / 1000
    }

    static func formatDistance(px: Double) -> String {
        let meters = metersFromPixels(px)
        if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
        return String(format: "%.0f m", meters)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - ActivityTracker

/// Passive (listen-only) CGEventTap observing session-wide mouse input.
/// Events from JigglerEngine's tagged source are classified as synthetic via
/// `.eventSourceUserData == kMickJiggerSyntheticTag`; everything else is
/// real user input. Requires Input Monitoring permission.
final class ActivityTracker {

    /// Real input callback for SessionDetector: (kind, distance delta px, time).
    var onRealEvent: ((RealEventKind, Double, Date) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var pending = ActivityDeltas()
    private var lastCursorPosition: CGPoint?
    private var lastRealMoveTimestamp: UInt64?

    /// Sampled real cursor positions for the Trail view, accumulated for the
    /// current day and cleared at the first sample after midnight.
    private var trail: [TrailPoint] = []
    private var trailDayKey = ActivityStore.dayKey(Date())
    /// Skip samples closer than this to the previous one (px).
    private static let trailMinSampleDistance = 3.0
    /// Decimation threshold: above this the buffer is halved (every 2nd point),
    /// which preserves the trail's shape while bounding memory.
    private static let trailMaxPoints = 60_000

    var isTapActive: Bool { tap != nil }

    /// Creates and installs the listen-only tap on the main run loop.
    /// Returns false when Input Monitoring permission is missing (tap
    /// creation fails) — caller decides how to surface that.
    @discardableResult
    func startTap() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let tracker = Unmanaged<ActivityTracker>.fromOpaque(refcon).takeUnretainedValue()
                tracker.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        return true
    }

    func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }

    /// Returns accumulated counters and resets them (called by the flush timer).
    func takeDeltas() -> ActivityDeltas {
        defer { pending = ActivityDeltas() }
        return pending
    }

    /// Non-destructive read for live UI (popover quick stats, window refresh).
    func peekDeltas() -> ActivityDeltas {
        pending
    }

    // MARK: Event handling (main run loop)

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables taps that stall or when secure input starts.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let isSynthetic =
            event.getIntegerValueField(.eventSourceUserData) == kMickJiggerSyntheticTag
        let now = Date()

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if isSynthetic {
                pending.synClicks += 1
            } else {
                pending.realClicks += 1
                let clickState = event.getIntegerValueField(.mouseEventClickState)
                let isDouble = clickState == 2
                if isDouble { pending.realDoubleClicks += 1 }
                noteRealActivity(at: now)
                onRealEvent?(isDouble ? .doubleClick : .click, 0, now)
            }

        case .scrollWheel:
            if isSynthetic {
                pending.synScrolls += 1
            } else {
                pending.realScrolls += 1
                noteRealActivity(at: now)
                onRealEvent?(.scroll, 0, now)
            }

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            let position = event.location
            var distance = 0.0
            if let last = lastCursorPosition {
                distance = hypot(position.x - last.x, position.y - last.y)
            }
            // Cursor position is shared between real and synthetic movement;
            // track it globally and attribute each delta to its event's class.
            lastCursorPosition = position

            if isSynthetic {
                pending.synEvents += 1
                pending.synDistancePx += distance
            } else {
                pending.realDistancePx += distance
                let speed = updateSpeed(distance: distance, timestamp: event.timestamp)
                appendTrailPoint(position: position, speed: speed ?? 0, now: now)
                noteRealActivity(at: now)
                onRealEvent?(.move, distance, now)
            }

        default:
            break
        }
    }

    private func noteRealActivity(at date: Date) {
        pending.lastActivity = date
        let hour = Calendar.current.component(.hour, from: date)
        pending.hourBins[hour] += 1
    }

    /// Updates the max-speed counter and returns the instantaneous speed (px/s)
    /// when it can be computed, nil for stale gaps and teleport artifacts.
    @discardableResult
    private func updateSpeed(distance: Double, timestamp: UInt64) -> Double? {
        defer { lastRealMoveTimestamp = timestamp }
        guard let last = lastRealMoveTimestamp, timestamp > last else { return nil }
        let dt = Double(timestamp - last) / 1_000_000_000  // ns → s
        // Ignore stale gaps and teleport artifacts (display switches etc.).
        guard dt > 0, dt < 0.5 else { return nil }
        let speed = distance / dt
        guard speed < 50_000 else { return nil }
        pending.maxSpeedPxPerSec = max(pending.maxSpeedPxPerSec, speed)
        return speed
    }

    // MARK: Cursor trail

    /// Today's sampled real cursor positions (empty right after midnight).
    func trailSnapshot() -> [TrailPoint] {
        guard ActivityStore.dayKey(Date()) == trailDayKey else { return [] }
        return trail
    }

    private func appendTrailPoint(position: CGPoint, speed: Double, now: Date) {
        let key = ActivityStore.dayKey(now)
        if key != trailDayKey {
            trail.removeAll()
            trailDayKey = key
        }
        if let last = trail.last,
           hypot(position.x - last.x, position.y - last.y) < Self.trailMinSampleDistance {
            return
        }
        trail.append(TrailPoint(
            x: position.x, y: position.y,
            speed: speed, time: now.timeIntervalSinceReferenceDate))
        if trail.count > Self.trailMaxPoints {
            trail = stride(from: 0, to: trail.count, by: 2).map { trail[$0] }
        }
    }

    deinit {
        stopTap()
    }
}
