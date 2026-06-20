# Mick Jigger

A native macOS menu bar utility that keeps your screen active by periodically moving the cursor — preventing idle state, screensavers, screen lock, and "away" status in Slack, Teams, and Zoom.

## What it does

One click in the menu bar starts jiggling. The cursor makes a small movement on a configurable interval and returns to its original position. The app pauses automatically while you're actively using the machine.

**Activity Tracking** records real input (clicks, scrolls, cursor distance, active time) independently of the jiggler — giving you an honest picture of your actual usage.

## Features

- Menu bar toggle — active/inactive in one click
- Configurable jiggle interval and movement distance
- Safe area margins to keep the cursor away from screen edges and system UI
- Auto-start after a configurable idle threshold
- Optional click and scroll simulation (opt-in, off by default)
- Activity Tracking with daily, weekly, monthly, and all-time views
- Personal records and activity trail
- Launch at login
- Universal binary (Apple Silicon + Intel)

## Requirements

- macOS 13 Ventura or later
- Accessibility permission (for cursor movement)
- Input Monitoring permission (for Activity Tracking, optional)

## Install

Download `MickJigger-v1.0.dmg`, open it, drag Mick Jigger to Applications.

## Project layout

```
MickJigger/          Swift source
knowledge/           Product docs and specs
assets/              Icons and images
bot/                 Telegram bot (future)
```

## Status

Early release. Working title — the final name will be decided before any public App Store listing.
