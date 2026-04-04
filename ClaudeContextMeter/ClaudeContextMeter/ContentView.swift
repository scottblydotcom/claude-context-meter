//
//  ContentView.swift
//  ClaudeContextMeter
//
//  Created by Scott Bly on 4/3/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        PopoverContentView()
    }
}

#Preview {
    ContentView()
        .environmentObject(MetricsViewModel())
}
