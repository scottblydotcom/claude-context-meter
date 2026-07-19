//
//  SettingsView.swift
//  ClaudeContextMeter
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(ClaudePlan.planKey) private var selectedPlanRaw: String = ClaudePlan.pro.rawValue
    @AppStorage(BillingWindowCalculator.limitKey) private var tokenLimit: Int = Int(ClaudePlan.pro.tokenLimit)
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var tokenLimitText: String
    @FocusState private var tokenFieldFocused: Bool

    init() {
        let stored = UserDefaults.standard.integer(forKey: BillingWindowCalculator.limitKey)
        let effective = stored > 0 ? stored : Int(ClaudePlan.pro.tokenLimit)
        _tokenLimitText = State(initialValue: "\(effective)")
    }

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
                        let newLimit = Int(clamping: plan.tokenLimit)
                        tokenLimit = newLimit
                        tokenLimitText = "\(newLimit)"
                    }
                }

                HStack {
                    TextField("Token limit", text: $tokenLimitText)
                        .focused($tokenFieldFocused)
                        .onSubmit { commitTokenLimit() }
                        .onChange(of: tokenFieldFocused) { _, focused in
                            if !focused { commitTokenLimit() }
                        }
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
                        let isCurrentlyEnabled = SMAppService.mainApp.status == .enabled
                        guard enabled != isCurrentlyEnabled else { return }
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = isCurrentlyEnabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // This app is LSUIElement (no Dock icon), so the Settings window is created
            // but macOS never brings it to the foreground on its own — it opens behind
            // whatever app currently has focus and looks like the click did nothing.
            NSApp.activate(ignoringOtherApps: true)
            Self.bringSettingsWindowToActiveSpace()
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            // Sync the text field to the current stored limit. Use the Pro default
            // as the display fallback if stored is 0 — BillingWindowCalculator already
            // applies the same fallback in its own calculation, so no UserDefaults write
            // is needed (which would spuriously fire UserDefaults.didChangeNotification).
            tokenLimitText = tokenLimit > 0 ? "\(tokenLimit)" : "\(Int(ClaudePlan.pro.tokenLimit))"
        }
        .frame(width: 360, height: 240)
    }

    private func commitTokenLimit() {
        // Strip non-digit characters so formatted input (e.g. "131,000") parses correctly.
        let digits = tokenLimitText.filter { $0.isNumber }
        guard let value = Int(digits), value > 1_000 else {
            tokenLimitText = "\(tokenLimit)"   // revert to last valid value
            return
        }
        guard value != tokenLimit else { return }  // no-op on double-fire (e.g. Return key)
        tokenLimit = value
    }

    /// SwiftUI's Settings window uses a stable frame-autosave name we can match on
    /// (confirmed via `defaults read`, key "NSWindow Frame com_apple_SwiftUI_Settings_window").
    ///
    /// **Known limitation (manually verified 2026-07-18):** `.moveToActiveSpace` does NOT
    /// reliably pull the window to whichever Space/screen the user is currently viewing
    /// when they click the gear icon — if the window is on a different Space than the one
    /// currently active, the click does nothing visible and the window stays put. It *does*
    /// correctly resolve the more common case this fix targets: the window already being on
    /// the user's current Space but buried behind another app's focus, or the user having
    /// since switched to the Space where the window already lives (at which point it's
    /// frontmost and reachable, no further action needed). True "always jump to me from any
    /// Space" behavior was attempted and abandoned — see the old `feature/settings-window-focus`
    /// branch — and isn't solved here. Workaround if you land somewhere the window isn't
    /// visible: switch to the Space/screen it's actually on (Mission Control), it'll be there.
    static func bringSettingsWindowToActiveSpace() {
        guard let window = NSApp.windows.first(where: {
            $0.frameAutosaveName == "com_apple_SwiftUI_Settings_window"
        }) else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
    }
}

#Preview {
    SettingsView()
}
