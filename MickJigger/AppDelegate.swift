import AppKit

/// Coordinator: owns the state machine and wires the engine, polling loop,
/// and status item together. State transitions follow PRODUCT_SPEC.md.
final class AppDelegate: NSObject, NSApplicationDelegate, JigglerControlling {

    private let settings = SettingsStore()
    private lazy var engine = JigglerEngine(settings: settings)
    private let pollingLoop = PollingLoop()
    private var statusItemController: StatusItemController!
    private let hotkeyManager = HotkeyManager()
    private lazy var aboutWindowController = AboutWindowController()

    private(set) var state: JigglerState = .inactive
    private(set) var permissionWarningVisible = false

    /// True while the screen is locked or displays are asleep — jiggling is
    /// paused but the logical state is preserved.
    private var isJigglePaused = false

    /// Polls AXIsProcessTrusted every 5s while in an active state, so a
    /// mid-session permission revocation stops the app instead of letting
    /// CGEvent posts silently fail.
    private var permissionWatchTimer: Timer?

    private var lastAppliedInterval = 0

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(controller: self, settings: settings)
        statusItemController.onRightClick = { [weak self] in self?.handleRightClick() }

        hotkeyManager.onToggle = { [weak self] in self?.handleRightClick() }
        hotkeyManager.onToggleMonitor = { [weak self] in self?.handleHotkeyMonitor() }
        hotkeyManager.register()

        pollingLoop.onTick = { [weak self] idle in self?.handlePollTick(idle: idle) }

        lastAppliedInterval = settings.interval
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange(_:)),
            name: .settingsDidChange, object: nil)

        registerSystemNotifications()

        // Active state is never persisted: start INACTIVE, or MONITORING
        // if auto-start was previously enabled — no user interaction needed.
        transition(to: settings.autoStartEnabled ? .monitoring : .inactive)

        // Activity tracking module: silent no-op unless Input Monitoring is
        // already granted (its inline prompt lives in the Activity window).
        ActivityService.shared.start()

        buildAppMenu()
    }

    private func buildAppMenu() {
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(
            title: "About Mick Jigger…",
            action: #selector(showAbout),
            keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit Mick Jigger",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenu.addItem(quitItem)

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        let menuBar = NSMenu()
        menuBar.addItem(appMenuItem)
        NSApp.mainMenu = menuBar
    }

    @objc private func showAbout() {
        aboutWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActivityService.shared.stop()
        engine.stop()
        pollingLoop.stop()
    }

    // MARK: - State machine

    private func transition(to newState: JigglerState) {
        state = newState

        if state.isActive && !isJigglePaused {
            engine.start()
        } else {
            engine.stop()
        }

        // Polling runs only in MONITORING / ACTIVE (auto) — no CPU spent on a
        // feature the user hasn't enabled.
        if state.needsPollingLoop {
            pollingLoop.start()
        } else {
            pollingLoop.stop()
        }

        if state.isActive {
            startPermissionWatch()
        } else {
            stopPermissionWatch()
        }

        publishStateChange()
    }

    private func publishStateChange() {
        statusItemController.update(state: state, permissionWarning: permissionWarningVisible)
        NotificationCenter.default.post(name: .jigglerStateDidChange, object: self)
    }

    // MARK: - Click / hotkey handlers

    /// Right click + ⌥⌘J: toggle active ↔ inactive.
    private func handleRightClick() {
        if state.isActive {
            requestDeactivate()
        } else {
            requestActivateManual()
        }
    }

    /// ⌥⌘M: toggle monitoring on/off.
    private func handleHotkeyMonitor() {
        autoStartToggled(state != .monitoring)
    }

    private func handleLeftClick() {
        switch state {
        case .inactive:
            requestActivateManual()
        case .monitoring:
            // User is clearly trying to activate — don't disable auto-start.
            requestActivateManual()
        case .activeManual:
            requestDeactivate()
        case .activeAuto:
            // Explicit click is a clear intent to stop: go INACTIVE, not
            // MONITORING. Auto-start is switched off so the app doesn't
            // silently re-arm; the user can re-enable it from the popover.
            settings.autoStartEnabled = false
            transition(to: .inactive)
        }
    }

    // MARK: - JigglerControlling

    func requestActivateManual() {
        guard AccessibilityPermission.isGranted else {
            // Activation blocked: inline prompt with System Settings link.
            permissionWarningVisible = true
            publishStateChange()
            statusItemController.showPopover()
            return
        }
        permissionWarningVisible = false
        transition(to: .activeManual)
    }

    func requestDeactivate() {
        switch state {
        case .activeManual:
            // Auto-start logic takes over once the user deactivates manually.
            transition(to: settings.autoStartEnabled ? .monitoring : .inactive)
        case .activeAuto:
            settings.autoStartEnabled = false
            transition(to: .inactive)
        case .monitoring, .inactive:
            transition(to: .inactive)
        }
    }

    func autoStartToggled(_ enabled: Bool) {
        settings.autoStartEnabled = enabled
        if enabled {
            // From INACTIVE start watching; if ACTIVE (manual), monitoring
            // takes over only after the user deactivates manually.
            if state == .inactive {
                transition(to: .monitoring)
            }
        } else {
            if state == .monitoring || state == .activeAuto {
                transition(to: .inactive)
            }
        }
    }

    func recheckPermission() {
        if permissionWarningVisible && AccessibilityPermission.isGranted {
            permissionWarningVisible = false
            publishStateChange()
        }
    }

    // MARK: - Polling loop (auto-start / auto-stop)

    private func handlePollTick(idle: TimeInterval) {
        switch state {
        case .monitoring:
            if idle >= TimeInterval(settings.autoStartThreshold) {
                guard AccessibilityPermission.isGranted else {
                    // Silent block + visible warning; never attempt the post.
                    if !permissionWarningVisible {
                        permissionWarningVisible = true
                        publishStateChange()
                    }
                    return
                }
                transition(to: .activeAuto)
            }
        case .activeAuto:
            if idle < 1.0 {
                // Real user input — stop jiggling and resume watching.
                transition(to: .monitoring)
            }
        case .inactive, .activeManual:
            break
        }
    }

    // MARK: - Settings changes

    @objc private func settingsDidChange(_ notification: Notification) {
        let interval = settings.interval
        if interval != lastAppliedInterval {
            lastAppliedInterval = interval
            engine.restartIfRunning()
        }
    }

    // MARK: - Permission revocation watch

    private func startPermissionWatch() {
        guard permissionWatchTimer == nil else { return }
        permissionWatchTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in
            guard let self, self.state.isActive else { return }
            if !AccessibilityPermission.isGranted {
                // Any active state → INACTIVE on revocation. Warn, don't crash.
                self.permissionWarningVisible = true
                self.transition(to: .inactive)
            }
        }
    }

    private func stopPermissionWatch() {
        permissionWatchTimer?.invalidate()
        permissionWatchTimer = nil
    }

    // MARK: - Sleep / wake / lock (PRODUCT_SPEC edge cases)

    private func registerSystemNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep),
                              name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked),
                                name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked),
                                name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func systemWillSleep() {
        pauseJiggling()
    }

    @objc private func systemDidWake() {
        // On wake the user is clearly present: ACTIVE (auto) → MONITORING;
        // ACTIVE (manual) resumes. Timers are restarted cleanly so they never
        // come back suspended or double-firing.
        isJigglePaused = false
        if state == .activeAuto {
            transition(to: .monitoring)
        } else {
            transition(to: state)  // re-applies engine/polling for current state
        }
    }

    @objc private func screensDidSleep() {
        pauseJiggling()
    }

    @objc private func screensDidWake() {
        resumeAfterScreenInactive()
    }

    @objc private func screenLocked() {
        pauseJiggling()
    }

    @objc private func screenUnlocked() {
        resumeAfterScreenInactive()
    }

    /// Pause jiggling without losing logical state.
    private func pauseJiggling() {
        isJigglePaused = true
        engine.stop()
    }

    /// Screen lock / display sleep ended. ACTIVE (auto) returns to MONITORING
    /// (the user is back); ACTIVE (manual) resumes jiggling.
    private func resumeAfterScreenInactive() {
        guard isJigglePaused else { return }
        isJigglePaused = false
        if state == .activeAuto {
            transition(to: .monitoring)
        } else {
            transition(to: state)
        }
    }
}
