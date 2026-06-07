//
//  ContextWindowCalculator.swift
//  ClaudeContextMeter
//

import Foundation

enum ContextWindowCalculator {

    /// Core calculation: accepts the most-recent session file URL (avoids redundant
    /// directory scans when called from RefreshCoordinator).
    static func calculate(mostRecentFile: URL?) -> ContextWindowMetrics? {
        guard let url = mostRecentFile else { return nil }
        guard let records = try? JSONLParser.parse(fileURL: url) else { return nil }

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

    /// Convenience wrapper: finds the most recent session file, then delegates to
    /// calculate(mostRecentFile:).
    static func calculate() -> ContextWindowMetrics? {
        calculate(mostRecentFile: JSONLParser.mostRecentSessionFile())
    }
}
