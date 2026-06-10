//
//  ClaudePlan.swift
//  ClaudeContextMeter
//

import Foundation

enum ClaudePlan: String, CaseIterable, Identifiable, Equatable {
    static let planKey = "selectedPlan"

    case pro
    case max5x
    case max20x

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pro:    return "Pro"
        case .max5x:  return "Max 5x"
        case .max20x: return "Max 20x"
        }
    }

    var tokenLimit: Int64 {
        switch self {
        case .pro:    return 131_000
        case .max5x:  return 655_000
        case .max20x: return 2_620_000
        }
    }

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
