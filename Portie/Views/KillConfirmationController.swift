//
//  KillConfirmationController.swift
//  Portie
//
//  Created by Tim Broddin on 05/02/2026.
//

import AppKit
import SwiftUI

@MainActor
final class KillConfirmationController {
    static let shared = KillConfirmationController()

    private init() {}

    func showConfirmation(port: Int, processName: String?) {
        let alert = NSAlert()
        alert.messageText = "Kill Process?"
        alert.informativeText = "This will terminate \(processName ?? "the process") on port \(port)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            Task {
                let success = await PortMonitor.shared.killProcess(port: port)
                if success {
                    try? await Task.sleep(for: .milliseconds(500))
                    PortMonitor.shared.refresh()
                }
            }
        }
    }
}
