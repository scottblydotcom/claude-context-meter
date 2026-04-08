//
//  ContextWindowSection.swift
//  ClaudeContextMeter
//

import SwiftUI

struct ContextWindowSection: View {
    let metrics: ContextWindowMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context Window")
                .font(.headline)

            GaugeRowView(
                label: "\(metrics.totalTokens.formatted()) / \(metrics.contextLimit.formatted()) tokens",
                percent: metrics.fillPercent)

            HStack(spacing: 12) {
                statView(label: "Model", value: metrics.model)
                Spacer()
            }

            HStack(spacing: 16) {
                statView(label: "Input", value: metrics.inputTokens.formatted())
                statView(label: "Cache", value: metrics.cacheReadTokens.formatted())
                statView(label: "Output", value: metrics.outputTokens.formatted())
                Spacer()
            }
        }
    }

    private func statView(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContextWindowSection(metrics: ContextWindowMetrics(
        fileName: "session.jsonl",
        model: "claude-sonnet-4-6",
        totalTokens: 116_000,
        contextLimit: 200_000,
        inputTokens: 1,
        cacheReadTokens: 115_755,
        outputTokens: 244
    ))
    .padding()
    .frame(width: 300)
}
