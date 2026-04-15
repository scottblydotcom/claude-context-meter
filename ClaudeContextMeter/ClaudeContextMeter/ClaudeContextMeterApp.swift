//
//  ClaudeContextMeterApp.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import SwiftUI

@main
struct ClaudeContextMeterApp: App {

    init() {
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
    }
}
