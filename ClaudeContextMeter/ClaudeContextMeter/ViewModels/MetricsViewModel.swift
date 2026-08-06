//
//  MetricsViewModel.swift
//  ClaudeContextMeter
//

import SwiftUI
import Combine

extension Notification.Name {
    /// Posted by SettingsView when the Settings window closes. SettingsView lives in a separate
    /// Settings scene with no reference to the shared MetricsViewModel, so this decouples the
    /// "user changed a setting, refresh the meter" signal across scenes.
    static let settingsDidClose = Notification.Name("com.scottbly.ClaudeContextMeter.settingsDidClose")
}

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
    private var lastPlan    = AppPreferences.store.string(forKey: ClaudePlan.planKey)
    private var lastLimit   = AppPreferences.store.integer(forKey: BillingWindowCalculator.limitKey)
    private var lastWeekday = AppPreferences.store.integer(forKey: WeeklyUsageCalculator.weekdayKey)
    private var lastHour    = AppPreferences.store.integer(forKey: WeeklyUsageCalculator.hourKey)

    init() {
        refresh()
        startWatching()
    }

    /// - Parameter force: Pass `true` only for user-initiated settings changes. The automatic
    ///   paths (FSEvents, heartbeat) must stay debounced, but a settings change that lands inside
    ///   the debounce window would otherwise be dropped and never retried, leaving the meter on
    ///   the old plan or limit until the next heartbeat (claude-context-meter-dxw).
    func refresh(force: Bool = false) {
        Task {
            guard let result = await coordinator.refresh(force: force) else { return }
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

        // Refresh when the user changes plan, token limit, or the weekly reset schedule in
        // Settings. Filter to the relevant keys to avoid spurious refreshes on every unrelated
        // UserDefaults write (e.g. other @AppStorage properties). The tracked lastX values are
        // @MainActor properties — mutations are wrapped in Task { @MainActor in } to satisfy
        // Swift 6 strict concurrency.
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    let currentPlan    = AppPreferences.store.string(forKey: ClaudePlan.planKey)
                    let currentLimit   = AppPreferences.store.integer(forKey: BillingWindowCalculator.limitKey)
                    let currentWeekday = AppPreferences.store.integer(forKey: WeeklyUsageCalculator.weekdayKey)
                    let currentHour    = AppPreferences.store.integer(forKey: WeeklyUsageCalculator.hourKey)
                    if currentPlan != self.lastPlan || currentLimit != self.lastLimit
                        || currentWeekday != self.lastWeekday || currentHour != self.lastHour {
                        self.lastPlan    = currentPlan
                        self.lastLimit   = currentLimit
                        self.lastWeekday = currentWeekday
                        self.lastHour    = currentHour
                        // Forced: the lastX values above are already updated, so this observer
                        // will not fire again for the same change. A debounced refresh here is
                        // lost permanently, not merely delayed.
                        self.refresh(force: true)
                    }
                }
            }
            .store(in: &cancellables)

        // Deterministic refresh when the Settings window closes. The didChange observer above
        // is a best-effort live path, but it doesn't reliably fire for the @AppStorage picker
        // writes in the separate Settings scene, so closing Settings always re-reads the meter.
        // Forced: this notification fires once, so a debounced refresh here is dropped for good.
        NotificationCenter.default
            .publisher(for: .settingsDidClose)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh(force: true) }
            }
            .store(in: &cancellables)
    }
}
