# Mick Jigger — Technical Notes

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI framework | AppKit (status item, popover) + SwiftUI (popover content) |
| Target OS | macOS 13.0+ (Ventura) |
| Distribution | Direct / DMG, not App Store |
| Build tool | Xcode 15+ |
| Dependencies | None (pure Apple frameworks only) |

---

## Project Structure

```
MickJigger/
├── App/
│   ├── MickJiggerApp.swift       — @main, AppDelegate setup
│   └── AppDelegate.swift           — NSApplicationDelegate, lifecycle
├── StatusBar/
│   ├── StatusBarController.swift   — NSStatusItem, NSPopover, icon management
│   └── MenuBarIcon.swift           — Icon rendering, four state variants
├── Engine/
│   ├── JigglerEngine.swift         — Orchestrates jiggle cycles, owns timers
│   ├── AutoStartMonitor.swift      — 1s polling loop, HID idle detection, state transitions
│   ├── CursorMover.swift           — CGEvent cursor movement with tagged source
│   └── SafeArea.swift              — Screen bounds + margin calculations
├── Settings/
│   └── AppSettings.swift           — @AppStorage wrappers, UserDefaults keys
├── UI/
│   ├── PopoverContentView.swift    — Root SwiftUI view for popover
│   ├── AutoStartView.swift         — Auto-start toggle + threshold selector
│   ├── MarginsView.swift           — Safe area margin inputs
│   └── PermissionPromptView.swift  — Accessibility permission banner
└── Resources/
    ├── Assets.xcassets             — App icon, menu bar template images (4 states)
    └── Info.plist
```

---

## Key APIs

### Cursor Movement

**`CGEvent` with mouse-moved type** — required for idle prevention:

```swift
// Requires Accessibility permission
// Generates real mouse-moved events — resets system idle timer
// Tagged source prevents self-triggering in auto-stop logic

let source = CGEventSource(stateID: .privateState)
source?.userData = kMickJiggerSyntheticTag  // e.g. 0x4D4A494747 ("MJIGG")

let event = CGEvent(mouseEventSource: source,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: targetPoint,
                    mouseButton: .left)
event?.post(tap: .cghidEventTap)
```

**Why not `CGWarpMouseCursorPosition`:**
- Moves cursor visually only
- Does NOT generate mouse events
- Does NOT reset macOS idle timer — screensaver and lock will still trigger
- Not sufficient for the product's core purpose

### Distinguishing Real vs Synthetic Input

This is the critical API that makes auto-start safe. It uses `CGEventSourceStateID` to scope the query:

| State ID | Includes |
|---|---|
| `.hidSystemState` | **Hardware only** — physical mouse, keyboard, trackpad. Does NOT include CGEvent synthetic posts. |
| `.combinedSessionState` | Hardware + all synthetic events |
| `.privateState` | Only events from the current process |

```swift
// Time since last PHYSICAL user input — synthetic events do NOT affect this counter
func physicalIdleSeconds() -> TimeInterval {
    let mouseIdle    = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
    let keyIdle      = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    let clickIdle    = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
    let scrollIdle   = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .scrollWheel)
    return min(mouseIdle, keyIdle, clickIdle, scrollIdle)
}
```

**No Accessibility permission required.** This API is available without any entitlements.

**Key guarantee:** Synthetic events posted by this app via `CGEvent` do NOT appear in `.hidSystemState` queries. Our jiggling cannot trigger auto-stop detection of our own events.

### Auto-Start Polling Loop

A 1-second `DispatchSourceTimer` runs whenever state is MONITORING or ACTIVE (auto):

```swift
// Runs only in MONITORING and ACTIVE (auto) states
// Stopped in INACTIVE and ACTIVE (manual) states
every 1.0 second:
  idle = physicalIdleSeconds()

  if state == .monitoring && idle >= autoStartThreshold:
    transition(.activeAuto)
    startJiggleTimer()

  if state == .activeAuto && idle < 1.0:
    stopJiggleTimer()
    transition(.monitoring)
```

The 1.0s threshold for detecting user return is intentional — avoids false positives from accidental brief contact with input devices.

### Jiggle Timer

```swift
// DispatchSourceTimer — more accurate than Timer under system load
private var jiggleTimer: DispatchSourceTimer?

func startJiggleTimer(interval: TimeInterval) {
    jiggleTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    jiggleTimer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
    jiggleTimer?.setEventHandler { [weak self] in
        self?.performJiggleCycle()
    }
    jiggleTimer?.resume()
}
```

### Jiggle Cycle (full sequence)

```swift
func performJiggleCycle() {
    // Guard 1: check real idle time first — skip if user is active
    guard physicalIdleSeconds() >= 3.0 else { return }

    // Guard 2: get current cursor position
    let origin = NSEvent.mouseLocation  // Cocoa coordinates
    let cgOrigin = cocoaToCGPoint(origin)

    // Guard 3: verify cursor is within safe area
    guard safeArea.contains(cgOrigin) else { return }

    // Compute target within safe area
    let offset = CGPoint(x: randomOffset(±distance), y: randomOffset(±distance))
    let target = safeArea.clamp(cgOrigin + offset)

    // Move to target (tagged synthetic event)
    postMouseMove(to: target)
    Thread.sleep(forTimeInterval: 0.15)

    // Return to origin
    postMouseMove(to: cgOrigin)
}
```

### Safe Area Calculation

```swift
struct SafeArea {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat

    // Returns rect in CGEvent coordinate space (top-left origin)
    func cgBounds(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        // NSScreen uses bottom-left origin on primary display
        // For primary display: cgY = screenHeight - cocoaY
        let screenHeight = NSScreen.screens
            .map { $0.frame.maxY }
            .max() ?? frame.height

        let cgTop    = screenHeight - frame.maxY + top
        let cgBottom = screenHeight - frame.minY - bottom

        return CGRect(
            x: frame.minX + left,
            y: cgTop,
            width: frame.width - left - right,
            height: cgBottom - cgTop
        )
    }

    func contains(_ point: CGPoint) -> Bool {
        let bounds = cgBounds(for: NSScreen.main ?? NSScreen.screens[0])
        return bounds.contains(point)
    }

    func clamp(_ point: CGPoint) -> CGPoint {
        let bounds = cgBounds(for: NSScreen.main ?? NSScreen.screens[0])
        return CGPoint(
            x: max(bounds.minX, min(bounds.maxX, point.x)),
            y: max(bounds.minY, min(bounds.maxY, point.y))
        )
    }
}
```

**Warning:** macOS uses two coordinate systems. `NSScreen.frame` and `NSEvent.mouseLocation` use bottom-left origin; `CGEvent` uses top-left origin. All safe area bounds must be computed in CGEvent space. This is the most common source of bugs in cursor manipulation apps.

### Accessibility Permission

```swift
func isAccessibilityGranted() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// On macOS 13+ — open System Settings directly (more reliable than in-app prompt)
func openAccessibilitySettings() {
    NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    )
}
```

---

## Global Keyboard Shortcuts (V1.1)

### Technical approach

Since Accessibility permission is already required and granted, use `NSEvent.addGlobalMonitorForEvents`:

```swift
// Requires Accessibility permission — already granted
var globalMonitor: Any?

func registerHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == keyCode && event.modifierFlags.contains(modifiers) {
            DispatchQueue.main.async { handler() }
        }
    }
}

func unregisterHotkey() {
    if let monitor = globalMonitor {
        NSEvent.removeMonitor(monitor)
        globalMonitor = nil
    }
}
```

**Default shortcuts:**
- `⌥⌘J` — toggle ACTIVE (manual) ↔ INACTIVE
- `⌥⌘M` — toggle MONITORING (auto-start) on/off

**Rationale for defaults:** `⌥⌘` modifier combination is rarely used by other apps. `J` for "Jiggle", `M` for "Monitor". Both are configurable.

### Alternative: Carbon RegisterEventHotKey

```c
// Does NOT require Accessibility permission
// Works reliably across macOS versions
// Useful if Accessibility is ever refused before hotkey registration
EventHotKeyRef hotKeyRef;
EventHotKeyID hotKeyID = { 'MJIG', 1 };
RegisterEventHotKey(kVK_ANSI_J, cmdKey | optionKey, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef);
```

Carbon approach is a fallback option. For V1.1, `NSEvent.addGlobalMonitorForEvents` is preferred (pure Swift, no bridging).

### Hotkey registration lifecycle

- Register on app launch (after Accessibility confirmed)
- Unregister on `applicationWillTerminate`
- Re-register after sleep/wake (`NSWorkspace.didWakeNotification`)
- Expose in popover: small row showing current shortcut + tap-to-change interaction

---

## Accessibility Permission — Detailed Notes

### What requires Accessibility

| Action | Requires Accessibility |
|---|---|
| CGEvent mouse-moved | ✅ Yes |
| CGEvent mouse click | ✅ Yes |
| NSEvent.addGlobalMonitorForEvents | ✅ Yes (macOS 13+) |
| CGWarpMouseCursorPosition | ❌ No |
| Reading cursor position (NSEvent.mouseLocation) | ❌ No |
| CGEventSource.secondsSinceLastEventType | ❌ No |
| Carbon RegisterEventHotKey | ❌ No |

### TCC (Transparency, Consent, Control)

Accessibility grants stored in `/Library/Application Support/com.apple.TCC/TCC.db`, managed by `tccd`. The app cannot self-grant — can only prompt the user.

If app bundle is renamed, moved, or bundle identifier changes, permission is invalidated and must be re-approved.

### MDM / Managed Devices

IT admins can pre-approve or permanently block Accessibility via MDM configuration profiles. The app cannot override this. Document as known limitation for enterprise users.

---

## App Distribution

### Direct Distribution

1. Build Release configuration
2. Enable Hardened Runtime
3. Sign: Developer ID Application certificate
4. Notarize via `notarytool`:
   ```bash
   xcrun notarytool submit MickJigger.dmg \
     --apple-id your@email.com \
     --team-id YOURTEAMID \
     --password app-specific-password \
     --wait
   ```
5. Staple: `xcrun stapler staple MickJigger.dmg`

Requires Apple Developer Program ($99/year).

### App Store — Not viable

App Sandbox blocks `CGEvent` posting to other processes. Incompatible with core functionality.

---

## Known Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Synthetic events accidentally counted as HID | Auto-stop fires on own jiggle | Use `.hidSystemState` (not `.combinedSessionState`); tag events with `userData`; verified in acceptance criteria |
| Race condition: jiggle fires same instant user returns | Cursor moves while user is regaining control | Check `physicalIdleSeconds() >= 3.0` at first line of every jiggle cycle, before any movement |
| Auto-start false positive: brief accidental contact | MONITORING → ACTIVE (auto) prematurely | Threshold minimum 30s; not configurable below that |
| Auto-stop false negative: user returns but no HID event for >1s | Jiggle continues briefly after user return | 1s polling interval; acceptable UX (≤1s lag to stop) |
| Coordinate system mismatch | Cursor moves to wrong position | All bounds computed in CGEvent space via single utility function; cover with manual test on 3 screen sizes |
| Accessibility revoked mid-session | CGEvent posts silently fail | Poll `AXIsProcessTrustedWithOptions` every 5s while active; show warning if lost |
| Sleep/wake: polling timer in bad state | Auto-start stuck or double-firing | Respond to `NSWorkspace.didWakeNotification`; stop and restart polling loop cleanly |
| Safe area margins larger than screen | No valid movement zone | Clamp to 100×100px minimum; show inline warning in popover |
| App bundle moved/renamed | Accessibility permission lost | Show re-authorization prompt when permission disappears unexpectedly |
| Hotkey conflicts with other apps | Shortcut silently swallowed | Use rare modifier combos (`⌥⌘`) as defaults; make configurable |

---

## Coordinate System Reference

```
NSScreen.frame / NSEvent.mouseLocation:    CGEvent positions:
  Origin: bottom-left                        Origin: top-left
  Y increases upward                         Y increases downward

Primary screen (2560×1600):
  NSScreen.frame = (0, 0, 2560, 1600)       CGEvent range: (0,0) → (2560,1600)
  NSEvent.mouseLocation.y=1600 = top        CGEvent.y=0 = top

Conversion (primary display):
  cgY = screenHeight - cocoaY

Conversion (multi-display, V2):
  cgY = totalDesktopHeight - cocoaY
  (totalDesktopHeight = max(screen.frame.maxY) across all screens)
```

---

## Settings — UserDefaults Keys

All keys prefixed with `mjv1.`:

```swift
enum SettingsKey {
    static let interval             = "mjv1.interval"            // Int, seconds
    static let movementDistance     = "mjv1.movementDistance"    // Int, pixels
    static let autoStartEnabled     = "mjv1.autoStartEnabled"    // Bool
    static let autoStartThreshold   = "mjv1.autoStartThreshold"  // Int, seconds
    static let marginTop            = "mjv1.marginTop"           // Int, pixels
    static let marginBottom         = "mjv1.marginBottom"        // Int, pixels
    static let marginLeft           = "mjv1.marginLeft"          // Int, pixels
    static let marginRight          = "mjv1.marginRight"         // Int, pixels
    static let launchAtLogin        = "mjv1.launchAtLogin"       // Bool
    static let hotkeyToggleCode     = "mjv1.hotkeyToggleCode"    // Int, keyCode (V1.1)
    static let hotkeyMonitorCode    = "mjv1.hotkeyMonitorCode"   // Int, keyCode (V1.1)
    // isActive / currentState: NOT persisted
}
```

---

## Launch at Login

```swift
import ServiceManagement

func setLaunchAtLogin(_ enabled: Bool) {
    do {
        if enabled { try SMAppService.mainApp.register() }
        else        { try SMAppService.mainApp.unregister() }
    } catch {
        // Surface error in UI
    }
}

func isLaunchAtLoginEnabled() -> Bool {
    SMAppService.mainApp.status == .enabled
}
```

No separate Login Item target or LaunchAgent required (macOS 13+ API).

---

## Info.plist Requirements

```xml
<!-- Prevents Dock icon and Cmd-Tab appearance — menu bar only -->
<key>LSUIElement</key>
<true/>

<!-- Usage description for Accessibility permission dialog -->
<key>NSAppleEventsUsageDescription</key>
<string>Mick Jigger needs Accessibility access to simulate mouse activity and prevent system idle.</string>
```
