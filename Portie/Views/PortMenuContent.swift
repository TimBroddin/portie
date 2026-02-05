//
//  PortMenuContent.swift
//  Portie
//
//  Created by Tim Broddin on 05/02/2026.
//

import SwiftUI
import AppKit
import ServiceManagement

struct PortMenuContent: View {
    @State private var portStorage = PortStorage.shared
    @State private var portMonitor = PortMonitor.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if portStorage.ports.isEmpty {
                Text("No ports configured")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(portStorage.ports) { port in
                    PortMenuItem(
                        port: port,
                        status: portMonitor.statuses[port.port]
                    )
                }
            }

            Divider()
                .padding(.vertical, 4)

            HStack {
                Button("Add Port...") {
                    AddPortWindowController.shared.showWindow()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n")

                Spacer()

                Button {
                    portMonitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
                .keyboardShortcut("r")
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 4)

            Toggle("Open at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .padding(.horizontal)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }

            Divider()
                .padding(.vertical, 4)

            Button("Quit Portie") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .keyboardShortcut("q")
        }
        .padding(.vertical, 8)
        .frame(width: 280)
        .onAppear {
            portMonitor.start()
        }
    }
}

struct PortMenuItem: View {
    let port: Port
    let status: PortStatus?
    @State private var isHovering = false

    private var isRunning: Bool {
        status?.isRunning ?? false
    }

    private var statusColor: Color {
        isRunning ? .green : .gray
    }

    private func truncate(_ text: String, max: Int) -> String {
        if text.count > max {
            return String(text.prefix(max - 3)) + "..."
        }
        return text
    }

    private var processNameText: String {
        guard let name = status?.processName else { return "" }
        return truncate(name, max: 50)
    }

    private var titleText: String {
        guard let title = status?.pageTitle else { return "" }
        return truncate(title, max: 50)
    }

    private var portLabelText: String {
        let label = port.label ?? "Port"
        return "\(label) :\(port.port)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(portLabelText)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isRunning {
                    if !processNameText.isEmpty {
                        Text(processNameText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !titleText.isEmpty {
                        Text(titleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("(not running)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                if isRunning {
                    Button {
                        killProcess()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Kill process")
                }

                Button {
                    openInBrowser()
                } label: {
                    Image(systemName: "globe")
                }
                .buttonStyle(.plain)
                .help("Open in browser")

                Button {
                    PortStorage.shared.removePort(port.port)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from list")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: "http://localhost:\(port.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func killProcess() {
        KillConfirmationController.shared.showConfirmation(
            port: port.port,
            processName: status?.processName
        )
    }
}
