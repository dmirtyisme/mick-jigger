# Mick Jigger — App Store Readiness

This document tracks everything required to prepare Mick Jigger for Mac App Store submission. It is a living checklist — updated as each phase progresses.

Current status: **V1 — Local prototype phase. App Store submission not planned yet.**

---

## App Store Compatibility: Feature Risk Assessment

| Feature | App Store compatible? | Notes |
|---|---|---|
| Cursor movement via `CGEvent.post()` | ✅ Yes | Requires Accessibility (TCC). Sandbox allows if user grants. Precedent: Lungo, similar apps exist on MAS. |
| Auto-start idle detection via `.hidSystemState` | ✅ Yes | No permissions required. Read-only aggregate query, not event interception. |
| Safe area margins | ✅ Yes | Pure math, no system interaction. |
| Launch at login via `SMAppService` | ✅ Yes | Official sandboxed API (macOS 13+). |
| Hotkeys via Carbon `RegisterEventHotKey` | ✅ Yes | No permissions required. Sandbox compatible. |
| Hotkeys via `NSEvent.addGlobalMonitorForEvents` | ⚠️ Caution | Requires Accessibility. Review may scrutinize "keyboard monitoring" framing. Use Carbon instead for App Store build. |
| Click simulation | 🔴 High risk | Input injection. Apple may reject as "automation tool" even with user opt-in. **Exclude from App Store build.** |
| Scroll simulation | 🔴 Medium risk | Same category as click simulation. **Exclude from App Store build.** |
| Sparkle auto-update | 🔴 Prohibited | App Store apps must update via App Store only. Remove entirely from App Store build. |
| Custom DMG installer scripts | 🔴 Prohibited | App Store requires self-contained `.app`. |
| Private APIs | ✅ None used | All APIs are public Apple frameworks. |

---

## Two Distribution Builds

The product must support two parallel build configurations from a single codebase:

```
App Store build (APPSTORE=1)        Direct Distribution build
───────────────────────────         ─────────────────────────
Move-only jiggling         ✅        Move-only jiggling        ✅
Auto-start                 ✅        Auto-start                ✅
Safe area margins          ✅        Safe area margins         ✅
Launch at login            ✅        Launch at login           ✅
Carbon-based hotkeys       ✅        Carbon-based hotkeys      ✅
App Sandbox enabled        ✅        App Sandbox disabled      ✅
Sparkle auto-update        ❌        Sparkle auto-update       ✅
Click simulation           ❌        Click simulation          ✅
Scroll simulation          ❌        Scroll simulation         ✅
```

Implementation: Xcode target + `#if APPSTORE` compile-time flags to conditionally exclude features.

---

## App Sandbox Requirements

### Entitlements — App Store build

```xml
<!-- Required entitlements (App Store build) -->
<key>com.apple.security.app-sandbox</key>
<true/>

<!-- If using network features (not needed for V1) -->
<!-- <key>com.apple.security.network.client</key> -->
<!-- <true/> -->
```

No additional entitlements required. Accessibility is a TCC permission (user-granted at runtime), not an entitlement.

**Temporary exceptions:** Do NOT add `com.apple.security.temporary-exception.*` entitlements — these are not accepted for App Store builds and trigger rejection.

### What sandbox restricts (and how we handle it)

| Restricted action | Our response |
|---|---|
| Reading files outside app container | Not needed — settings in UserDefaults, no file I/O |
| Network access | Not needed — fully local app |
| CGEventTap passive monitoring | Not used — we use `.hidSystemState` aggregate query instead |
| Posting events without Accessibility | Handled — permission flow built into activation |

### Sandbox testing checklist

- [ ] Build with App Sandbox enabled; verify all core functionality works
- [ ] Verify `CGEvent.post(tap: .cghidEventTap)` works under sandbox with Accessibility granted
- [ ] Verify `CGEventSource.secondsSinceLastEventType(.hidSystemState, ...)` works under sandbox
- [ ] Verify `SMAppService.mainApp.register()` works under sandbox
- [ ] Verify Carbon `RegisterEventHotKey` works under sandbox
- [ ] Confirm app does not write to any path outside its sandbox container
- [ ] Run `codesign --verify --deep --strict` with no errors
- [ ] Run `spctl --assess --type execute` with no warnings

---

## Permissions Documentation

### Accessibility

**Required for:** `CGEvent.post()` — simulating mouse movement.

**When requested:** On first activation attempt. Not at app launch.

**How requested:** Inline prompt in popover UI directing user to System Settings → Privacy & Security → Accessibility. App does NOT call `AXIsProcessTrustedWithOptions` with `prompt=true` on macOS 13+ (Apple recommends against it; open System Settings directly instead).

**Info.plist key:**
```xml
<key>NSAccessibilityUsageDescription</key>
<string>Mick Jigger uses Accessibility to move the mouse cursor, which prevents your Mac from entering sleep or showing as away in apps like Slack or Teams.</string>
```

**Fallback if denied:** App enters degraded mode — can monitor inactivity but cannot jiggle. UI shows persistent inline warning. App does not crash, does not retry silently.

### Input Monitoring

**Not required.** The app does not intercept, record, or read keyboard or mouse input from other applications.

`CGEventSource.secondsSinceLastEventType(.hidSystemState, ...)` is a read-only query of an aggregate time counter — it does not access individual events, keystrokes, or click targets from other apps.

This distinction is important for App Review and must be documented clearly in the App Store description.

### No other permissions needed

| Permission | Used? | Why not |
|---|---|---|
| Camera | ❌ | Not relevant |
| Microphone | ❌ | Not relevant |
| Location | ❌ | Not relevant |
| Contacts / Calendar | ❌ | Not relevant |
| Full Disk Access | ❌ | No file I/O outside container |
| Screen Recording | ❌ | App does not read screen content |
| Input Monitoring | ❌ | Uses `.hidSystemState` aggregate only |

---

## App Metadata

### App name
Mick Jigger

### Subtitle (max 30 chars)
Keep your Mac awake

### Description (draft)

```
Mick Jigger keeps your Mac awake and your status active while you're away from the keyboard.

It works by periodically moving the mouse cursor a small amount — enough to prevent macOS from entering sleep, activating the screensaver, or showing you as "away" in Slack, Teams, or other apps.

Key features:
• Menu bar utility — always one click away
• Auto-start: automatically activates after you've been away for a set time
• Auto-stop: automatically deactivates the moment you return
• Safe area margins: cursor movement stays away from menu bar, Dock, and screen edges
• Configurable interval and movement distance
• No clicks, no keystrokes, no interaction with other apps

Mick Jigger requires Accessibility permission to move the mouse cursor. It does not read your keystrokes, monitor your screen, or interact with any other application.

No accounts. No cloud. No telemetry. Runs entirely on your Mac.
```

### Keywords (max 100 chars total)
`mouse jiggler, keep awake, prevent sleep, caffeine, screen sleep, idle, away status, menu bar`

### Category
Primary: Utilities
Secondary: Productivity

### Age rating
4+ (no objectionable content)

### Privacy Policy
Required (even for apps with no data collection — must state that no data is collected).

---

## Privacy Policy Requirements

App Store requires a privacy policy URL even if the app collects no data. The policy must state:

- What data is collected: None.
- What permissions are used and why: Accessibility — to move the mouse cursor.
- Whether data is shared with third parties: No.
- Contact information for privacy inquiries.

Minimum viable privacy policy can be hosted as a static page (GitHub Pages, Notion public page, personal domain).

---

## Screenshots Required

| Format | Dimensions | Count |
|---|---|---|
| Mac (required) | 1280×800 or 1440×900 | 3–10 |

Screenshots must show:
1. App in menu bar, inactive state
2. Popover open showing settings
3. App active (status + subline text)
4. Auto-start section visible
5. (Optional) Safe area margins section

**App Review note:** Screenshots should not claim the app "automates" anything or "bypasses" system settings. Framing: "keeps Mac awake", "prevents screen sleep".

---

## App Review Risk Assessment

### Overall risk: Low to Medium

The "keep-awake" utility category is established on the Mac App Store. Precedents: Lungo (by Sindre Sorhus), Caffeine, Theine, Amphetamine (returned after initial rejection), Keepin' Alive, and others.

### Risk factors

| Factor | Risk | Mitigation |
|---|---|---|
| Accessibility permission usage | Medium | Usage description must exactly match actual usage. Do not mention "automation" or "input simulation". |
| "Simulates mouse movement" in description | Medium | Frame as "moves the cursor to prevent sleep", not "simulates user activity" |
| Auto-start idle detection | Low | Read-only aggregate query; does not intercept input |
| No click/scroll in App Store build | Low | Explicitly excluded; no review risk |
| App purpose is clear | Low | Category is established; multiple precedents |

### Amphetamine precedent

Amphetamine was initially removed from the App Store in 2020 due to concerns about "encouraging illegal activity" (circumventing MDM restrictions). Apple reversed the decision after developer and community pushback. The app returned with minor description changes. Takeaway: frame the app around **productivity and legitimate use cases**, not circumventing restrictions.

### Recommended App Review note

Include in App Review notes when submitting:

```
Mick Jigger is a menu bar utility that prevents macOS from entering idle state by
periodically moving the mouse cursor a small amount. It requires Accessibility permission
solely for this cursor movement.

The app does not:
- Monitor or record keyboard input
- Click on UI elements or interact with other apps
- Access any data outside its sandbox container
- Require network access

This is similar in purpose and implementation to existing App Store utilities such as
Lungo and Keepin' Alive.
```

---

## Checklist: V1.5 App Store Readiness Audit

To be completed before V2 App Store submission:

### Technical

- [ ] App Sandbox enabled and all features verified working
- [ ] No temporary exception entitlements
- [ ] No private APIs (`nm` scan + manual review)
- [ ] No calls to `system()`, `NSTask` executing shell commands, or `dlopen()`
- [ ] No network requests
- [ ] No writes outside sandbox container (`~/Library/Application Support/<bundle-id>` is fine)
- [ ] `CGEvent.post()` verified working under sandbox with Accessibility granted
- [ ] Carbon hotkeys verified working under sandbox
- [ ] `#if APPSTORE` flag correctly excludes click/scroll/Sparkle
- [ ] Codesigning with Distribution certificate verified
- [ ] App passes `spctl` assessment

### Permissions

- [ ] `NSAccessibilityUsageDescription` present and accurately describes usage
- [ ] No `NSInputMonitoringUsageDescription` (not needed; would trigger unnecessary scrutiny)
- [ ] Permission prompt tested: shows at first activation, not at launch
- [ ] Fallback behavior tested: app functional (monitoring) when Accessibility denied
- [ ] Accessibility revocation handled gracefully mid-session

### App Store Connect

- [ ] App name and subtitle finalized
- [ ] App description written and reviewed (no prohibited framing)
- [ ] Keywords under 100 chars
- [ ] Category selected (Utilities)
- [ ] Age rating completed
- [ ] Privacy policy URL live and accessible
- [ ] Privacy nutrition label completed in App Store Connect (data not collected)
- [ ] Screenshots prepared (3+ at correct resolution)
- [ ] App Review notes written
- [ ] Support URL ready (GitHub or website)

### Pre-submission testing

- [ ] Tested on Intel Mac (if supporting x86_64)
- [ ] Tested on Apple Silicon Mac
- [ ] Universal binary verified (`lipo -info`)
- [ ] Tested on minimum supported OS (macOS 13.0)
- [ ] Tested on latest macOS
- [ ] 3× sleep/wake cycle test passed
- [ ] Full App Sandbox test passed (sandbox enabled, all features verified)
- [ ] TestFlight build distributed and tested by at least one additional person

---

## Fallback Behavior Map (if permissions denied)

```
Accessibility denied
└── Cannot post CGEvents (cursor movement blocked)
    └── UI: Persistent warning banner in popover
    └── State: MONITORING still works (idle detection is permission-free)
    └── State: Auto-start triggers, shows warning, does not attempt to jiggle
    └── State: Icon shows warning indicator (badge or different icon variant)
    └── Action: [Open System Settings] button always visible
    └── Never: silent failure, crash, or removal of other settings
```

The app remains useful in a degraded state: it can still monitor inactivity and notify the user (via menu bar state change) without being able to actually jiggle.
