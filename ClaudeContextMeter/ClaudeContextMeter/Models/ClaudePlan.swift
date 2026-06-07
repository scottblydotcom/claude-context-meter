//
//  ClaudePlan.swift
//  ClaudeContextMeter
//

import Foundation

enum ClaudePlan: String, CaseIterable, Identifiable, Equatable {
    static let planKey = "selectedPlan"

    case pro    = "pro"
    case max5x  = "max5x"
    case max20x = "max20x"

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

    func save() {
        UserDefaults.standard.set(rawValue, forKey: ClaudePlan.planKey)
        UserDefaults.standard.set(Int(tokenLimit), forKey: BillingWindowCalculator.limitKey)
    }
}
