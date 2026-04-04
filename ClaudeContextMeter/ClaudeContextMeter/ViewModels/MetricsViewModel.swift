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

    nonisolated(unsafe) private var fileWatcher: FileWatcher?
    nonisolated(unsafe) private var heartbeat: Timer?

    init() {
        refresh()
        startWatching()
    }

    func refresh() {
        context = ContextWindowCalculator.calculate()
        billing = BillingWindowCalculator.calculate()
    }

    private func startWatching() {
        let projectsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
            .path

        fileWatcher = FileWatcher(paths: [projectsPath]) { [weak self] in
            self?.refresh()
        }
        fileWatcher?.start()

        // 30-second heartbeat as fallback in case FSEvents misses an event
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

}
