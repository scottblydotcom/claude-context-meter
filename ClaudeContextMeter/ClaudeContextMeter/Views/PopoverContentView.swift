//
//  PopoverContentView.swift
//  ClaudeContextMeter
//

import SwiftUI
import ServiceManagement

struct PopoverContentView: View {
    @EnvironmentObject private var viewModel: MetricsViewModel
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Text("Claude Context Meter")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding()

            Divider()

            // Context Window
            if let context = viewModel.context {
                ContextWindowSection(metrics: context)
                    .padding()
            } else {
                Text("No session data found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Divider()

            // Billing Window
            if let billing = viewModel.billing {
                BillingWindowSection(metrics: billing)
                    .padding()
            }

            Divider()

            // Weekly Usage
            if let weekly = viewModel.weekly {
                WeeklyUsageSection(metrics: weekly)
                    .padding()
            }

            Divider()

            // Footer
            HStack {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Revert toggle if registration fails
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
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
        }
        .frame(width: 320)
    }
}

#Preview {
    PopoverContentView()
        .environmentObject(MetricsViewModel())
}
