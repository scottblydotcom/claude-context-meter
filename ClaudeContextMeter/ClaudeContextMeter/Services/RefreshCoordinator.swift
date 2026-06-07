//
//  RefreshCoordinator.swift
//  ClaudeContextMeter
//

import Foundation

/// Off-main-thread coordinator: performs one directory scan per refresh cycle and
/// passes derived file lists to the three metric calculators. Returns nil when called
/// within `minimumInterval` of the previous refresh (debounced).
actor RefreshCoordinator {

    private var lastRefreshDate: Date = .distantPast
    let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 5) {
        self.minimumInterval = minimumInterval
    }

    func refresh() async -> (context: ContextWindowMetrics?,
                              billing: BillingWindowMetrics,
                              weekly: WeeklyUsageMetrics)? {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshDate) >= minimumInterval else {
            return nil
        }
        lastRefreshDate = now

        let (mostRecent, billingFiles, weeklyFiles) = JSONLParser.scanAllFiles(relativeTo: now)

        let context = ContextWindowCalculator.calculate(mostRecentFile: mostRecent)
        let billing = BillingWindowCalculator.calculate(files: billingFiles)
        let weekly  = WeeklyUsageCalculator.calculate(files: weeklyFiles)

        return (context, billing, weekly)
    }
}
