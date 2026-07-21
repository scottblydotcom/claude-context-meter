//
//  PopoverContentView.swift
//  ClaudeContextMeter
//

import SwiftUI

struct PopoverContentView: View {
    @EnvironmentObject private var viewModel: MetricsViewModel

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
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Settings")
                .simultaneousGesture(TapGesture().onEnded {
                    // Covers the case where the Settings window is already open but
                    // buried behind another app — SettingsView's own onAppear only
                    // fires on a fresh open, not when an existing window regains focus.
                    // Does NOT reliably pull the window across from a different Space
                    // than the one currently active — see the known-limitation note on
                    // SettingsView.bringSettingsWindowToActiveSpace() for what this
                    // does and doesn't cover; kept here anyway since it's a correct,
                    // low-cost no-op when the window is already on this Space.
                    NSApp.activate(ignoringOtherApps: true)
                    SettingsView.bringSettingsWindowToActiveSpace()
                })
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
