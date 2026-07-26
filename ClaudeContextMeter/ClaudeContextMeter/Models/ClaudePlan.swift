//
//  ClaudePlan.swift
//  ClaudeContextMeter
//

import Foundation

/// Single injection seam for all of the app's `UserDefaults` access. Production uses
/// `.standard`; the unit tests point this at a throwaway suite so they never read or clobber
/// the user's real preferences (see claude-context-meter-8ax — the test suite previously
/// deleted a live `selectedPlan`/`billingTokenLimit` because it wrote to the shared prod
/// domain). `nonisolated(unsafe)` because it's a mutable global read from the nonisolated
/// calculators (off the main thread) and swapped by tests; the value is only ever reassigned
/// in test setUp/tearDown, never concurrently with reads in production (production never writes
/// it — it stays `.standard`, so reads observe an effectively-immutable value).
///
/// The swap-in-setUp isolation assumes **serial** test execution (the scheme's TestableReference
/// is not marked `parallelizable`). If parallel test execution is ever enabled, two test classes
/// swapping this global would race — move to per-call store injection at that point rather than a
/// shared global. (Surfaced by an outside-family fleet review, 2026-07-26.)
nonisolated enum AppPreferences {
    nonisolated(unsafe) static var store: UserDefaults = .standard
}

/// Marked `nonisolated` because this project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// without this, BillingWindowCalculator.defaultLimit (nonisolated) couldn't reference
/// `ClaudePlan.pro.tokenLimit` at compile time. nonisolated is still freely callable from
/// @MainActor contexts (SettingsView, MetricsViewModel), so this doesn't restrict UI usage.
nonisolated enum ClaudePlan: String, CaseIterable, Identifiable, Equatable {
    static let planKey = "selectedPlan"

    case pro
    case max5x
    case max20x

    var id: String { rawValue }

    /// Per-plan display label and billing-window token limit, in one place so adding or
    /// adjusting a plan's data is a single switch case rather than two switches kept in sync.
    private var spec: (label: String, tokenLimit: Int64) {
        switch self {
        case .pro:    return ("Pro", 131_000)
        case .max5x:  return ("Max 5x", 655_000)
        case .max20x: return ("Max 20x", 2_620_000)
        }
    }

    var label: String { spec.label }
    var tokenLimit: Int64 { spec.tokenLimit }

    static var current: ClaudePlan {
        guard let raw = AppPreferences.store.string(forKey: ClaudePlan.planKey),
              let plan = ClaudePlan(rawValue: raw) else {
            return .pro
        }
        return plan
    }

    /// Writes this plan's preset token limit and plan key to UserDefaults.
    /// Not called by SettingsView (which drives both keys via @AppStorage directly);
    /// available for programmatic use and covered by unit tests.
    func save() {
        AppPreferences.store.set(rawValue, forKey: ClaudePlan.planKey)
        AppPreferences.store.set(Int(clamping: tokenLimit), forKey: BillingWindowCalculator.limitKey)
    }
}
