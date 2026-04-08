//
//  BillingWindowSection.swift
//  ClaudeContextMeter
//

import SwiftUI

struct BillingWindowSection: View {
    let metrics: BillingWindowMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Billing Window")
                    .font(.headline)
                Spacer()
                Text("resets in \(metrics.timeUntilReset)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GaugeRowView(label: "\(metrics.outputTokens.formatted()) / \(metrics.tokenLimit.formatted()) output tokens", percent: metrics.fillPercent)

            HStack {
                Text("started \(metrics.windowStartTime)")
                Spacer()
                Text("resets at \(metrics.nextResetTime)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    BillingWindowSection(metrics: BillingWindowMetrics(
        outputTokens: 61_670,
        tokenLimit: 131_000,
        windowStart: Date().addingTimeInterval(-3600),
        nextReset: Date().addingTimeInterval(14100)
    ))
    .padding()
    .frame(width: 300)
}
