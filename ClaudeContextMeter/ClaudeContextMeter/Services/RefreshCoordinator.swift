//
//  RefreshCoordinator.swift
//  ClaudeContextMeter
//

import Foundation

struct RefreshResult {
    let context: ContextWindowMetrics?
    let billing: BillingWindowMetrics
    let weekly: WeeklyUsageMetrics
}

/// Off-main-thread coordinator: performs one directory scan per refresh cycle and
/// passes derived file lists to the three metric calculators. Returns nil when called
/// within `minimumInterval` of the previous refresh (debounced).
actor RefreshCoordinator {

    private var lastRefreshDate: Date = .distantPast
    let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 5) {
        self.minimumInterval = minimumInterval
    }

    func refresh() async -> RefreshResult? {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshDate) >= minimumInterval else {
            return nil
        }
        lastRefreshDate = now

        let scan = JSONLParser.scanAllFiles(relativeTo: now)

        let context = ContextWindowCalculator.calculate(mostRecentFile: scan.mostRecent)
        let billing = BillingWindowCalculator.calculate(files: scan.billingFiles)
        let weekly  = WeeklyUsageCalculator.calculate(files: scan.weeklyFiles)

        return RefreshResult(context: context, billing: billing, weekly: weekly)
    }
}
