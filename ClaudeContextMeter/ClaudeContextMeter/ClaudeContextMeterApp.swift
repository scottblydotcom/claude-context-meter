//
//  ClaudeContextMeterApp.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import SwiftUI

@main
struct ClaudeContextMeterApp: App {
    var body: some Scene {
        MenuBarExtra("CCM", systemImage: "chart.bar.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
