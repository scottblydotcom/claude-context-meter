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
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
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
