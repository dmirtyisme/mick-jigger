import AppKit
import UniformTypeIdentifiers

final class ActivityWindowController: NSWindowController {

    private static let contentWidth: CGFloat = 520
    private static let cardPadding: CGFloat = 16
    private static let cardGap: CGFloat = 12
    private static let outerPadding: CGFloat = 20

    private static let metricIcons: [String: String] = [
        "Activity Score":    "chart.bar.fill",
        "Active Time":       "clock",
        "Clicks":            "cursorarrow.click",
        "Double-clicks":     "cursorarrow.click.2",
        "Scrolls":           "scroll",
        "Cursor Distance":   "cursorarrow.rays",
        "Idle Time":         "pause.circle",
        "Longest Session":   "timer",
        "Avg Cursor Speed":  "gauge",
        "Max Cursor Speed":  "gauge.high",
        "Last Activity":     "clock.arrow.circlepath",
        "Avg Active / Day":  "chart.bar.xaxis",
        "Avg Activity Score":"chart.bar.fill",
        "Sessions":          "repeat",
        "Days Tracked":      "calendar",
    ]

    private let service: ActivityService

    private let permissionBanner = NSView()
    private let tabs = NSSegmentedControl(
        labels: ["Today", "Week", "Month", "All Time", "Trail"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let shareButton = NSButton()
    private let trackingStatusLabel = NSTextField(labelWithString: "")
    private let contentStack = NSStackView()
    private var refreshTimer: Timer?
    private var trailView: TrailView?
    private var shouldAnimateNextRefresh = false
    private var personalRecordRows: [(label: String, value: String, symbol: String)] = []

    init(service: ActivityService) {
        self.service = service
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
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

        let effectView = NSVisualEffectView()
        effectView.material = .sidebar
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(
            top: Self.outerPadding, left: Self.outerPadding,
            bottom: Self.outerPadding, right: Self.outerPadding)
        root.translatesAutoresizingMaskIntoConstraints = false

        buildPermissionBanner()
        root.addArrangedSubview(permissionBanner)

        tabs.segmentStyle = .automatic
        tabs.target = self
        tabs.action = #selector(tabChanged)
        shareButton.image = NSImage(
            systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        shareButton.isBordered = false
        shareButton.imageScaling = .scaleProportionallyDown
        shareButton.target = self
        shareButton.action = #selector(shareClicked(_:))
        shareButton.toolTip = "Share today's activity stats"
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let headerRow = NSStackView(views: [tabs, headerSpacer, shareButton])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        root.addArrangedSubview(headerRow)

        trackingStatusLabel.font = .systemFont(ofSize: 11)
        root.addArrangedSubview(trackingStatusLabel)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Self.cardGap

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

        effectView.addSubview(root)
        let container = NSView()
        container.addSubview(effectView)
        window.contentView = container

        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            root.topAnchor.constraint(equalTo: effectView.topAnchor),
            root.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),

            container.widthAnchor.constraint(equalToConstant: 560),
            container.heightAnchor.constraint(equalToConstant: 580),

            scroll.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            permissionBanner.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            headerRow.widthAnchor.constraint(equalToConstant: Self.contentWidth),

            docView.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: docView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor),
        ])
    }

    private func buildPermissionBanner() {
        permissionBanner.wantsLayer = true
        permissionBanner.layer?.backgroundColor =
            NSColor.systemOrange.withAlphaComponent(0.1).cgColor
        permissionBanner.layer?.cornerRadius = 8

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true

        let text = NSTextField(labelWithString:
            "Activity tracking needs Input Monitoring permission — nothing leaves this Mac.")
        text.font = .systemFont(ofSize: 11)
        text.textColor = .labelColor
        text.setContentHuggingPriority(.init(1), for: .horizontal)
        text.lineBreakMode = .byTruncatingTail

        let enableButton = NSButton(
            title: "Enable", target: self, action: #selector(requestPermission))
        enableButton.bezelStyle = .rounded
        enableButton.controlSize = .mini
        let settingsButton = NSButton(
            title: "Settings", target: self, action: #selector(openSettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .mini

        let row = NSStackView(views: [icon, text, enableButton, settingsButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        permissionBanner.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: permissionBanner.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: permissionBanner.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: permissionBanner.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: permissionBanner.trailingAnchor, constant: -10),
        ])
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
        shouldAnimateNextRefresh = true
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

    @objc private func shareClicked(_ sender: NSButton) {
        let stats = service.todaySnapshot()
        let text = "Today I moved my cursor "
            + "\(ActivityService.formatDistance(px: stats.distancePx)), made "
            + "\(ActivityService.formatCount(stats.clicks)) clicks and scrolled "
            + "\(ActivityService.formatCount(stats.scrolls)) times. "
            + "Tracked by Mick Jigger."
        let picker = NSSharingServicePicker(items: [text])
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    func refresh() {
        if !service.isTracking && InputMonitoringPermission.isGranted {
            service.start()
        }
        permissionBanner.isHidden = service.isTracking
        updateTrackingStatus()

        if shouldAnimateNextRefresh {
            shouldAnimateNextRefresh = false
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                contentStack.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.rebuildTabContent()
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self?.contentStack.animator().alphaValue = 1
                })
            })
        } else {
            rebuildTabContent()
        }
    }

    private func rebuildTabContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        trailView = nil
        switch tabs.selectedSegment {
        case 0: buildTodayTab()
        case 1: buildPeriodTab(days: 7, title: "Last 7 days")
        case 2: buildMonthTab()
        case 3: buildAllTimeTab()
        default: buildTrailTab()
        }
    }

    private func updateTrackingStatus() {
        let dot: String
        let dotColor: NSColor
        let text: String
        if service.isTracking {
            dot = "●"
            dotColor = .systemGreen
            if let first = service.todaySnapshot().firstInput {
                text = " Tracking  —  started \(Self.timeString(first))"
            } else {
                text = " Tracking"
            }
        } else {
            dot = "○"
            dotColor = .systemGray
            text = " Tracking paused  —  Input Monitoring required"
        }
        let status = NSMutableAttributedString(
            string: dot,
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: dotColor])
        status.append(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        trackingStatusLabel.attributedStringValue = status
    }

    // MARK: - Today

    private func buildTodayTab() {
        let stats = service.todaySnapshot()
        addSection("Today")
        let avgSpeed = stats.activeSeconds > 0 ? stats.distancePx / stats.activeSeconds : 0
        addMetricCards([
            ("Activity Score",   "\(stats.score) / 100"),
            ("Active Time",      ActivityService.formatDuration(stats.activeSeconds)),
            ("Clicks",           ActivityService.formatCount(stats.clicks)),
            ("Double-clicks",    ActivityService.formatCount(stats.doubleClicks)),
            ("Scrolls",          ActivityService.formatCount(stats.scrolls)),
            ("Cursor Distance",  ActivityService.formatDistance(px: stats.distancePx)),
            ("Idle Time",        ActivityService.formatDuration(stats.idleSeconds)),
            ("Longest Session",  ActivityService.formatDuration(stats.longestSessionSeconds)),
            ("Avg Cursor Speed", String(format: "%.0f px/s", avgSpeed)),
            ("Max Cursor Speed", String(format: "%.0f px/s", stats.maxSpeedPxPerSec)),
            ("Last Activity",    stats.lastActivity.map(Self.timeString) ?? "—"),
        ])

        addSeparator()
        addSection("Activity Timeline")
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
        addTimelineCard(bins: stats.hourBins, caption: caption.joined(separator: "  ·  "))

        addSeparator()
        addBreakdown(
            realClicks: stats.clicks, realScrolls: stats.scrolls, realDistance: stats.distancePx,
            synClicks: stats.synClicks, synScrolls: stats.synScrolls,
            synDistance: stats.synDistancePx, synMoves: stats.synEvents)

        let insights = service.insightsToday()
        if !insights.isEmpty {
            addSeparator()
            addSection("Insights")
            let symbols = ["sparkles", "chart.line.uptrend.xyaxis", "clock", "flame"]
            for (index, line) in insights.enumerated() {
                addCallout(line, symbol: symbols[index % symbols.count])
            }
        }
    }

    // MARK: - Week

    private func buildPeriodTab(days: Int, title: String) {
        let stats = service.periodStats(lastDays: days)
        addSection(title)
        addMetricCards([
            ("Active Time",       ActivityService.formatDuration(stats.activeSeconds)),
            ("Cursor Distance",   ActivityService.formatDistance(px: stats.distancePx)),
            ("Clicks",            ActivityService.formatCount(stats.clicks)),
            ("Scrolls",           ActivityService.formatCount(stats.scrolls)),
            ("Avg Active / Day",  ActivityService.formatDuration(stats.avgActiveSecondsPerDay)),
            ("Avg Activity Score","\(stats.avgScore) / 100"),
            ("Sessions",          ActivityService.formatCount(stats.sessionCount)),
            ("Longest Session",   ActivityService.formatDuration(stats.longestSessionSeconds)),
        ])
        addSeparator()
        addBreakdown(
            realClicks: stats.clicks, realScrolls: stats.scrolls, realDistance: stats.distancePx,
            synClicks: stats.synClicks, synScrolls: stats.synScrolls,
            synDistance: stats.synDistancePx, synMoves: stats.synEvents)
        addPerDayList(stats.perDay)
    }

    // MARK: - Month

    private func buildMonthTab() {
        buildPeriodTab(days: 30, title: "Last 30 days")
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let windowStart = calendar.date(byAdding: .day, value: -29, to: startOfToday)!
        let prevStart = calendar.date(byAdding: .day, value: -30, to: windowStart)!
        let prevEnd = calendar.date(byAdding: .day, value: -1, to: windowStart)!
        let previous = service.store.dailyRows(
            from: ActivityStore.dayKey(prevStart), to: ActivityStore.dayKey(prevEnd))
        let prevDistance = previous.reduce(0.0) { $0 + $1.realDistancePx }
        let prevClicks   = previous.reduce(0)   { $0 + $1.realClicks }
        let current = service.periodStats(lastDays: 30)
        addSeparator()
        addSection("Trends (vs previous 30 days)")
        addCallout(
            Self.trendLine("Distance", current: current.distancePx, previous: prevDistance),
            symbol: current.distancePx >= prevDistance
                ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
        addCallout(
            Self.trendLine("Clicks", current: Double(current.clicks), previous: Double(prevClicks)),
            symbol: Double(current.clicks) >= Double(prevClicks)
                ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
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
        addMetricCards([
            ("Cursor Distance",   ActivityService.formatDistance(px: stats.distancePx)),
            ("Clicks",            ActivityService.formatCount(stats.clicks)),
            ("Double-clicks",     ActivityService.formatCount(stats.doubleClicks)),
            ("Scrolls",           ActivityService.formatCount(stats.scrolls)),
            ("Active Time",       ActivityService.formatDuration(stats.activeSeconds)),
            ("Sessions",          ActivityService.formatCount(stats.sessionCount)),
            ("Days Tracked",      ActivityService.formatCount(stats.daysWithData)),
            ("Avg Activity Score","\(stats.avgScore) / 100"),
        ])
        addSeparator()
        addBreakdown(
            realClicks: stats.clicks, realScrolls: stats.scrolls, realDistance: stats.distancePx,
            synClicks: stats.synClicks, synScrolls: stats.synScrolls,
            synDistance: stats.synDistancePx, synMoves: stats.synEvents)

        addSeparator()
        addSection("Personal Records")
        let records = service.personalRecords()
        personalRecordRows = []
        if let best = records.maxDistanceDay {
            personalRecordRows.append((
                "Longest cursor distance",
                "\(ActivityService.formatDistance(px: best.distancePx)) · \(Self.dayString(best.day))",
                "trophy"))
        }
        if let best = records.maxClicksDay {
            personalRecordRows.append((
                "Most clicks in a day",
                "\(ActivityService.formatCount(best.clicks)) · \(Self.dayString(best.day))",
                "trophy"))
        }
        if let best = records.longestSession {
            personalRecordRows.append((
                "Longest work session",
                "\(ActivityService.formatDuration(best.duration)) · \(Self.dayString(ActivityStore.dayKey(best.start)))",
                "trophy"))
        }
        if let best = records.mostActiveDay {
            personalRecordRows.append((
                "Most active day",
                "\(Self.dayString(best.day)) · score \(best.score)",
                "flame"))
        }
        if personalRecordRows.isEmpty {
            personalRecordRows.append((
                "No records yet",
                "They'll appear as activity accumulates.",
                "hourglass"))
        }
        addPersonalRecordsTable()
    }

    // MARK: - Trail

    private func buildTrailTab() {
        addSection("Cursor Trail — Today")
        let points = service.trailPoints()
        let trail = TrailView(points: points)
        trailView = trail
        contentStack.addArrangedSubview(trail)
        trail.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        trail.heightAnchor.constraint(equalToConstant: 330).isActive = true
        addCaption(points.isEmpty
            ? "No cursor movement recorded yet today. The trail accumulates real "
              + "(not synthetic) cursor positions and resets at midnight."
            : "\(ActivityService.formatCount(points.count)) samples · real cursor "
              + "movement only · resets at midnight")
        let saveButton = NSButton(
            title: "Save as PNG…", target: self, action: #selector(saveTrailPNG))
        saveButton.bezelStyle = .rounded
        let shareTrailButton = NSButton(
            title: "Share", target: self, action: #selector(shareTrailPNG(_:)))
        shareTrailButton.bezelStyle = .rounded
        let buttonRow = NSStackView(views: [saveButton, shareTrailButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        contentStack.addArrangedSubview(buttonRow)
    }

    @objc private func saveTrailPNG() {
        guard let window, let data = trailView?.pngData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "MickJigger-Trail-\(ActivityStore.dayKey(Date())).png"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url) } catch {
                NSLog("Trail PNG export failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func shareTrailPNG(_ sender: NSButton) {
        guard let data = trailView?.pngData(), let image = NSImage(data: data) else { return }
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    // MARK: - Section builders

    private func addSection(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        contentStack.addArrangedSubview(label)
    }

    private func addSeparator() {
        let box = NSBox()
        box.boxType = .separator
        contentStack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
    }

    private func addCaption(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
    }

    /// NSBox-backed card with rounded fill and no border.
    private func card(_ content: NSView, padding: CGFloat = ActivityWindowController.cardPadding) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6)
        box.cornerRadius = 10
        box.borderWidth = 0
        box.contentViewMargins = NSSize(width: 0, height: 0)
        box.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -padding),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -padding),
        ])
        return box
    }

    // MARK: - Metric cards

    private func addMetricCards(_ metrics: [(String, String)]) {
        var index = 0
        while index < metrics.count {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = Self.cardGap
            rowStack.distribution = .fillEqually
            for pair in metrics[index..<min(index + 2, metrics.count)] {
                rowStack.addArrangedSubview(metricCard(title: pair.0, value: pair.1))
            }
            if metrics.count - index == 1 { rowStack.addArrangedSubview(NSView()) }
            contentStack.addArrangedSubview(rowStack)
            rowStack.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
            index += 2
        }
    }

    private func metricCard(title: String, value: String) -> NSView {
        let symbolName = Self.metricIcons[title] ?? "square.dashed"
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .systemBlue

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        valueLabel.textColor = .labelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        titleLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [icon, valueLabel, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3

        let cardView = card(stack)
        cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        return cardView
    }

    // MARK: - Timeline

    private func addTimelineCard(bins: [Int], caption: String) {
        let timeline = TimelineView(bins: bins)
        let stack = NSStackView(views: [timeline])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        timeline.widthAnchor.constraint(
            equalToConstant: Self.contentWidth - 2 * Self.cardPadding).isActive = true
        if !caption.isEmpty {
            let label = NSTextField(labelWithString: caption)
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
        }
        let cardView = card(stack)
        contentStack.addArrangedSubview(cardView)
        cardView.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
    }

    // MARK: - Real vs Synthetic

    private func addBreakdown(
        realClicks: Int, realScrolls: Int, realDistance: Double,
        synClicks: Int, synScrolls: Int, synDistance: Double, synMoves: Int
    ) {
        addSection("Real vs Synthetic")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addArrangedSubview(duoBarBlock(
            name: "Clicks",
            real: Double(realClicks), syn: Double(synClicks),
            realText: ActivityService.formatCount(realClicks),
            synText:  ActivityService.formatCount(synClicks)))
        stack.addArrangedSubview(duoBarBlock(
            name: "Scrolls",
            real: Double(realScrolls), syn: Double(synScrolls),
            realText: ActivityService.formatCount(realScrolls),
            synText:  ActivityService.formatCount(synScrolls)))
        stack.addArrangedSubview(duoBarBlock(
            name: "Distance",
            real: realDistance, syn: synDistance,
            realText: ActivityService.formatDistance(px: realDistance),
            synText:  ActivityService.formatDistance(px: synDistance)))
        let movesLabel = NSTextField(labelWithString:
            "Synthetic moves: \(ActivityService.formatCount(synMoves))")
        movesLabel.font = .systemFont(ofSize: 10)
        movesLabel.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(movesLabel)
        for block in stack.arrangedSubviews where block !== movesLabel {
            block.widthAnchor.constraint(
                equalToConstant: Self.contentWidth - 2 * Self.cardPadding).isActive = true
        }
        let cardView = card(stack)
        contentStack.addArrangedSubview(cardView)
        cardView.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
    }

    /// One metric: label header + two NSLevelIndicator rows (Real / Synthetic).
    private func duoBarBlock(
        name: String, real: Double, syn: Double, realText: String, synText: String
    ) -> NSView {
        let maxValue = max(real, syn, 1)

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor

        func levelRow(tag: String, value: Double, text: String) -> NSView {
            let tagLabel = NSTextField(labelWithString: tag)
            tagLabel.font = .systemFont(ofSize: 10)
            tagLabel.textColor = .tertiaryLabelColor
            tagLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true

            let indicator = NSLevelIndicator()
            indicator.levelIndicatorStyle = .continuousCapacity
            indicator.minValue = 0
            indicator.maxValue = 1
            indicator.doubleValue = value / maxValue
            indicator.setContentHuggingPriority(.init(1), for: .horizontal)

            let valueLabel = NSTextField(labelWithString: text)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            valueLabel.textColor = .labelColor
            valueLabel.alignment = .right
            valueLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

            let row = NSStackView(views: [tagLabel, indicator, valueLabel])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            return row
        }

        let realRow = levelRow(tag: "Real",      value: real, text: realText)
        let synRow  = levelRow(tag: "Synthetic", value: syn,  text: synText)
        let block   = NSStackView(views: [nameLabel, realRow, synRow])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 4
        for row in [realRow, synRow] {
            row.widthAnchor.constraint(equalTo: block.widthAnchor).isActive = true
        }
        return block
    }

    // MARK: - Callout rows

    private func addCallout(_ text: String, symbol: String) {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        icon.contentTintColor = .systemBlue
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor

        let rowStack = NSStackView(views: [icon, label])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 10

        let cardView = card(rowStack, padding: 12)
        contentStack.addArrangedSubview(cardView)
        cardView.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
    }

    // MARK: - Personal Records table

    private func addPersonalRecordsTable() {
        let innerWidth = Self.contentWidth - 2 * Self.cardPadding

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []

        let labelCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        labelCol.width = innerWidth * 0.62
        let valueCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueCol.width = innerWidth * 0.38
        tableView.addTableColumn(labelCol)
        tableView.addTableColumn(valueCol)
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(
            equalToConstant: CGFloat(personalRecordRows.count) * 44).isActive = true

        let cardView = card(scrollView, padding: 0)
        contentStack.addArrangedSubview(cardView)
        cardView.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
    }

    // MARK: - Per-day list

    private func addPerDayList(
        _ perDay: [(day: String, distancePx: Double, clicks: Int, activeSeconds: Double, score: Int)]
    ) {
        guard !perDay.isEmpty else { return }
        addSeparator()
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
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }

    private static func dayString(_ dayKey: String) -> String {
        guard let date = ActivityStore.date(fromDayKey: dayKey) else { return dayKey }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }
}

// MARK: - NSTableView data source & delegate

extension ActivityWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        personalRecordRows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let record = personalRecordRows[row]
        let cell = NSTableCellView()

        if tableColumn?.identifier.rawValue == "label" {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: record.symbol, accessibilityDescription: nil)
            icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
            icon.contentTintColor = .systemBlue
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 20).isActive = true

            let textField = NSTextField(labelWithString: record.label)
            textField.font = .systemFont(ofSize: 12, weight: .semibold)
            textField.textColor = .labelColor
            cell.textField = textField

            let stack = NSStackView(views: [icon, textField])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        } else {
            let textField = NSTextField(labelWithString: record.value)
            textField.font = .systemFont(ofSize: 12)
            textField.textColor = .secondaryLabelColor
            textField.alignment = .right
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 44 }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}

// MARK: - TrailView

/// Day-long cursor trail rendered as a smoothed bezier on a fixed dark canvas.
private final class TrailView: NSView {

    private let points: [TrailPoint]
    private static let background = NSColor(srgbRed: 10/255, green: 10/255, blue: 15/255, alpha: 1)
    private static let gapSeconds: TimeInterval = 2.0
    private static let maxRenderPoints = 12_000

    init(points: [TrailPoint]) {
        if points.count > Self.maxRenderPoints {
            let step = points.count / Self.maxRenderPoints + 1
            self.points = stride(from: 0, to: points.count, by: step).map { points[$0] }
        } else {
            self.points = points
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        bounds.fill()
        guard points.count >= 3 else { drawEmptyMessage(); return }

        let union = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let desktop = union.isNull
            ? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            : CGRect(x: union.minX, y: 0, width: union.width, height: union.height)
        let inset: CGFloat = 14
        let scale = min(
            (bounds.width - 2 * inset) / desktop.width,
            (bounds.height - 2 * inset) / desktop.height)
        let offset = CGPoint(
            x: (bounds.width - desktop.width * scale) / 2,
            y: (bounds.height - desktop.height * scale) / 2)

        func map(_ p: TrailPoint) -> CGPoint {
            CGPoint(
                x: offset.x + (p.x - desktop.minX) * scale,
                y: offset.y + (desktop.maxY - p.y) * scale)
        }

        for i in 1..<(points.count - 1) {
            let a = points[i-1], b = points[i], c = points[i+1]
            if b.time - a.time > Self.gapSeconds || c.time - b.time > Self.gapSeconds { continue }
            let pa = map(a), pb = map(b), pc = map(c)
            let from = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
            let to   = CGPoint(x: (pb.x + pc.x) / 2, y: (pb.y + pc.y) / 2)
            let path = NSBezierPath()
            path.move(to: from)
            path.curve(
                to: to,
                controlPoint1: CGPoint(
                    x: from.x + 2/3 * (pb.x - from.x), y: from.y + 2/3 * (pb.y - from.y)),
                controlPoint2: CGPoint(
                    x: to.x + 2/3 * (pb.x - to.x),   y: to.y + 2/3 * (pb.y - to.y)))
            path.lineWidth = Self.width(forSpeed: b.speed)
            path.lineCapStyle = .round
            Self.color(forSpeed: b.speed).setStroke()
            path.stroke()
        }
    }

    private static func width(forSpeed speed: Double) -> CGFloat {
        let t = min(max(speed, 0) / 2_500, 1)
        return CGFloat(2.2 - 1.8 * t)
    }

    private static func color(forSpeed speed: Double) -> NSColor {
        let t = CGFloat(min(max(speed, 0) / 2_500, 1))
        return NSColor(srgbRed: 0.35 + 0.65 * t, green: 0.55 + 0.45 * t, blue: 1.0, alpha: 0.45)
    }

    private func drawEmptyMessage() {
        let text = "No trail yet — move the mouse."
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white.withAlphaComponent(0.3),
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()
        string.draw(at: NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2))
    }

    func pngData() -> Data? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - TimelineView

/// 24-hour activity strip: one bar per hour, height ∝ real event count.
private final class TimelineView: NSView {

    private let bins: [Int]
    private static let labelHeight: CGFloat = 16
    private static let topPadding: CGFloat = 8

    init(bins: [Int]) {
        self.bins = bins
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 120).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let barArea = NSRect(
            x: 0, y: Self.labelHeight,
            width: bounds.width,
            height: bounds.height - Self.labelHeight - Self.topPadding)
        let maxBin = max(bins.max() ?? 0, 1)
        let barWidth = barArea.width / 24

        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: barArea.minY - 1, width: bounds.width, height: 1).fill()

        for (hour, count) in bins.enumerated() {
            let x = barArea.minX + CGFloat(hour) * barWidth
            let height = count > 0
                ? max(4, barArea.height * CGFloat(count) / CGFloat(maxBin)) : 2
            let bar = NSRect(x: x + 2, y: barArea.minY, width: barWidth - 4, height: height)
            (count > 0 ? NSColor.controlAccentColor : NSColor.separatorColor).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        for hour in stride(from: 0, through: 24, by: 6) {
            let x = barArea.minX + CGFloat(hour) * barWidth
            NSAttributedString(string: String(format: "%02d", hour % 24), attributes: attributes)
                .draw(at: NSPoint(x: min(x, bounds.width - 16), y: 1))
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
