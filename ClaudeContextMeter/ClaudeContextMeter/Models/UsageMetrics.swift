//
//  UsageMetrics.swift
//  ClaudeContextMeter
//

import Foundation

/// The calculated context window metrics for the most recent Claude session turn.
struct ContextWindowMetrics {
    let fileName: String
    let model: String
    let totalTokens: Int
    let contextLimit: Int
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int

    /// Percentage of context window filled (0–100).
    var fillPercent: Int {
        guard contextLimit > 0 else { return 0 }
        return Int((Double(totalTokens) / Double(contextLimit)) * 100)
    }
}
