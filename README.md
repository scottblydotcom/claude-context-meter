# Claude Context Meter

A Mac menu bar app that shows your Claude usage at a glance — context window fill, billing window token burn, and weekly usage totals.

Claude doesn't surface these numbers natively across its interfaces. This app reads the same local session files Claude writes to disk and displays them in a lightweight always-on indicator.

---

## What it shows

**Context Window** — how full your current session's context is (tokens used / 200k limit), with a green/yellow/red indicator.

**Billing Window** — output tokens used in the current rolling 5-hour window. Resets on a rolling basis anchored to the top of the hour your first request landed in. Anthropic hasn't published the exact output token limit per window — you can configure the threshold to match what you observe on your plan.

**Weekly Usage** — four views of your token usage since the last weekly reset. Anthropic hasn't published the exact counting formula, so the app shows all four plausible methods so you can compare:
- **All tokens** — input + cache creation + cache reads + output
- **Excl. cache reads** — removes cache read tokens (large but cheap)
- **Input + output** — only tokens you directly sent and received
- **Peak-adjusted** — applies a 2× multiplier for requests made Mon–Fri 5–11 AM PT; Anthropic has indicated peak hours count more heavily against the weekly limit

---

## Requirements

- macOS 14 Sonoma or later
- Claude Code installed and actively used — available as the Claude Mac Desktop app (via the Code tab), a standalone CLI, or IDE extensions. All write to the same local session files this app reads.
- **Claude Pro plan** — v1 is built and tested against the Pro plan. Max and Team plans have different limits and reset schedules; defaults may not match your plan.

---

## Install

### Option A: DMG (easiest)
1. Download `ClaudeContextMeter-1.0.dmg` (or latest version) from Releases
2. Open the DMG, drag the app to Applications
3. Launch it — the gauge icon appears in your menu bar
4. Click the icon to see your usage

### Option B: Build from source
1. Clone this repo
2. Open `ClaudeContextMeter/ClaudeContextMeter.xcodeproj` in Xcode
3. Build and run (⌘R)

---

## Configuration

The app works out of the box with sensible defaults. Two settings are configurable in the popover:

**Launch at Login** — toggle in the footer of the popover to start the app automatically on login.

**Weekly reset day/hour** — defaults to Tuesday at 9 PM. Check your Claude settings to confirm your plan's reset time, then adjust if needed via `UserDefaults` (UI coming soon):

```bash
# Example: reset on Wednesday at 8 PM
defaults write com.scottbly.ClaudeContextMeter weeklyResetWeekday 4
defaults write com.scottbly.ClaudeContextMeter weeklyResetHour 20
```

Weekday values: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat

**Billing token limit** — the threshold shown in the billing window gauge. Anthropic hasn't published the exact per-window limit, so this is configurable. Adjust based on what you observe:

```bash
defaults write com.scottbly.ClaudeContextMeter billingTokenLimit 131000
```

---

## How it works

Claude Code writes session data to JSONL files at:
```
~/.claude/projects/
```

The app watches these files with `FSEvents`, parses them on change, and updates the menu bar indicator in real time. No network requests, no API keys, no telemetry — all local.

---

## Limitations

- **Claude Code sessions only** — reads session files written by Claude Code (CLI, IDE extensions, or the Code tab in the Mac Desktop app). Chat conversations in the Claude Desktop app and claude.ai web interface are not captured. If you use both the Code tab and the Desktop chat interface under the same plan, only your Code tab tokens are counted here.
- **Output tokens for billing window** — the billing window tracks output tokens only, based on observed behavior. Anthropic hasn't documented the exact formula.
- **Weekly total is an estimate** — Anthropic hasn't published the counting formula or the exact limits. The four methods bracket the likely answer; treat them as directional, not exact.
- **No historical charts** — current window only. Past sessions are used only to find the active window boundary.

---

## Contributing

Issues and pull requests welcome. See `BACKLOG.md` for known bugs and planned features.
