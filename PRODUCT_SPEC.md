# Mick Jigger — Product Spec

## Overview

Mick Jigger is a menu bar utility. It has no main window. All interaction happens through a status item in the macOS menu bar and a popover attached to it.

---

## Application State Machine

The app operates in one of four discrete states:

```
                    ┌─────────────────────────────────────────┐
                    │                                         │
          user enables auto-start                  user disables auto-start
                    │                                         │
                    ▼                                         │
  ┌──────────┐  left-click   ┌───────────┐   left-click  ┌──────────────┐
  │ INACTIVE │ ────────────► │ ACTIVE    │ ◄──────────── │  MONITORING  │
  │          │ ◄──────────── │ (manual)  │               │  (auto-start │
  └──────────┘  left-click   └───────────┘               │   enabled)   │
                                                          └──────┬───────┘
                                                                 │
                                          hidIdle >= threshold   │
                                                                 ▼
                                                        ┌──────────────┐
                                                        │  ACTIVE      │
                                                        │  (auto)      │
                                                        └──────┬───────┘
                                                               │
                                             hidIdle < 1.0s   │
                                                               ▼
                                                        ┌──────────────┐
                                                        │  MONITORING  │
                                                        │  (resumes)   │
                                                        └──────────────┘
```

### State definitions

| State | Description |
|---|---|
| **INACTIVE** | App is idle. No jiggling, no monitoring. Manual activation only. |
| **MONITORING** | Auto-start is enabled. Watching physical input. No jiggling yet. |
| **ACTIVE (manual)** | User explicitly activated via left-click or toggle. Jiggling runs. |
| **ACTIVE (auto)** | Jiggling started automatically after inactivity threshold was reached. |

### State transitions

| From | To | Trigger |
|---|---|---|
| INACTIVE | ACTIVE (manual) | User left-clicks menu bar icon |
| INACTIVE | MONITORING | User enables Auto-start toggle |
| MONITORING | ACTIVE (auto) | `hidIdle >= autoStartThreshold` |
| MONITORING | INACTIVE | User disables Auto-start toggle |
| ACTIVE (manual) | INACTIVE | User left-clicks menu bar icon |
| ACTIVE (auto) | MONITORING | `hidIdle < 1.0s` (real user input detected) |
| ACTIVE (auto) | INACTIVE | User explicitly disables via toggle |
| Any active state | INACTIVE | Accessibility permission revoked |

**Key rule:** ACTIVE (auto) and ACTIVE (manual) are behaviorally identical for jiggling. The difference is only in what happens next: auto deactivates itself when user returns; manual requires explicit toggle.

---

## Menu Bar Status Item

### Icon states

| State | Icon |
|---|---|
| INACTIVE | Mouse cursor outline, monochrome (system secondary color) |
| MONITORING | Mouse cursor outline with small indicator dot (amber/yellow) |
| ACTIVE (manual) | Mouse cursor filled, accent color |
| ACTIVE (auto) | Mouse cursor filled, accent color (same as manual) |

The icon must be recognizable at 16×16 and 22×22 points. System template image behavior preferred for INACTIVE and MONITORING states. Color variants for active states.

### Click behavior

| Action | Result |
|---|---|
| Left click | Toggle between ACTIVE (manual) ↔ INACTIVE; if MONITORING → ACTIVE (manual); if ACTIVE (auto) → INACTIVE |
| Right click | Open popover with settings |

**Left-click in MONITORING state:** transitions to ACTIVE (manual), not INACTIVE. Rationale: user is clearly trying to activate — don't confuse them by disabling a feature they set up.

**Left-click in ACTIVE (auto) state:** stops jiggling and returns to INACTIVE (not MONITORING). Rationale: an explicit click is a clear intent to stop. User can re-enable auto-start from the popover if needed.

---

## Popover

Opens on right-click. Attached to the status item. Closes on click outside.

### Layout

```
┌────────────────────────────────────────┐
│  Mick Jigger              ● Active   │  ← status label + toggle switch
│  "Jiggling every 60s"                  │  ← status subline (contextual)
├────────────────────────────────────────┤
│  Jiggle interval                        │
│  [30s]  [1min]  [2min]  [5min]         │  ← segmented control
├────────────────────────────────────────┤
│  Movement distance                      │
│  [Small]  [Medium]  [Large]            │  ← segmented control
├────────────────────────────────────────┤
│  Auto-start after inactivity   [toggle]│  ← master toggle for auto-start
│  Start after: [30s][1min][5min][10min] │  ← shown only if auto-start ON
├────────────────────────────────────────┤
│  Safe area margins              [▸]    │  ← disclosure section
├────────────────────────────────────────┤
│  Launch at login                [ ]    │
│  Quit Mick Jigger                    │
└────────────────────────────────────────┘
```

### Status subline (contextual text below title)

| State | Subline text |
|---|---|
| INACTIVE | "Inactive" |
| MONITORING | "Watching — starts after 5min idle" |
| ACTIVE (manual) | "Jiggling every 60s" |
| ACTIVE (auto) | "Auto-active — jiggling every 60s" |
| Permission missing | "⚠ Accessibility access required" |

### Auto-start section (conditional rendering)

Shown only when Auto-start toggle is ON:

```
┌──────────────────────────────────────────┐
│  Auto-start after inactivity   [● ON]    │
│  Start after:                            │
│  [30s]  [1min]  [5min]  [10min]         │
└──────────────────────────────────────────┘
```

When OFF, the "Start after" row is hidden (not greyed out — fully collapsed).

### Safe Area Margins (expanded)

```
┌──────────────────────────────────────┐
│  Safe area margins                    │
│                                       │
│  Top     [____60____] px             │
│  Bottom  [____80____] px             │
│  Left    [____20____] px             │
│  Right   [____20____] px             │
└──────────────────────────────────────┘
```

Default margin values:
- Top: 60px (covers menu bar + 1 row of browser tabs)
- Bottom: 80px (covers Dock)
- Left: 20px
- Right: 20px

---

## Core Behaviors

### Polling Loop (always running when app is active)

A 1-second polling loop runs whenever the app state is MONITORING or ACTIVE (auto). It is the single source of truth for auto-start logic.

```
every 1.0 second:
  hidIdle = min(
    secondsSinceLastEventType(.hidSystemState, .mouseMoved),
    secondsSinceLastEventType(.hidSystemState, .keyDown),
    secondsSinceLastEventType(.hidSystemState, .leftMouseDown),
    secondsSinceLastEventType(.hidSystemState, .scrollWheel)
  )

  if state == .monitoring AND hidIdle >= autoStartThreshold:
    → transition to .activeAuto
    → start jiggle timer

  if state == .activeAuto AND hidIdle < 1.0:
    → stop jiggle timer
    → transition to .monitoring
```

The polling loop does **not** run in INACTIVE or ACTIVE (manual) states — no CPU consumed for a feature the user hasn't enabled.

### Jiggle Cycle

Runs on a separate `DispatchSourceTimer` at the configured interval. Each cycle:

1. **Check HID idle** — query `.hidSystemState` idle time. If `hidIdle < 3.0s`, skip this cycle entirely.
   - This is the "pause when user is active" safety guard.
   - Uses `.hidSystemState` — synthetic events from this app do NOT reset this counter.
2. **Record current cursor position** (`originX`, `originY`).
3. **Compute target position** within safe area bounds:
   - `targetX = clamp(originX + randomOffset(±distance), safeLeft, safeRight)`
   - `targetY = clamp(originY + randomOffset(±distance), safeTop, safeBottom)`
4. **Move cursor** via `CGEvent` with a `CGEventSource` tagged with `userData = kMickJiggerSyntheticTag`.
5. **Wait 150ms.**
6. **Return cursor to origin** via the same tagged `CGEventSource`.

**Why tagged source:** Ensures our own events are identifiable. The `.hidSystemState` isolation already handles auto-stop detection, but tagging defends against future edge cases where our events could be misread.

### Auto-start Threshold Values

| Label | Seconds |
|---|---|
| 30s | 30 |
| 1min | 60 |
| 5min | 300 |
| 10min | 600 |

Default: 5min (300s).

### Movement Distance Values

| Label | Pixel offset |
|---|---|
| Small | ±5px |
| Medium | ±20px |
| Large | ±50px |

### Jiggle Interval Values

| Label | Seconds |
|---|---|
| 30s | 30 |
| 1min | 60 |
| 2min | 120 |
| 5min | 300 |

### Safe Area Calculation

Given screen bounds `(W, H)` and margins:

```
safeLeft   = left
safeRight  = W - right
safeTop    = top
safeBottom = H - bottom
```

If cursor is already outside the safe area (e.g. user moved it to a toolbar), the jiggle cycle is skipped for that tick.

---

## Settings Persistence

All settings stored in `UserDefaults`.

| Key | Type | Default |
|---|---|---|
| `interval` | Int (seconds) | 60 |
| `movementDistance` | Int (px) | 20 |
| `autoStartEnabled` | Bool | false |
| `autoStartThreshold` | Int (seconds) | 300 |
| `marginTop` | Int (px) | 60 |
| `marginBottom` | Int (px) | 80 |
| `marginLeft` | Int (px) | 20 |
| `marginRight` | Int (px) | 20 |
| `launchAtLogin` | Bool | false |

**Not persisted:**
- `isActive` — app always starts INACTIVE on launch
- `currentState` — always reset to INACTIVE (or MONITORING if `autoStartEnabled` was on)

**On launch with `autoStartEnabled = true`:** app starts in MONITORING state automatically, without requiring any user interaction.

---

## Accessibility Permission Flow

Accessibility is required to post `CGEvent` mouse-moved events recognized as real activity by the system.

### First activation flow

1. App launches → INACTIVE (or MONITORING if auto-start was previously enabled).
2. User attempts to activate (toggle or auto-start fires).
3. Check `AXIsProcessTrustedWithOptions(nil)`.
4. If not trusted → show inline prompt:
   ```
   ⚠ Accessibility access required
   Mick Jigger needs Accessibility permission
   to simulate mouse activity.
   [Open System Settings]
   ```
5. Button opens System Settings → Privacy & Security → Accessibility.
6. App detects grant on next popover open or poll cycle.

### Auto-start + no permission

If auto-start fires while permission is missing: do not attempt to jiggle. Show permission warning in menu bar icon (e.g. badge). Do not silently fail.

---

## States and Edge Cases

| Scenario | Behavior |
|---|---|
| Screen locked | Pause jiggling; if in ACTIVE (auto), return to MONITORING on unlock |
| Display sleep | Pause jiggling; resume on wake |
| System sleep | App suspends; on wake: ACTIVE (auto) returns to MONITORING (user clearly present), ACTIVE (manual) resumes |
| User returns during ACTIVE (auto) | hidIdle < 1.0s detected → stop jiggling → MONITORING |
| User moves mouse during jiggle cycle | hidIdle check at start of cycle skips it; no conflict |
| Cursor at screen edge | Safe area clamp prevents movement outside bounds |
| Safe area too small | Clamp to 100×100px minimum; show inline warning |
| App crashes while active | On next launch: INACTIVE (or MONITORING if autoStartEnabled) |
| Multiple displays | Operate on main display only (V1) |
| Accessibility permission revoked | Stop immediately; show warning; do not crash |
| Auto-start fires, Accessibility not granted | Show permission warning; do not attempt CGEvent post |
| User enables auto-start while ACTIVE (manual) | Auto-start begins monitoring in background; manual active state continues; auto logic takes over only if user later deactivates manually |
