//
//  ClaudeContextMeterApp.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import SwiftUI

@main
struct ClaudeContextMeterApp: App {

    /// True when running inside an XCTest host process (unit or UI tests). xcodebuild
    /// retries outlier-duration tests by launching a second test-host copy of the app
    /// while the first is still shutting down; without this check the single-instance
    /// guard below would see that first copy and self-terminate the retry, producing a
    /// spurious "test runner crashed before establishing connection" failure even though
    /// every real assertion passed.
    static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        guard !Self.isRunningUnderTests else { return }

        // Prevent multiple instances. If another copy is already running, quit immediately.
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            NSApp.terminate(nil)
        }
    }

    @StateObject private var viewModel = MetricsViewModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(viewModel)
        } label: {
            StatusBarView(
                contextFill: viewModel.context?.fillPercent ?? 0,
                billingFill: viewModel.billing?.fillPercent ?? 0
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
