//
//  ContextWindowCalculator.swift
//  ClaudeContextMeter
//

import Foundation

/// Marked `nonisolated` because this project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// without this, every member would implicitly inherit @MainActor isolation and calls from
/// RefreshCoordinator (an actor, not @MainActor) would be Swift 6 language-mode errors. This
/// is pure computation with no UI state — safe and intended to run off the main thread.
nonisolated enum ContextWindowCalculator {

    /// Core calculation: accepts the most-recent session file URL plus its pre-parsed
    /// records (avoids redundant file I/O when called from RefreshCoordinator, which
    /// resolves records once per file across all three calculators via JSONLParseCache).
    static func calculate(mostRecentFile: URL?, records: [SessionRecord]) -> ContextWindowMetrics? {
        guard let url = mostRecentFile else { return nil }

        var seen = Set<String>()
        let complete = records.filter { record in
            guard record.isCompleteAssistantRecord,
                  let rid = record.requestId else { return false }
            return seen.insert(rid).inserted
        }

        guard let last = complete.last,
              let usage = last.message?.usage,
              let model = last.message?.model else { return nil }

        // The context window is determined by the model ID (a fixed per-model property), so a
        // missing/malformed sessionId no longer affects the denominator. The safety-net
        // comparison uses the INPUT-side sum (excludes output): the mapped window is max input,
        // and counting generated output would falsely promote a maxed-out 200k model to /1M.
        let limit = ModelLimits.contextWindow(
            for: model,
            observedInputTokens: usage.inputSideTokens
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

    /// Convenience wrapper: parses mostRecentFile, then delegates to
    /// calculate(mostRecentFile:records:). Prefer the records: overload directly when
    /// records are already available (e.g. from RefreshCoordinator's JSONLParseCache)
    /// to avoid redundant parsing.
    static func calculate(mostRecentFile: URL?) -> ContextWindowMetrics? {
        guard let url = mostRecentFile, let records = try? JSONLParser.parse(fileURL: url) else { return nil }
        return calculate(mostRecentFile: url, records: records)
    }

    /// Convenience wrapper: finds the most recent session file, then delegates to
    /// calculate(mostRecentFile:).
    static func calculate() -> ContextWindowMetrics? {
        calculate(mostRecentFile: JSONLParser.mostRecentSessionFile())
    }
}
