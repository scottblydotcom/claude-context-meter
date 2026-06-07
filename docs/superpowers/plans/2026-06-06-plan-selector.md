# Plan Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native macOS Settings window with a Claude plan picker (Pro / Max 5x / Max 20x) and an editable token limit field, replacing the hardcoded 131,000 default and moving Launch at Login out of the popover footer.

**Architecture:** A new `ClaudePlan` enum owns the preset values and UserDefaults persistence. A new `SettingsView` uses `@AppStorage` to bind directly to UserDefaults — no extra ViewModel needed. The SwiftUI `Settings {}` scene wires it to ⌘, and to a gear button in the popover footer.

**Tech Stack:** Swift 6, SwiftUI, `@AppStorage`, `ServiceManagement` (SMAppService), XCTest

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Models/ClaudePlan.swift` | **Create** | Plan enum: labels, preset token limits, UserDefaults read/write |
| `Views/SettingsView.swift` | **Create** | Settings UI: plan picker, token limit field, Launch at Login toggle |
| `ClaudeContextMeterApp.swift` | **Modify** | Add `Settings { SettingsView() }` scene |
| `Views/PopoverContentView.swift` | **Modify** | Replace Launch at Login toggle with gear button in footer |
| `ClaudeContextMeterTests/ClaudeContextMeterTests.swift` | **Modify** | Add `ClaudePlanTests` class |

`BillingWindowCalculator.swift` — **no changes**. Its `tokenLimit` already reads `UserDefaults.standard.integer(forKey: "billingTokenLimit")` dynamically.

---

## Task 1: `ClaudePlan` enum

**Files:**
- Create: `ClaudeContextMeter/ClaudeContextMeter/Models/ClaudePlan.swift`
- Modify: `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift`

---

- [ ] **Step 1.1: Add `ClaudePlanTests` class to the existing test file**

Open `ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift` and append this class at the very end of the file, before the final `}` if there is one, or just at the bottom:

```swift
// MARK: - ClaudePlan

final class ClaudePlanTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "selectedPlan")
        UserDefaults.standard.removeObject(forKey: "billingTokenLimit")
    }

    func testProLabelAndLimit() {
        XCTAssertEqual(ClaudePlan.pro.label, "Pro")
        XCTAssertEqual(ClaudePlan.pro.tokenLimit, 131_000)
    }

    func testMax5xLabelAndLimit() {
        XCTAssertEqual(ClaudePlan.max5x.label, "Max 5x")
        XCTAssertEqual(ClaudePlan.max5x.tokenLimit, 655_000)
    }

    func testMax20xLabelAndLimit() {
        XCTAssertEqual(ClaudePlan.max20x.label, "Max 20x")
        XCTAssertEqual(ClaudePlan.max20x.tokenLimit, 2_620_000)
    }

    func testAllCasesHasThreePlans() {
        XCTAssertEqual(ClaudePlan.allCases.count, 3)
    }

    func testCurrentDefaultsToProWhenNothingStored() {
        UserDefaults.standard.removeObject(forKey: "selectedPlan")
        XCTAssertEqual(ClaudePlan.current, .pro)
    }

    func testCurrentReadsStoredPlan() {
        UserDefaults.standard.set("max5x", forKey: "selectedPlan")
        XCTAssertEqual(ClaudePlan.current, .max5x)
    }

    func testCurrentFallsBackToProForUnknownRaw() {
        UserDefaults.standard.set("enterprise", forKey: "selectedPlan")
        XCTAssertEqual(ClaudePlan.current, .pro)
    }

    func testSaveWritesBothKeys() {
        ClaudePlan.max5x.save()
        XCTAssertEqual(UserDefaults.standard.string(forKey: "selectedPlan"), "max5x")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "billingTokenLimit"), 655_000)
    }

    func testSaveMax20xWritesCorrectLimit() {
        ClaudePlan.max20x.save()
        XCTAssertEqual(UserDefaults.standard.string(forKey: "selectedPlan"), "max20x")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "billingTokenLimit"), 2_620_000)
    }
}
```

- [ ] **Step 1.2: Run tests to confirm they fail**

Press **Cmd+U** in Xcode.

Expected: `ClaudePlanTests` fails with *"Cannot find type 'ClaudePlan' in scope"*. All other existing tests should still pass.

- [ ] **Step 1.3: Create `ClaudePlan.swift`**

Create the file at `ClaudeContextMeter/ClaudeContextMeter/Models/ClaudePlan.swift`:

```swift
//
//  ClaudePlan.swift
//  ClaudeContextMeter
//

import Foundation

enum ClaudePlan: String, CaseIterable, Identifiable, Equatable {
    case pro    = "pro"
    case max5x  = "max5x"
    case max20x = "max20x"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pro:    return "Pro"
        case .max5x:  return "Max 5x"
        case .max20x: return "Max 20x"
        }
    }

    var tokenLimit: Int64 {
        switch self {
        case .pro:    return 131_000
        case .max5x:  return 655_000
        case .max20x: return 2_620_000
        }
    }

    /// Returns the plan matching the stored `selectedPlan` key, defaulting to `.pro`.
    static var current: ClaudePlan {
        let raw = UserDefaults.standard.string(forKey: "selectedPlan") ?? ""
        return ClaudePlan(rawValue: raw) ?? .pro
    }

    /// Writes this plan's raw value and preset token limit to UserDefaults.
    func save() {
        UserDefaults.standard.set(rawValue, forKey: "selectedPlan")
        UserDefaults.standard.set(Int(tokenLimit), forKey: BillingWindowCalculator.limitKey)
    }
}
```

> **Xcode note:** After creating the file on disk, drag it into the Xcode project navigator under the `Models` group so Xcode includes it in the target. If using Xcode's File → New menu, choose the `Models` group directly.

- [ ] **Step 1.4: Run tests to confirm they pass**

Press **Cmd+U**.

Expected: all `ClaudePlanTests` pass. All pre-existing tests still pass (56 total + 9 new = 65).

- [ ] **Step 1.5: Run security scan**

```bash
cd /Users/scottbly/Git/claude-context-meter && ./scripts/scan.sh
```

Expected: Gitleaks, Semgrep, and Trivy all pass with no findings.

- [ ] **Step 1.6: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Models/ClaudePlan.swift \
        ClaudeContextMeter/ClaudeContextMeterTests/ClaudeContextMeterTests.swift
git commit -m "feat: add ClaudePlan enum with preset token limits and UserDefaults persistence"
```

---

## Task 2: `SettingsView`

**Files:**
- Create: `ClaudeContextMeter/ClaudeContextMeter/Views/SettingsView.swift`

This is a SwiftUI view — no unit tests. Verify visually after wiring up in Task 3.

---

- [ ] **Step 2.1: Create `SettingsView.swift`**

Create the file at `ClaudeContextMeter/ClaudeContextMeter/Views/SettingsView.swift`:

```swift
//
//  SettingsView.swift
//  ClaudeContextMeter
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("selectedPlan") private var selectedPlanRaw: String = ClaudePlan.pro.rawValue
    @AppStorage(BillingWindowCalculator.limitKey) private var tokenLimit: Int = Int(ClaudePlan.pro.tokenLimit)
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var tokenLimitText: String = ""

    var body: some View {
        Form {
            Section("Claude Plan") {
                Picker("Plan", selection: $selectedPlanRaw) {
                    ForEach(ClaudePlan.allCases) { plan in
                        Text(plan.label).tag(plan.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedPlanRaw) { _, newRaw in
                    if let plan = ClaudePlan(rawValue: newRaw) {
                        tokenLimit = Int(plan.tokenLimit)
                        tokenLimitText = "\(tokenLimit)"
                    }
                }

                HStack {
                    TextField("Token limit", text: $tokenLimitText)
                        .onAppear { tokenLimitText = "\(tokenLimit)" }
                        .onSubmit { commitTokenLimit() }
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }
                Text("Adjust if you observe a different ceiling on your plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 240)
    }

    private func commitTokenLimit() {
        guard let value = Int(tokenLimitText), value > 1_000 else {
            tokenLimitText = "\(tokenLimit)"   // revert to last valid value
            return
        }
        tokenLimit = value
    }
}

#Preview {
    SettingsView()
}
```

> **Xcode note:** Add the file to the `Views` group in the project navigator.

- [ ] **Step 2.2: Build only (no run yet)**

Press **Cmd+B** in Xcode.

Expected: builds with no errors or warnings. (Can't visually verify until wired into the app in Task 3.)

---

## Task 3: Wire `Settings {}` scene + gear button in footer

**Files:**
- Modify: `ClaudeContextMeter/ClaudeContextMeter/ClaudeContextMeterApp.swift`
- Modify: `ClaudeContextMeter/ClaudeContextMeter/Views/PopoverContentView.swift`

---

- [ ] **Step 3.1: Add `Settings {}` scene to the app**

Open `ClaudeContextMeterApp.swift`. Replace the entire `body` computed property with:

```swift
var body: some Scene {
    MenuBarExtra {
        ContentView()
            .environmentObject(viewModel)
    } label: {
        StatusBarView(
            contextFill: viewModel.context?.fillPercent ?? 0,
            billingFill: viewModel.billing?.fillPercent ?? 0
        )
    }
    .menuBarExtraStyle(.window)

    Settings {
        SettingsView()
    }
}
```

- [ ] **Step 3.2: Replace the footer in `PopoverContentView`**

Open `PopoverContentView.swift`. Find the footer `HStack` (currently contains the Launch at Login toggle and Quit button). Replace it with:

```swift
// Footer
HStack {
    Button {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } label: {
        Image(systemName: "gearshape")
            .font(.caption)
    }
    .buttonStyle(.plain)
    .help("Settings")
    Spacer()
    Button("Quit") {
        NSApplication.shared.terminate(nil)
    }
    .buttonStyle(.plain)
    .font(.caption)
    .foregroundStyle(.secondary)
}
.padding(.horizontal)
.padding(.vertical, 8)
```

Also remove the `@State private var launchAtLogin` line at the top of `PopoverContentView` — it's no longer needed there:

```swift
// DELETE this line:
@State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
```

And remove the `import ServiceManagement` line at the top of `PopoverContentView.swift` if it's present.

- [ ] **Step 3.3: Build and run**

Press **Cmd+R** in Xcode (or Cmd+U to run tests, then launch manually).

**Verify the following:**

1. The popover footer now shows a ⚙ gear icon on the left and "Quit" on the right. No Launch at Login toggle in the footer.
2. Clicking the gear opens a Settings window with two sections: **Claude Plan** and **General**.
3. The Claude Plan section shows a "Plan" picker defaulting to "Pro" and a token limit field showing "131000".
4. The General section shows a Launch at Login toggle.
5. Pressing ⌘, also opens the Settings window.
6. Selecting "Max 5x" in the picker updates the token limit field to "655000".
7. Selecting "Max 20x" updates it to "2620000".
8. Manually editing the token limit field to e.g. "700000" and pressing Return keeps the picker on whichever plan was selected.
9. Entering a value ≤ 1000 and pressing Return reverts to the previous value.
10. Closing and reopening Settings shows the last saved plan and token limit.
11. The billing window gauge in the popover reflects the new token limit after the next refresh (click ↻ to force).

- [ ] **Step 3.4: Run tests**

Press **Cmd+U**.

Expected: all 65 tests pass.

- [ ] **Step 3.5: Run security scan**

```bash
cd /Users/scottbly/Git/claude-context-meter && ./scripts/scan.sh
```

Expected: all three tools pass.

- [ ] **Step 3.6: Commit**

```bash
git add ClaudeContextMeter/ClaudeContextMeter/Views/SettingsView.swift \
        ClaudeContextMeter/ClaudeContextMeter/ClaudeContextMeterApp.swift \
        ClaudeContextMeter/ClaudeContextMeter/Views/PopoverContentView.swift
git commit -m "feat: add Settings window with plan picker and adjustable token limit"
```

---

## Done

After Task 3 is committed, the feature is complete. Update the backlog: mark **Plan selector + billing window token limits** as complete and note the `selectedPlan` UserDefaults key in architecture notes.
