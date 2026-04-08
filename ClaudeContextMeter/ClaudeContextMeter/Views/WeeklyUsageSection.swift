//
//  WeeklyUsageSection.swift
//  ClaudeContextMeter
//

import SwiftUI

struct WeeklyUsageSection: View {
    let metrics: WeeklyUsageMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weekly Usage")
                    .font(.headline)
                Spacer()
                Text("resets \(metrics.nextResetDisplay)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                row(label: "All tokens",        value: metrics.allTokens)
                row(label: "Excl. cache reads", value: metrics.noCacheRead)
                row(label: "Input + output",    value: metrics.inputOutputOnly)
                row(label: "Peak-adjusted",     value: metrics.peakAdjustedTokens)
            }
        }
    }

    private func row(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.formatted())
                .monospacedDigit()
        }
        .font(.caption)
    }
}

#Preview {
    WeeklyUsageSection(metrics: WeeklyUsageMetrics(
        allTokens:           1_158_100,
        noCacheRead:            63_560,
        inputOutputOnly:        21_550,
        peakAdjustedTokens:  1_420_800,
        windowStart:         Date().addingTimeInterval(-3600),
        nextReset:           Date().addingTimeInterval(6 * 24 * 3600)
    ))
    .padding()
    .frame(width: 320)
}
