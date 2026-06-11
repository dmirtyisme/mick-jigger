# Mick Jigger — MVP Scope

## Goal

Ship a stable, safe macOS menu bar utility that moves the cursor periodically to prevent system idle, and can automatically activate itself after a configurable period of inactivity.

---

## In Scope

### Core

- [x] Menu bar status item with four visual states (inactive / monitoring / active-manual / active-auto)
- [x] Left-click to toggle active/inactive immediately
- [x] Right-click to open settings popover
- [x] Periodic cursor movement using `CGEvent` tagged with synthetic source marker
- [x] Cursor returns to origin position after each jiggle cycle
- [x] Jiggle cycle skipped if real HID input detected within last 3 seconds (`.hidSystemState`)
- [x] Safe area margins (top, bottom, left, right) — cursor never moves outside
- [x] Configurable jiggle interval: 30s / 1min / 2min / 5min
- [x] Configurable movement distance: Small (5px) / Medium (20px) / Large (50px)
- [x] Accessibility permission check and inline prompt on first activation
- [x] App always starts inactive (or monitoring if auto-start was previously enabled) on launch
- [x] Graceful handling of Accessibility permission denial or revocation
- [x] Settings persisted in UserDefaults (active state NOT persisted)

### Auto-start after inactivity

- [x] Auto-start toggle in popover (default: OFF)
- [x] Configurable inactivity threshold: 30s / 1min / 5min / 10min (default: 5min)
- [x] 1-second polling loop using `CGEventSource.secondsSinceLastEventType(.hidSystemState, ...)`
- [x] Automatic activation when physical HID idle time >= threshold
- [x] Automatic deactivation when physical HID idle time < 1.0s (user returned)
- [x] MONITORING state: app watches for inactivity but does not jiggle
- [x] On app launch with auto-start enabled → start in MONITORING state automatically
- [x] Permission check before auto-activation; silent block + warning if not granted

### Supported macOS versions

Target: macOS 13 Ventura and later.
Rationale: `SMAppService` for launch-at-login requires macOS 13+. Simplifies implementation and avoids legacy LaunchAgent approach.

---

## Out of Scope (MVP)

| Feature | Reason | Target version |
|---|---|---|
| Global keyboard shortcut (hotkeys) | Not critical for MVP; requires additional event monitoring setup | V1.1 |
| Launch at login | Nice-to-have, not core | V1.1 |
| Auto-stop timer | Nice-to-have | V1.1 |
| Menu bar icon animation | Polish, not function | V1.1 |
| Idle threshold configuration for jiggle-skip (expose 3s value) | Hardcoded is fine for MVP | V1.1 |
| Click simulation | Safety risk, not needed for core use case | V2 (opt-in) |
| Scroll / zoom simulation | Unpredictable side effects | V2 |
| Work Area visual definition | Complex UI, not essential | V2 |
| Multi-display support | Adds complexity, low priority | V2 |
| Movement pattern selector | Overkill for MVP | V2 |
| App Store distribution | Sandbox incompatibility | Not planned |

---

## MVP Acceptance Criteria

1. **Activation speed:** User can go from app launch to active jiggling in under 5 seconds (including granting Accessibility permission on first run).

2. **Safety:** App never moves cursor into the top margin zone. Verified on 1440×900, 1920×1080, and Retina 2560×1600.

3. **Jiggle-skip when active:** If user moves mouse or types within 3 seconds before a scheduled jiggle, that cycle is skipped. Verified manually.

4. **Return to origin:** After each jiggle cycle, cursor is back at pre-jiggle position within ±2px.

5. **Sleep/wake stability:** App survives 3× sleep/wake cycles without crashing or getting stuck in ACTIVE state.

6. **Permission flow:** Activation blocked and inline prompt shown with working System Settings link if Accessibility not granted.

7. **Settings persistence:** Interval, distance, auto-start toggle, and auto-start threshold survive app restart.

8. **No spurious clicks:** No `kCGEventLeftMouseDown` or similar events ever posted. Verified with event monitoring tool.

9. **Auto-start activates:** With auto-start ON and threshold = 30s, leaving the machine idle for 35 seconds results in jiggling starting automatically.

10. **Auto-stop on return:** While in ACTIVE (auto), moving the mouse stops jiggling within 1–2 seconds and returns app to MONITORING state.

11. **HID isolation:** Synthetic jiggle events do NOT trigger auto-stop detection. Verified by watching MONITORING → ACTIVE (auto) → jiggling → still active (no false positive from own events).

---

## MVP Non-Goals

- Perfect visual design (functional is sufficient)
- Notarization and public distribution (developer-only build acceptable for MVP)
- Automated tests (manual verification acceptable for MVP)
- Performance benchmarking (trivial CPU workload, not a concern)
