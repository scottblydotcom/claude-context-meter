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
        .frame(minWidth: 320)
        .onAppear { loadData() }
    }

    private func loadData() {
        guard let url = JSONLParser.mostRecentSessionFile() else {
            statusText = "No session files found."
            return
        }

        guard let records = try? JSONLParser.parse(fileURL: url) else {
            statusText = "Failed to parse session file."
            return
        }

        // Deduplicate by requestId, keep only complete assistant records
        var seen = Set<String>()
        let complete = records.filter { record in
            guard record.isCompleteAssistantRecord,
                  let rid = record.requestId else { return false }
            return seen.insert(rid).inserted
        }

        guard let last = complete.last,
              let usage = last.message?.usage,
              let model = last.message?.model else {
            statusText = "No complete assistant records found.\nFile: \(url.lastPathComponent)"
            return
        }

        let limit = ModelLimits.contextWindow(for: model)
        let pct = Int(Double(usage.totalTokens) / Double(limit) * 100)

        statusText = """
        File: \(url.lastPathComponent)
        Model: \(model)
        Tokens used: \(usage.totalTokens) / \(limit)
        Context fill: \(pct)%
        (input: \(usage.inputTokens), cache: \(usage.cacheReadInputTokens), output: \(usage.outputTokens))
        """
    }
}

#Preview {
    ContentView()
}
