//
//  MetricsViewModel.swift
//  ClaudeContextMeter
//

import SwiftUI
import Combine

@MainActor
class MetricsViewModel: ObservableObject {
    @Published var context: ContextWindowMetrics?
    @Published var billing: BillingWindowMetrics?

    init() {
        refresh()
    }

    func refresh() {
        context = ContextWindowCalculator.calculate()
        billing = BillingWindowCalculator.calculate()
    }
}
