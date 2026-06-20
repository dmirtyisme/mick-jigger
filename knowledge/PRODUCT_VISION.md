# Mick Jigger — Product Vision

## What It Is

Mick Jigger is a native macOS menu bar utility that simulates user activity by periodically moving the cursor. Its primary purpose is to prevent macOS from entering idle state, triggering screensavers, locking the screen, or showing "away" status in communication tools — without requiring any changes to system settings.

## Why It Exists

macOS and most enterprise software (Slack, Teams, Zoom, Loom) use cursor inactivity as a proxy for user absence. This creates friction in legitimate workflows:

- Watching a long video or presentation
- Monitoring a running process or build
- Reading long documents without interaction
- Sitting in a meeting room using a secondary machine
- Keeping a screen readable without touching it

The correct solution would be to configure each app's idle timeout individually — but that's fragmented, often restricted by IT policy, or simply not available. Mick Jigger solves the problem at the OS level with a single toggle.

## Core Principles

**1. Safety first.**
The app must never cause unintended interactions. Cursor movement stays within a configurable safe area. Clicks are disabled in V1. The app must not interfere with the user's own input.

**2. One-click activation.**
The primary action — toggle active/inactive — must require exactly one click. No dialogs, no confirmations, no loading states.

**3. Invisible when inactive, obvious when active.**
When inactive, the app should not draw attention. When active, the menu bar icon must clearly signal the state at a glance.

**4. No cloud. No accounts. No telemetry.**
This is a local utility. It runs on the device, stores settings locally, and has no network requirements.

**5. Does not fight the user.**
If the user is actively using the machine, the jiggler pauses. It activates only when the system is actually idle. Movement is minimal and returns the cursor to its original position.

**6. Minimal footprint.**
Low CPU, low memory, no background services, no login agents beyond a simple launch-at-login toggle.

## Target User

A macOS user — developer, designer, analyst, or knowledge worker — who occasionally needs to keep their screen active without touching the machine, and wants a quick, reliable way to do it without reconfiguring system settings.

## What It Is Not

- It is not a macro tool or automation platform.
- It is not a click bot or input injector for gaming or scraping.
- It is not a screen time bypass tool for managed devices (Accessibility restrictions from MDM may block it).
- It is not a productivity tracker or idle monitor.

## Success Criteria for V1

- User can activate cursor jiggling in under 2 seconds from launch.
- App never causes an unintended click or scroll.
- App correctly pauses when user is actively using the machine.
- App survives sleep/wake cycles without crashing or getting stuck.
- Cursor always returns to its original position after a jiggle cycle.
- Safe area margins prevent cursor from reaching system UI zones.

## Naming Strategy

### Current working title
Mick Jigger

### Origin
Wordplay between "Mick Jagger" and "Mouse Jiggler".

### Status
- Temporary working title
- Used for development, testing, and repository naming
- Subject to change before any public release

### What this name is used for
- Project name
- Repository name (mick-jigger)
- Internal codename

### Final name
To be decided after the product reaches a working state
and its final direction is clear. Naming is not a priority now.

### Known risks
- Potential trademark proximity to Mick Jagger / Rolling Stones brand
- Name may not reflect the analytics direction if product pivots further
- App Store search discoverability unknown for this name
These are noted for future review. Do not change the name without a separate explicit decision.
