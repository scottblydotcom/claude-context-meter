//
//  ClaudePlan.swift
//  ClaudeContextMeter
//

import Foundation

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
        case .pro:    return ("Pro",     131_000)
        case .max5x:  return ("Max 5x",  655_000)
        case .max20x: return ("Max 20x", 2_620_000)
        }
    }

    var label: String { spec.label }
    var tokenLimit: Int64 { spec.tokenLimit }

    static var current: ClaudePlan {
        guard let raw = UserDefaults.standard.string(forKey: ClaudePlan.planKey),
              let plan = ClaudePlan(rawValue: raw) else {
            return .pro
        }
        return plan
    }

    /// Writes this plan's preset token limit and plan key to UserDefaults.
    /// Not called by SettingsView (which drives both keys via @AppStorage directly);
    /// available for programmatic use and covered by unit tests.
    func save() {
        UserDefaults.standard.set(rawValue, forKey: ClaudePlan.planKey)
        UserDefaults.standard.set(Int(clamping: tokenLimit), forKey: BillingWindowCalculator.limitKey)
    }
}
