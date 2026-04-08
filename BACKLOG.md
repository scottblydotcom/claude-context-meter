# Backlog

## Infrastructure

### Move project to GitHub
**Added:** 2026-04-07

Create a public GitHub repo, push the project, and set up Issues for tracking going forward.

**Priority:** Soon

## Features

### Best practice tips
**Added:** 2026-04-08

In-app guidance (Help menu or tooltip) on how to use Claude efficiently to stay within weekly/billing limits. E.g., keep conversations focused, start new sessions to avoid carrying large context, work outside peak hours when possible.

**Priority:** Medium

### README
**Added:** 2026-04-08

Public-facing README covering: what the app does, how to install, how to configure reset day/hour, what each metric means, and limitations (JSONL-based, local only).

**Priority:** Soon (needed before GitHub push)

### Help menu
**Added:** 2026-04-08

Standard macOS Help menu item in the menu bar app. Could link to README, show keyboard shortcuts, or surface the best practice tips inline.

**Priority:** Medium

### Peak billing time tokens as % of total
**Added:** 2026-04-08

Show peak-hour tokens as a percentage of total weekly tokens. Useful metric to help users understand how much of their usage lands in the 2× multiplier window (Mon–Fri 5–11 AM PT). Helps them see whether shifting usage to off-peak hours would meaningfully extend their weekly limit.

**Example display:** "42% of tokens used during peak hours"

**Priority:** Medium

## Bugs

### App hangs in uninterruptible kernel state on crash
**Reported:** 2026-04-07

The app was found stuck in `SX` process state — received kill signal but could not exit due to an uninterruptible kernel wait. Force Quit in Activity Monitor had no effect, and `kill -9` from Terminal also failed. Required a full system reboot to clear.

This should not be possible. The app is holding a kernel resource (likely a file handle, network socket, or system API call) that never times out and cannot be interrupted. Needs investigation into what I/O or system calls the app is making and whether they need timeouts or cancellation handling.

**Impact:** User must reboot to recover.
**Priority:** High
