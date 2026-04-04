//
//  ContentView.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import SwiftUI

struct ContentView: View {
    @State private var statusText = "Reading..."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Context Meter")
                .font(.headline)
            Text(statusText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 360, minHeight: 260)
        .onAppear { loadData() }
    }

    private func loadData() {
        let context = ContextWindowCalculator.calculate()
        let billing = BillingWindowCalculator.calculate()

        var lines: [String] = []

        if let c = context {
            lines += [
                "── Context Window ──────────────",
                "File:  \(c.fileName)",
                "Model: \(c.model)",
                "Fill:  \(c.fillPercent)%  (\(c.totalTokens) / \(c.contextLimit))",
                "       in \(c.inputTokens)  cache \(c.cacheReadTokens)  out \(c.outputTokens)",
            ]
        } else {
            lines.append("Context window: no data")
        }

        lines.append("")
        lines += [
            "── Billing Window (5 hr) ───────",
            "Output tokens: \(billing.outputTokens) / \(billing.tokenLimit)",
            "Fill:  \(billing.fillPercent)%",
            "Resets in: \(billing.timeUntilReset)",
        ]

        statusText = lines.joined(separator: "\n")
    }
}

#Preview {
    ContentView()
}
