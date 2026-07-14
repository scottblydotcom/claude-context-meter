//
//  ModelLimits.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import Foundation

/// Marked `nonisolated` because this project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// without this, calls from the nonisolated ContextWindowCalculator would be Swift 6 errors.
nonisolated enum ModelLimits {
    static let defaultContextWindow: Int64 = 200_000
    static let extendedContextWindow: Int64 = 1_000_000

    /// Only Opus 4.7 can use the extended 1M context window.
    private static let extendedContextModel = "claude-opus-4-7"

    /// Single UserDefaults key storing all confirmed-1M sessions as [sessionId: confirmedDate].
    /// One key replaces the previous per-session key pairs (sessionLimit_<id>, sessionLimitDate_<id>),
    /// preventing namespace pollution and eliminating any need for dictionaryRepresentation().
    static let opusSessionLimitsKey = "opusSessionLimits"

    /// UserDefaults key tracking when we last ran the 30-day stale-entry prune.
    static let lastPruneDateKey = "sessionLimitsLastPruneDate"

    /// Returns the context window limit for a session.
    ///
    /// Both Opus 4.7 variants (200k and 1M) report the same model string in JSONL.
    /// Detection is reactive: once `observedTokens` exceeds 200k for a given session,
    /// the confirmation date is stored in a single `[String: Date]` dictionary under
    /// `opusSessionLimitsKey` in UserDefaults. This survives autocompaction resets
    /// and is pruned (entries older than 30 days removed) at most once every 24 hours.
    ///
    /// **Boundary:** `observedTokens == 200_000` returns `defaultContextWindow` (200k).
    /// The threshold is `> 200_000` — a session exactly at the 200k limit has not yet
    /// exceeded it, so the 200k denominator is correct.
    ///
    /// **Empty/nil sessionId:** callers must guard against nil before calling; this
    /// function guards against empty strings to prevent collisions on the "" key.
    static func contextWindow(for model: String, sessionId: String, observedTokens: Int64) -> Int64 {
        guard model == extendedContextModel, !sessionId.isEmpty else { return defaultContextWindow }

        let defaults = UserDefaults.standard
        pruneStaleEntriesIfNeeded(defaults: defaults)

        var limits = defaults.dictionary(forKey: opusSessionLimitsKey) as? [String: Date] ?? [:]

        // Already confirmed as 1M in a prior call — honour across compaction
        if limits[sessionId] != nil {
            return extendedContextWindow
        }

        // First time we observe tokens exceeding the 200k boundary
        if observedTokens > defaultContextWindow {
            limits[sessionId] = Date()
            defaults.set(limits, forKey: opusSessionLimitsKey)
            return extendedContextWindow
        }

        return defaultContextWindow
    }

    // MARK: - Private

    /// Prunes sessions confirmed more than 30 days ago. Throttled to run at most once
    /// per 24 hours — the operation is cheap (one dict read + filter + write) but
    /// called on every FSEvent and 30s heartbeat for Opus 4.7 sessions.
    private static func pruneStaleEntriesIfNeeded(defaults: UserDefaults) {
        let now = Date()
        if let lastPrune = defaults.object(forKey: lastPruneDateKey) as? Date,
           now.timeIntervalSince(lastPrune) < 24 * 60 * 60 {
            return
        }
        defaults.set(now, forKey: lastPruneDateKey)

        var limits = defaults.dictionary(forKey: opusSessionLimitsKey) as? [String: Date] ?? [:]
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let originalCount = limits.count
        limits = limits.filter { $0.value >= cutoff }
        if limits.count != originalCount {
            defaults.set(limits, forKey: opusSessionLimitsKey)
        }
    }
}
