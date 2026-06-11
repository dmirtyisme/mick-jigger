import AppKit

/// Stats window (not a popover) opened from the menu bar popover's
/// "Activity" button. Tabs: Today / Week / Month / All Time.
/// Metrics per ACTIVITY_TRACKING.md, including the Real vs Synthetic
/// breakdown and the weighted Activity Score.
final class ActivityWindowController: NSWindowController {

    private let service: ActivityService

    private let permissionBanner = NSStackView()
    private let tabs = NSSegmentedControl(
        labels: ["Today", "Week", "Month", "All Time"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let contentStack = NSStackView()
    private var refreshTimer: Timer?

    init(service: ActivityService) {
        self.service = service
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Activity"
        window.center()
        super.init(window: window)
        buildContent()
        tabs.selectedSegment = 0
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startRefreshTimer()
        refresh()
    }

    // MARK: - Layout skeleton

    private func buildContent() {
        guard let window else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        buildPermissionBanner()
        root.addArrangedSubview(permissionBanner)

        tabs.target = self
        tabs.action = #selector(tabChanged)
        root.addArrangedSubview(tabs)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let docView = NSView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(contentStack)
        scroll.documentView = docView
        root.addArrangedSubview(scroll)

        let container = NSView()
        container.addSubview(root)
        window.contentView = container

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(equalToConstant: 560),
            container.heightAnchor.constraint(equalToConstant: 660),

            scroll.widthAnchor.constraint(equalToConstant: 520),
            permissionBanner.widthAnchor.constraint(equalToConstant: 520),
            tabs.widthAnchor.constraint(equalToConstant: 520),

            docView.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: docView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor),
        ])
    }

    private func buildPermissionBanner() {
        permissionBanner.orientation = .vertical
        permissionBanner.alignment = .leading
        permissionBanner.spacing = 6
        let text = NSTextField(wrappingLabelWithString:
            "⚠ Input Monitoring access required\nActivity tracking needs Input Monitoring "
            + "permission to observe your mouse input. Nothing leaves this Mac.")
        text.font = .systemFont(ofSize: 11)
        text.textColor = .systemOrange
        let enableButton = NSButton(
            title: "Enable Activity Tracking",
            target: self, action: #selector(requestPermission))
        enableButton.bezelStyle = .rounded
        enableButton.controlSize = .small
        let settingsButton = NSButton(
            title: "Open System Settings",
            target: self, action: #selector(openSettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        let buttons = NSStackView(views: [enableButton, settingsButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        permissionBanner.addArrangedSubview(text)
        permissionBanner.addArrangedSubview(buttons)
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.refresh()
        }
    }

    @objc private func tabChanged() {
        refresh()
    }

    @objc private func requestPermission() {
        InputMonitoringPermission.request()
        service.start()
        refresh()
    }

    @objc private func openSettings() {
        InputMonitoringPermission.openSystemSettings()
    }

    func refresh() {
        // Tracking may have become possible since last look (grant landed).
        if !service.isTracking && InputMonitoringPermission.isGranted {
            service.start()
        }
        permissionBanner.isHidden = service.isTracking

        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        switch tabs.selectedSegment {
        case 0: buildTodayTab()
        case 1: buildPeriodTab(days: 7, title: "Last 7 days")
        case 2: buildMonthTab()
        default: buildAllTimeTab()
        }
    }

    // MARK: - Today

    private func buildTodayTab() {
        let stats = service.todaySnapshot()

        addSection("Today")
        let avgSpeed = stats.activeSeconds > 0
            ? stats.distancePx / stats.activeSeconds : 0
        addMetricsGrid([
            ("Clicks", ActivityService.formatCount(stats.clicks)),
            ("Double-clicks", ActivityService.formatCount(stats.doubleClicks)),
            ("Scrolls", ActivityService.formatCount(stats.scrolls)),
            ("Cursor Distance", ActivityService.formatDistance(px: stats.distancePx)),
            ("Active Time", ActivityService.formatDuration(stats.activeSeconds)),
            ("Idle Time", ActivityService.formatDuration(stats.idleSeconds)),
            ("Longest Session", ActivityService.formatDuration(stats.longestSessionSeconds)),
            ("Last Activity", stats.lastActivity.map(Self.timeString) ?? "—"),
            ("Avg Cursor Speed", String(format: "%.0f px/s", avgSpeed)),
            ("Max Cursor Speed", String(format: "%.0f px/s", stats.maxSpeedPxPerSec)),
            ("Activity Score", "\(stats.score) / 100"),
        ])

        addSection("Activity Timeline")
        let timeline = TimelineView(bins: stats.hourBins)
        contentStack.addArrangedSubview(timeline)
        timeline.widthAnchor.constraint(equalToConstant: 520).isActive = true
        var caption: [String] = []
        if let first = stats.firstInput { caption.append("Started \(Self.timeString(first))") }
        if let peak = stats.hourBins.enumerated().max(by: { $0.element < $1.element }),
           peak.element > 0 {
            caption.append(String(format: "Peak %02d:00–%02d:00", peak.offset, (peak.offset + 1) % 24))
        }
        if let end = stats.lastSessionEnd {
            caption.append("Ended \(Self.timeString(end))")
        } else if stats.firstInput != nil {
            caption.append("Session running")
        }
        if !caption.isEmpty {
            addCaption(caption.joined(separator: " · "))
        }

        addBreakdown(
            realClicks: stats.clicks, realScrolls: stats.scrolls, realDistance: stats.distancePx,
            synClicks: stats.synClicks, synScrolls: stats.synScrolls,
            synDistance: stats.synDistancePx, synMoves: stats.synEvents)

        let insights = service.insightsToday()
        if !insights.isEmpty {
            addSection("Insights")
            for line in insights { addCaption(line) }
        }
    }

    // MARK: - Week

    private func buildPeriodTab(days: Int, title: String) {
        let stats = service.periodStats(lastDays: days)

        addSection(title)
        addMetricsGrid([
            ("Active Time", ActivityService.formatDuration(stats.activeSeconds)),
            ("Cursor Distance", ActivityService.formatDistance(px: stats.distancePx)),
            ("Clicks", ActivityService.formatCount(stats.clicks)),
            ("Scrolls", ActivityService.formatCount(stats.scrolls)),
            ("Avg Active / Day", ActivityService.formatDuration(stats.avgActiveSecondsPerDay)),
            ("Avg Activity Score", "\(stats.avgScore) / 100"),
            ("Sessions", ActivityService.formatCount(stats.sessionCount)),
            ("Longest Session", ActivityService.formatDuration(stats.longestSessionSeconds)),
        ])

        addBreakdown(
            realClicks: stats.clicks, realScrolls: stats.scrolls, realDistance: stats.distancePx,
            synClicks: stats.synClicks, synScrolls: stats.synScrolls,
            synDistance: stats.synDistancePx, synMoves: stats.synEvents)

        addPerDayList(stats.perDay)
    }

    // MARK: - Month

    private func buildMonthTab() {
        buildPeriodTab(days: 30, title: "Last 30 days")

        // Trends: this 30-day window vs the previous one.
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let windowStart = calendar.date(byAdding: .day, value: -29, to: startOfToday)!
        let prevStart = calendar.date(byAdding: .day, value: -30, to: windowStart)!
        let prevEnd = calendar.date(byAdding: .day, value: -1, to: windowStart)!
        let previous = service.store.dailyRows(
            from: ActivityStore.dayKey(prevStart), to: ActivityStore.dayKey(prevEnd))

        let prevDistance = previous.reduce(0.0) { $0 + $1.realDistancePx }
        let prevClicks = previous.reduce(0) { $0 + $1.realClicks }
        let current = service.periodStats(lastDays: 30)

        addSection("Trends (vs previous 30 days)")
        addCaption(Self.trendLine("Distance", current: current.distancePx, previous: prevDistance))
        addCaption(Self.trendLine("Clicks", current: Double(current.clicks), previous: Double(prevClicks)))
    }

    private static func trendLine(_ name: String, current: Double, previous: Double) -> String {
        guard previous > 0 else { return "\(name): no earlier data to compare." }
        let change = (current - previous) / previous * 100
        let arrow = change >= 0 ? "▲" : "▼"
        return String(format: "%@: %@ %.0f%% vs previous period", name, arrow, abs(change))
    }

    // MARK: - All Time

    private func buildAllTimeTab() {
        let stats = service.periodStats(lastDays: nil)

        addSection("All Time")
        addMetricsGrid([
            ("Cursor Distance", ActivityService.formatDistance(px: stats.distancePx)),
            ("Clicks", ActivityService.formatCount(stats.clicks)),
            ("Double-clicks", ActivityService.formatCount(stats.doubleClicks)),
            ("Scrolls", ActivityService.formatCount(stats.scrolls)),
            ("Active Time", ActivityService.formatDuration(stats.activeSeconds)),
            ("Sessions", ActivityService.formatCount(stats.sessionCount)),
            ("Days Tracked", ActivityService.formatCount(stats.daysWithData)),
            ("Avg Activity Score", "\(stats.avgScore) / 100"),
        ])

        addBreakdown(
            realClicks: stats.clicks, realScrolls: stats.scrolls, realDistance: stats.distancePx,
            synClicks: stats.synClicks, synScrolls: stats.synScrolls,
            synDistance: stats.synDistancePx, synMoves: stats.synEvents)

        addSection("Personal Records")
        let records = service.personalRecords()
        if let best = records.maxDistanceDay {
            addCaption("Longest cursor distance in a day: "
                + "\(ActivityService.formatDistance(px: best.distancePx)) (\(Self.dayString(best.day)))")
        }
        if let best = records.maxClicksDay {
            addCaption("Most clicks in a day: "
                + "\(ActivityService.formatCount(best.clicks)) (\(Self.dayString(best.day)))")
        }
        if let best = records.longestSession {
            addCaption("Longest work session: "
                + "\(ActivityService.formatDuration(best.duration)) (\(Self.dayString(ActivityStore.dayKey(best.start))))")
        }
        if let best = records.mostActiveDay {
            addCaption("Most active day: \(Self.dayString(best.day)) (score \(best.score))")
        }
        if records.maxDistanceDay == nil && records.longestSession == nil {
            addCaption("No records yet — they'll appear as activity accumulates.")
        }
    }

    // MARK: - Shared section builders

    private func addSection(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        contentStack.addArrangedSubview(label)
    }

    private func addCaption(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalToConstant: 520).isActive = true
    }

    /// Two metric pairs per row: name (secondary) + value (semibold).
    private func addMetricsGrid(_ metrics: [(String, String)]) {
        let grid = NSGridView()
        grid.columnSpacing = 10
        grid.rowSpacing = 8
        var index = 0
        while index < metrics.count {
            var views: [NSView] = []
            for pair in metrics[index..<min(index + 2, metrics.count)] {
                let name = NSTextField(labelWithString: pair.0)
                name.font = .systemFont(ofSize: 11)
                name.textColor = .secondaryLabelColor
                let value = NSTextField(labelWithString: pair.1)
                value.font = .systemFont(ofSize: 13, weight: .semibold)
                views.append(name)
                views.append(value)
            }
            while views.count < 4 { views.append(NSGridCell.emptyContentView) }
            grid.addRow(with: views)
            index += 2
        }
        grid.column(at: 0).width = 130
        if grid.numberOfColumns > 2 { grid.column(at: 2).width = 130 }
        contentStack.addArrangedSubview(grid)
    }

    private func addBreakdown(
        realClicks: Int, realScrolls: Int, realDistance: Double,
        synClicks: Int, synScrolls: Int, synDistance: Double, synMoves: Int
    ) {
        addSection("Real vs Synthetic")
        let grid = NSGridView()
        grid.columnSpacing = 18
        grid.rowSpacing = 4

        func cell(_ text: String, bold: Bool = false, secondary: Bool = false) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11, weight: bold ? .semibold : .regular)
            if secondary { label.textColor = .secondaryLabelColor }
            return label
        }

        grid.addRow(with: [
            cell(""), cell("Clicks", secondary: true), cell("Scrolls", secondary: true),
            cell("Distance", secondary: true), cell("Moves", secondary: true),
        ])
        grid.addRow(with: [
            cell("Real", bold: true),
            cell(ActivityService.formatCount(realClicks)),
            cell(ActivityService.formatCount(realScrolls)),
            cell(ActivityService.formatDistance(px: realDistance)),
            cell("—"),
        ])
        grid.addRow(with: [
            cell("Synthetic", bold: true),
            cell(ActivityService.formatCount(synClicks)),
            cell(ActivityService.formatCount(synScrolls)),
            cell(ActivityService.formatDistance(px: synDistance)),
            cell(ActivityService.formatCount(synMoves)),
        ])
        grid.addRow(with: [
            cell("Combined", bold: true),
            cell(ActivityService.formatCount(realClicks + synClicks)),
            cell(ActivityService.formatCount(realScrolls + synScrolls)),
            cell(ActivityService.formatDistance(px: realDistance + synDistance)),
            cell(ActivityService.formatCount(synMoves)),
        ])
        contentStack.addArrangedSubview(grid)
    }

    private func addPerDayList(
        _ perDay: [(day: String, distancePx: Double, clicks: Int, activeSeconds: Double, score: Int)]
    ) {
        guard !perDay.isEmpty else { return }
        addSection("By Day")
        for entry in perDay {
            addCaption("\(Self.dayString(entry.day)) — "
                + "\(ActivityService.formatDistance(px: entry.distancePx)) · "
                + "\(ActivityService.formatCount(entry.clicks)) clicks · "
                + "\(ActivityService.formatDuration(entry.activeSeconds)) active · "
                + "score \(entry.score)")
        }
    }

    // MARK: - Formatting

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private static func dayString(_ dayKey: String) -> String {
        guard let date = ActivityStore.date(fromDayKey: dayKey) else { return dayKey }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}

// MARK: - Timeline view

/// 24-hour activity strip: one bar per hour, height ∝ real event count.
private final class TimelineView: NSView {

    private let bins: [Int]

    init(bins: [Int]) {
        self.bins = bins
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 72).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let barArea = NSRect(x: 0, y: 16, width: bounds.width, height: bounds.height - 20)
        let maxBin = max(bins.max() ?? 0, 1)
        let barWidth = barArea.width / 24

        for (hour, count) in bins.enumerated() {
            let x = barArea.minX + CGFloat(hour) * barWidth
            // Baseline tick for empty hours so the strip reads as a timeline.
            let height = count > 0
                ? max(3, barArea.height * CGFloat(count) / CGFloat(maxBin))
                : 1.5
            let bar = NSRect(
                x: x + 1, y: barArea.minY,
                width: barWidth - 2, height: height)
            (count > 0 ? NSColor.controlAccentColor : NSColor.separatorColor).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }

        // Hour labels.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        for hour in stride(from: 0, through: 24, by: 6) {
            let x = barArea.minX + CGFloat(hour) * barWidth
            let text = String(format: "%02d", hour % 24)
            NSAttributedString(string: text, attributes: attributes)
                .draw(at: NSPoint(x: min(x, bounds.width - 14), y: 0))
        }
    }
}
