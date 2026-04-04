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
        }
        .frame(width: 320)
        .onAppear { viewModel.refresh() }
    }
}

#Preview {
    PopoverContentView()
        .environmentObject(MetricsViewModel())
}
