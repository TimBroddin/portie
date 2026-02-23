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
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 320, height: 320))
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

enum AddPortTab: String, CaseIterable {
    case discovered = "Discovered"
    case manual = "Manual"
}

struct AddPortWindowView: View {
    let onDismiss: () -> Void

    @State private var selectedTab: AddPortTab = .discovered

    var body: some View {
        VStack(spacing: 0) {
            // Custom toolbar header
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Add Port")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.top, 16)

                Picker("", selection: $selectedTab) {
                    ForEach(AddPortTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .background(.bar)

            Divider()

            switch selectedTab {
            case .manual:
                ManualAddPortView(onDismiss: onDismiss)
            case .discovered:
                DiscoveredPortsView(onDismiss: onDismiss)
            }
        }
        .frame(width: 300)
    }
}

struct ManualAddPortView: View {
    let onDismiss: () -> Void

    @State private var portText = ""
    @State private var label = ""
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Port Number")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g., 3000", text: $portText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
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

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.escape)

                Button("Add") {
                    addPort()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(portText.isEmpty)
            }
        }
        .padding(20)
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

struct DiscoveredPortsView: View {
    let onDismiss: () -> Void

    @State private var portMonitor = PortMonitor.shared

    var body: some View {
        Group {
            if portMonitor.discoveredPorts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No open ports found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 180)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(portMonitor.discoveredPorts) { discovered in
                            DiscoveredPortRow(discovered: discovered)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180)
            }
        }
        .onAppear {
            portMonitor.refresh()
        }
    }
}

struct DiscoveredPortRow: View {
    let discovered: DiscoveredPort
    @State private var isHovering = false
    @State private var added = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: ":\(discovered.port)")
                    .font(.system(.body, weight: .medium).monospaced())
                Text(discovered.processName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if added {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.medium)
            } else {
                Button {
                    PortStorage.shared.addPort(discovered.port, label: discovered.processName)
                    PortMonitor.shared.refresh()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        added = true
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(isHovering ? .primary : .secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Add to monitored ports")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
