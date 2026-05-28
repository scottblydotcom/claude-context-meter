# Claude Context Meter

A macOS menu bar app that shows Claude Code usage at a glance — without opening the Claude Desktop app.

**Built for Claude Code CLI users.** The Claude Desktop app (as of 2026) natively shows context window, 5-hour billing, and weekly usage in Settings → Usage. If you live in the Desktop app, you don't need this. This app exists for people who work primarily in the Claude Code CLI or IDE extensions and want those numbers in the macOS menu bar without context-switching.

---

## What it shows

**Context Window** — tokens used in your current session vs the model's limit, with a green/yellow/red indicator. Automatically detects Opus 4.7 1M sessions (1M limit); all other models use 200k.

**Billing Window** — output tokens used in the current rolling 5-hour window, with a configurable threshold. Resets on a rolling basis anchored to the top of the hour your first request landed in. Accurate to ±1 hour — the exact window boundary requires server-side data the app doesn't have.

**Weekly Usage** — three local token counts since the last weekly reset:
- **All tokens** — input + cache creation + cache reads + output
- **Excl. cache reads** — removes cache read tokens (large but cheap)
- **Input + output** — only tokens you directly sent and received

These are useful as relative trend indicators. They do not match Anthropic's server-side weekly % exactly — that formula is not publicly documented.

---

## What it cannot show

These are available in **Claude Desktop → Settings → Usage** and require server-side data:

- Exact weekly % matching Anthropic's "Plan usage"
- Per-bucket weekly limits (All models / Sonnet only / per-app)
- Context category breakdown (Messages / System tools / Skills / MCP tools / Memory / Autocompact buffer)

---

## Requirements

- macOS 14 Sonoma or later
- Claude Code in active use — CLI, IDE extensions, or the Code tab in the Mac Desktop app. All write to the same local session files this app reads.
- **Tested against Claude Pro and Max plans.** Team/Enterprise plans have different limits; defaults may need adjustment.

---

## Install

### Option A: DMG (easiest)
1. Download the latest `.dmg` from [Releases](https://github.com/scottblydotcom/claude-context-meter/releases)
2. Open the DMG, drag the app to Applications
3. Launch it — the gauge icon appears in your menu bar
4. Click the icon to see your usage

### Option B: Build from source
1. Clone this repo
2. Open `ClaudeContextMeter/ClaudeContextMeter.xcodeproj` in Xcode
3. Build and run (`⌘R`)

---

## Configuration

The app works out of the box with sensible defaults. Two settings are configurable:

**Launch at Login** — toggle in the popover footer.

**Weekly reset day/hour** — defaults to Tuesday at 9 PM (Claude Pro/Max). Confirm your plan's reset time in Claude Desktop → Settings → Usage, then adjust if needed:

```bash
# Example: reset on Wednesday at 8 PM
defaults write com.scottbly.ClaudeContextMeter weeklyResetWeekday 4
defaults write com.scottbly.ClaudeContextMeter weeklyResetHour 20
```

Weekday values: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat

**Billing token limit** — the threshold shown in the billing window gauge. Adjust to match what you observe on your plan:

```bash
defaults write com.scottbly.ClaudeContextMeter billingTokenLimit 131000
```

---

## How it works

Claude Code writes session data to JSONL files at `~/.claude/projects/`. The app watches these with `FSEvents`, parses on change, and updates the menu bar in real time. No network requests, no API keys, no telemetry — fully local.

---

## Known limitations

- **Claude Code sessions only** — reads files written by Claude Code (CLI, IDE extensions, Code tab). Desktop chat conversations are not captured.
- **Context window: pre-200k sessions show 200k denominator** — Opus 4.7 1M sessions are detected reactively once token usage crosses 200k. Until then, the denominator shows 200k. After crossing, the 1M limit is remembered for that session even after compaction.
- **Billing window ±1h accuracy** — JSONL files contain no billing boundary markers. The window anchor can be off by up to one hour. Cannot be fixed without a server-side API.
- **Weekly total is an estimate** — the three local counts bracket the answer; none will match Anthropic's server-side % exactly.
- **No historical charts** — current window only.

---

## Contributing

Issues and pull requests welcome. See the [backlog](docs/superpowers/plans/) for planned work.

---

## License

MIT
