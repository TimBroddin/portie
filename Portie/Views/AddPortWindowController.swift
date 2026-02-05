//
//  AddPortWindowController.swift
//  Portie
//
//  Created by Tim Broddin on 05/02/2026.
//

import AppKit
import SwiftUI

@MainActor
final class AddPortWindowController {
    static let shared = AddPortWindowController()

    private var window: NSWindow?

    private init() {}

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let addPortView = AddPortWindowView {
            self.closeWindow()
        }

        let hostingController = NSHostingController(rootView: addPortView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Add Port"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 300, height: 180))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

struct AddPortWindowView: View {
    let onDismiss: () -> Void

    @State private var portText = ""
    @State private var label = ""
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Port Number")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g., 3000", text: $portText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Label (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g., Frontend", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            if showError {
                Text("Please enter a valid port (1-65535)")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.escape)

                Button("Add") {
                    addPort()
                }
                .keyboardShortcut(.return)
                .disabled(portText.isEmpty)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func addPort() {
        guard let port = Int(portText), port >= 1, port <= 65535 else {
            showError = true
            return
        }

        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        PortStorage.shared.addPort(port, label: trimmedLabel.isEmpty ? nil : trimmedLabel)
        PortMonitor.shared.refresh()
        onDismiss()
    }
}
