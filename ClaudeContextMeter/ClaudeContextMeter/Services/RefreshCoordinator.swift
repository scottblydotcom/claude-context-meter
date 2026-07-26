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

/// Off-main-thread coordinator: performs one directory scan per refresh cycle, resolves
/// each relevant file's records through a JSONLParseCache (so unchanged files are never
/// re-read or re-decoded), and passes derived records to the three metric calculators.
/// Returns nil when called within `minimumInterval` of the previous refresh (debounced).
actor RefreshCoordinator {

    private var lastRefreshDate: Date = .distantPast
    private var parseCache = JSONLParseCache()
    let minimumInterval: TimeInterval
    private let projectsDir: URL?

    init(minimumInterval: TimeInterval = 5, projectsDir: URL? = nil) {
        self.minimumInterval = minimumInterval
        self.projectsDir = projectsDir
    }

    func refresh() async -> RefreshResult? {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshDate) >= minimumInterval else {
            return nil
        }
        lastRefreshDate = now

        let scan = JSONLParser.scanAllFiles(relativeTo: now, projectsDir: projectsDir)

        var relevantFiles = Set(scan.billingFiles).union(scan.weeklyFiles)
        if let mostRecent = scan.mostRecent { relevantFiles.insert(mostRecent) }
        parseCache.prune(keeping: relevantFiles)

        var recordsByFile: [URL: [SessionRecord]] = [:]
        for url in relevantFiles {
            recordsByFile[url] = parseCache.records(for: url)
        }

        let billingRecords = scan.billingFiles.flatMap { recordsByFile[$0] ?? [] }
        let weeklyRecords  = scan.weeklyFiles.flatMap { recordsByFile[$0] ?? [] }
        let mostRecentRecords = scan.mostRecent.flatMap { recordsByFile[$0] } ?? []

        let context = ContextWindowCalculator.calculate(mostRecentFile: scan.mostRecent, records: mostRecentRecords)
        let billing = BillingWindowCalculator.calculate(records: billingRecords)
        let weekly  = WeeklyUsageCalculator.calculate(records: weeklyRecords)

        return RefreshResult(context: context, billing: billing, weekly: weekly)
    }
}
