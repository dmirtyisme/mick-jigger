# Mick Jigger — Roadmap

---

## V1.0 — MVP

**Goal:** A stable, safe jiggler with intelligent auto-start. Set it and forget it.

### Included

- Menu bar app with four states: INACTIVE / MONITORING / ACTIVE (manual) / ACTIVE (auto)
- Cursor movement with return-to-origin
- Jiggle-skip guard using `.hidSystemState` (real HID input detection)
- Safe area margins (top, bottom, left, right)
- Configurable jiggle interval: 30s / 1min / 2min / 5min
- Movement distance: Small / Medium / Large
- **Auto-start after inactivity** — configurable threshold (30s / 1min / 5min / 10min)
- Auto-stop when user returns (HID detection, not synthetic event confusion)
- Synthetic events tagged with custom `userData` to prevent self-triggering
- Accessibility permission flow with inline prompt
- Settings persistence (UserDefaults)
- Correct behavior through sleep/wake cycles
- MONITORING state restores on launch if auto-start was previously enabled

### Not included

- Hotkeys, launch at login, click/scroll simulation, Work Area UI

---

## V1.1 — Daily use polish

**Goal:** Reduce friction for daily use. No new core mechanics.

### Additions

**Global keyboard shortcut (hotkeys)**
- Default hotkey: `⌥⌘J` to toggle ACTIVE (manual) ↔ INACTIVE
- Additional hotkey: `⌥⌘M` to toggle MONITORING on/off (auto-start)
- Configurable in popover — click to re-assign shortcut
- Implementation: `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` (requires Accessibility, already granted)
- Shown in popover: "Toggle: ⌥⌘J · Auto-start: ⌥⌘M"
- Hotkey registration survives sleep/wake

**Launch at login**
- Toggle in popover (SMAppService, macOS 13+)

**Auto-stop timer**
- "Stop after: 1h / 2h / 4h / Never"
- Applies to ACTIVE (manual) only — does not affect MONITORING / ACTIVE (auto) logic

**Menu bar icon animation**
- Subtle pulse or opacity animation while in ACTIVE states
- Uses Core Animation on NSStatusBarButton

**Idle threshold for jiggle-skip (configurable)**
- Expose the hardcoded 3s value as a slider (1s–10s) in the Advanced section
- Useful for users with slow cursor movement patterns

---

## V2.0 — Extended interaction modes

**Goal:** Add optional, strictly controlled interaction beyond cursor movement.

### Additions

**Click simulation (opt-in, disabled by default)**
- Single left-click before returning cursor to origin
- Only fires within safe area bounds
- Click interval independent from movement interval
- Explicit opt-in checkbox; warning banner shown when enabled
- Requires: cursor in safe zone + Accessibility permission

**Scroll simulation (opt-in, disabled by default)**
- Net-zero scroll gesture (down + up) at cursor position
- Same safe area constraint
- Warning shown when enabled

**Work Area definition**
- User-defined rectangular zone on screen
- Draw via drag overlay or enter px values manually
- Named zones; activity confined to zone instead of screen-minus-margins
- Replaces margin system when a zone is active

**Multi-display support**
- Per-display selection: choose which display(s) to operate on
- Each display has independent safe area configuration
- Main display used as fallback

---

## V3.0 — Profiles and intelligence

**Goal:** Make the app adapt to different workflows without manual reconfiguration.

### Additions

**Profiles**
- Named presets: "Meeting", "Reading", "Presentation", "Monitoring"
- Each stores: interval, distance, margins, click/scroll toggles, auto-start settings
- Quick-switch from popover via segmented control or dropdown
- Import/export as JSON file

**Context-aware behavior (opt-in)**
- Detect frontmost app category (privacy-safe: no data leaves device)
- Example: lower frequency when terminal is active vs. browser in fullscreen
- Requires: Accessibility (already granted)

**Activity log**
- On-device log: date / time / duration / trigger (manual vs auto) per session
- No analytics, no telemetry
- Accessible from "History" section in popover, expandable

**Sparkle / auto-update**
- In-app update check and install for direct distribution builds
- User-controlled: check automatically or manual only

---

## Explicitly Deferred (Not Planned)

| Feature | Reason |
|---|---|
| App Store distribution | Sandbox incompatibility with CGEvent posting |
| iOS / iPadOS version | Different platform and permission model |
| Cloud sync of settings | Unnecessary complexity for a local utility |
| Remote control / API | Out of scope, creates security surface |
| Analytics / telemetry | Conflicts with local-only principle |
