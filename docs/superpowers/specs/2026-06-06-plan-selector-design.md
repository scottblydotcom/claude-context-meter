# Plan Selector — Design Spec
**Date:** 2026-06-06
**Status:** Approved

## Background

Claude Context Meter's billing window gauge is calibrated against a hardcoded token limit
(131,000 output tokens, approximating the Pro plan). Users on Max plans were seeing the
gauge read against the wrong ceiling. A temporary workaround (`defaults write
com.scottbly.ClaudeContextMeter billingTokenLimit 655000`) exists but is not user-facing.

The app tracks Claude output token consumption via Claude Code and Claude Desktop app JSONL
logs. It does not connect to any Anthropic API and has no way to read the true per-plan
limit server-side. All limits are approximations based on observed behavior.

## Goals

- Let users select their Anthropic plan so the gauge reads against the right ceiling.
- Allow the token limit to be manually adjusted, because our preset values are estimates and
  users may observe a different real-world ceiling.
- Move "Launch at Login" out of the footer and into a proper Settings window.
- Keep the UI simple and native macOS.

## Out of Scope

- Free tier (Claude Code requires a paid Anthropic subscription; no Free option needed).
- Network calls or API-based limit lookup.
- Cost tracking or weekly usage limit configuration (separate backlog items).

---

## Data Model

### Plan Presets

| Plan | Token Limit | Notes |
|------|-------------|-------|
| Pro  | 131,000     | Current default; value is approximate |
| Max 5x | 655,000  | 5× Pro estimate; approximate |
| Max 20x | 2,620,000 | 20× Pro estimate; approximate |

### UserDefaults Keys

| Key | Type | Description |
|-----|------|-------------|
| `billingTokenLimit` | `Int` | Token limit used in calculations. Already exists. |
| `selectedPlan` | `String` | Persists the picker selection: `"pro"`, `"max5x"`, `"max20x"`. New. |

The two keys are independent after initial selection: choosing a plan writes both, but
editing the token limit field only writes `billingTokenLimit`. On app launch, the picker
reads `selectedPlan` and the field reads `billingTokenLimit`.

If `selectedPlan` is absent (fresh install or existing install before this feature), the
picker defaults to `.pro` and the field shows 131,000 (existing `defaultLimit` fallback).

### `ClaudePlan` Enum (new file: `ClaudePlan.swift`)

```swift
enum ClaudePlan: String, CaseIterable, Identifiable {
    case pro    = "pro"
    case max5x  = "max5x"
    case max20x = "max20x"

    var id: String { rawValue }

    var label: String { ... }          // "Pro", "Max 5x", "Max 20x"
    var tokenLimit: Int64 { ... }      // preset value per table above

    static var current: ClaudePlan { ... }   // reads selectedPlan from UserDefaults
    func save() { ... }                      // writes selectedPlan + billingTokenLimit
}
```

`BillingWindowCalculator` requires no logic changes — `tokenLimit` already reads from
UserDefaults dynamically.

---

## Architecture

### New Scene: `Settings {}`

Add a SwiftUI `Settings { SettingsView() }` scene to `ClaudeContextMeterApp.swift`.
This creates a native macOS Settings window accessible via ⌘, and programmatically.

### Gear Button (footer)

Replace the current footer layout with a version that:
- Retains the **Quit** button (right side)
- Adds a **gear icon button** (left side, `.plain` style) that calls
  `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`
- Removes the **Launch at Login** toggle (moved to SettingsView)

### `SettingsView` (new file: `Views/SettingsView.swift`)

A single-pane `Form` containing:

1. **Plan section**
   - `Picker("Plan", selection: $selectedPlan)` — inline or menu style, lists the three
     `ClaudePlan` cases by label
   - Changing the picker writes both `selectedPlan` and `billingTokenLimit` via
     `ClaudePlan.save()`

2. **Token limit section**
   - Label: *"Observed token limit (approximate)"*
   - A numeric-only `TextField` bound to `billingTokenLimit` as an `Int64`
   - Editing the field writes only `billingTokenLimit`; the picker does not change
   - A short note beneath: *"Adjust if you observe a different ceiling on your plan."*

3. **General section**
   - `Toggle("Launch at Login", isOn: $launchAtLogin)` — same SMAppService logic as
     current footer implementation

Window size: fixed, approximately 360 × 220 pt (standard macOS Settings panel).

---

## State Management

`SettingsView` holds two `@AppStorage` bindings:
- `@AppStorage("selectedPlan") var selectedPlanRaw: String`
- `@AppStorage("billingTokenLimit") var tokenLimit: Int`

`@AppStorage` writes to `UserDefaults` on every change, so `BillingWindowCalculator` picks
up new values on the next refresh without any additional plumbing.

---

## Error Handling

- If the user types a non-numeric or zero value in the token limit field, the field rejects
  the input or reverts to the last valid value on focus loss.
- If `SMAppService` registration fails (Launch at Login toggle), revert the toggle — same
  behavior as the current footer implementation.

---

## Files Changed

| File | Change |
|------|--------|
| `ClaudeContextMeterApp.swift` | Add `Settings { SettingsView() }` scene |
| `Views/PopoverContentView.swift` | Remove Launch at Login toggle; add gear button to footer |
| `Views/SettingsView.swift` | **New** — plan picker, token limit field, launch at login |
| `Models/ClaudePlan.swift` | **New** — plan enum with presets and UserDefaults helpers |
| `Services/BillingWindowCalculator.swift` | No logic changes |

---

## Testing

- Selecting each plan preset writes the correct `billingTokenLimit` to UserDefaults.
- Editing the token limit field does not change `selectedPlan`.
- On relaunch, the picker and field restore to their last saved values.
- A fresh install (no prior UserDefaults) defaults to Pro / 131,000.
- Launch at Login toggle in Settings behaves identically to the old footer toggle.
- Gear button opens the Settings window; ⌘, also opens it.
