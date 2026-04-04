//
//  BillingWindowCalculator.swift
//  ClaudeContextMeter
//

import Foundation

enum BillingWindowCalculator {

    /// UserDefaults key for the billing token limit.
    static let limitKey = "billingTokenLimit"

    /// Default output token limit for the 5-hour billing window.
    static let defaultLimit = 88_000

    /// The current billing token limit (user-configurable, falls back to default).
    static var tokenLimit: Int {
        let stored = UserDefaults.standard.integer(forKey: limitKey)
        return stored > 0 ? stored : defaultLimit
    }

    /// Sums output tokens across all sessions in the last 5 hours, deduplicated by requestId.
    static func calculate() -> BillingWindowMetrics {
        let cutoff = Date().addingTimeInterval(-5 * 3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var seen = Set<String>()
        var totalOutputTokens = 0

        for url in JSONLParser.allSessionFiles() {
            guard let records = try? JSONLParser.parse(fileURL: url) else { continue }

            for record in records {
                guard record.isCompleteAssistantRecord,
                      let rid = record.requestId,
                      seen.insert(rid).inserted,
                      let timestamp = formatter.date(from: record.timestamp),
                      timestamp >= cutoff,
                      let outputTokens = record.message?.usage?.outputTokens
                else { continue }

                totalOutputTokens += outputTokens
            }
        }

        return BillingWindowMetrics(outputTokens: totalOutputTokens, tokenLimit: tokenLimit)
    }
}
