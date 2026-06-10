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
    @Published var weekly: WeeklyUsageMetrics?

    nonisolated(unsafe) private var fileWatcher: FileWatcher?
    nonisolated(unsafe) private var heartbeat: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let coordinator = RefreshCoordinator()
    // Tracked on the @MainActor to avoid capturing mutable locals in an escaping closure,
    // which is a Swift 6 strict-concurrency violation.
    private var lastPlan  = UserDefaults.standard.string(forKey: ClaudePlan.planKey)
    private var lastLimit = UserDefaults.standard.integer(forKey: BillingWindowCalculator.limitKey)

    init() {
        refresh()
        startWatching()
    }

    func refresh() {
        Task {
            guard let result = await coordinator.refresh() else { return }
            self.context = result.context
            self.billing = result.billing
            self.weekly  = result.weekly
        }
    }

    private func startWatching() {
        let projectsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
            .path

        fileWatcher = FileWatcher(paths: [projectsPath]) { [weak self] in
            self?.refresh()
        }
        fileWatcher?.start()

        // 60-second heartbeat as failsafe in case FSEvents misses an event.
        // FSEvents handles live updates; this is a backstop only.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }

        // Refresh when the user changes plan or token limit in Settings.
        // Filter to the two relevant keys to avoid spurious refreshes on every
        // unrelated UserDefaults write (e.g. other @AppStorage properties).
        // lastPlan/lastLimit are @MainActor properties — mutations are wrapped in
        // Task { @MainActor in } to satisfy Swift 6 strict concurrency.
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let currentPlan  = UserDefaults.standard.string(forKey: ClaudePlan.planKey)
                    let currentLimit = UserDefaults.standard.integer(forKey: BillingWindowCalculator.limitKey)
                    if currentPlan != self.lastPlan || currentLimit != self.lastLimit {
                        self.lastPlan  = currentPlan
                        self.lastLimit = currentLimit
                        self.refresh()
                    }
                }
            }
            .store(in: &cancellables)
    }
}
