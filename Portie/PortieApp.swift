//
//  PortieApp.swift
//  Portie
//
//  Created by Tim Broddin on 05/02/2026.
//

import SwiftUI

@main
struct PortieApp: App {
    @State private var portMonitor = PortMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            PortMenuContent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "network")
                if portMonitor.activeCount > 0 {
                    Text("\(portMonitor.activeCount)")
                        .font(.caption2)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
