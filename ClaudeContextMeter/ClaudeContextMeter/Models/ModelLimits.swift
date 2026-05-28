//
//  ModelLimits.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import Foundation

enum ModelLimits {
    static let defaultContextWindow: Int64 = 200_000
    static let extendedContextWindow: Int64 = 1_000_000

    /// Only Opus 4.7 can use the extended 1M context window.
    private static let extendedContextModel = "claude-opus-4-7"

    /// Returns the context window limit for a session.
    ///
    /// Both Opus 4.7 variants (200k and 1M) report the same model string in JSONL.
    /// Detection is reactive: once `observedTokens` exceeds 200k for a given session,
    /// the 1M limit is persisted in UserDefaults so it survives autocompaction resets.
    /// UserDefaults keys older than 30 days are pruned on each call.
    ///
    /// **Boundary:** `observedTokens == 200_000` returns `defaultContextWindow` (200k).
    /// The threshold is `> 200_000` — a session exactly at the 200k limit has not yet
    /// exceeded it, so the 200k denominator is correct.
    ///
    /// **nil sessionId:** callers must guard against a nil sessionId and skip this
    /// function rather than coalescing to a shared sentinel, to avoid cross-session
    /// key collisions in UserDefaults.
    static func contextWindow(for model: String, sessionId: String, observedTokens: Int64) -> Int64 {
        guard model == extendedContextModel else { return defaultContextWindow }

        let limitKey = "sessionLimit_\(sessionId)"
        let dateKey  = "sessionLimitDate_\(sessionId)"
        let defaults = UserDefaults.standard

        // Prune eagerly on each call. The number of sessionLimitDate_ keys is bounded
        // by Opus 4.7 sessions in the past 30 days (typically single digits), so the
        // full UserDefaults snapshot is cheap and throttling is not necessary.
        pruneStaleEntries(defaults: defaults)

        // Already confirmed as 1M in a prior call — honour across compaction
        if defaults.bool(forKey: limitKey) {
            return extendedContextWindow
        }

        // First time we observe tokens exceeding the 200k boundary
        if observedTokens > defaultContextWindow {
            defaults.set(true, forKey: limitKey)
            defaults.set(Date(), forKey: dateKey)
            return extendedContextWindow
        }

        return defaultContextWindow
    }

    // MARK: - Private

    private static func pruneStaleEntries(defaults: UserDefaults) {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("sessionLimitDate_") {
            if let date = defaults.object(forKey: key) as? Date, date < cutoff {
                let sessionSuffix = String(key.dropFirst("sessionLimitDate_".count))
                defaults.removeObject(forKey: "sessionLimit_\(sessionSuffix)")
                defaults.removeObject(forKey: key)
            }
        }
    }
}
