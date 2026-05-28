//
//  ContextWindowCalculator.swift
//  ClaudeContextMeter
//

import Foundation

enum ContextWindowCalculator {

    /// Finds the most recent session file, parses it, and returns context window metrics.
    /// Returns nil if no complete assistant record can be found.
    static func calculate() -> ContextWindowMetrics? {
        guard let url = JSONLParser.mostRecentSessionFile() else { return nil }
        guard let records = try? JSONLParser.parse(fileURL: url) else { return nil }

        // Deduplicate by requestId, keep only complete assistant records
        var seen = Set<String>()
        let complete = records.filter { record in
            guard record.isCompleteAssistantRecord,
                  let rid = record.requestId else { return false }
            return seen.insert(rid).inserted
        }

        guard let last = complete.last,
              let usage = last.message?.usage,
              let model = last.message?.model else { return nil }

        // A nil sessionId means the JSONL record is malformed. Skip 1M detection entirely
        // rather than coalescing to a shared "unknown" key, which would let one 1M session
        // permanently mark all future nil-sessionId Opus 4.7 sessions as 1M.
        guard let sessionId = last.sessionId else {
            let limit = ModelLimits.defaultContextWindow
            return ContextWindowMetrics(
                fileName: url.lastPathComponent,
                model: model,
                totalTokens: usage.totalTokens,
                contextLimit: limit,
                inputTokens: usage.inputTokens,
                cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                outputTokens: usage.outputTokens
            )
        }
        let limit = ModelLimits.contextWindow(
            for: model,
            sessionId: sessionId,
            observedTokens: usage.totalTokens
        )

        return ContextWindowMetrics(
            fileName: url.lastPathComponent,
            model: model,
            totalTokens: usage.totalTokens,
            contextLimit: limit,
            inputTokens: usage.inputTokens,
            cacheReadTokens: usage.cacheReadInputTokens ?? 0,
            outputTokens: usage.outputTokens
        )
    }
}
