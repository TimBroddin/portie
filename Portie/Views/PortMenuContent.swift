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
    @State private var portlessService = PortlessService.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let proxy = portlessService.proxyStatus, proxy.isRunning {
                PortlessProxyBadge(status: proxy)

                if !portlessService.routes.isEmpty {
                    ForEach(portlessService.routes, id: \.hostname) { route in
                        PortlessRouteMenuItem(route: route, proxyStatus: proxy)
                    }
                }

                Divider()
                    .padding(.vertical, 4)
            }

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
                .padding(.vertical, 8)
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
        if let hostname = status?.portlessHostname {
            return hostname
        }
        let label = port.label ?? "Port"
        return "\(label) :\(port.port)"
    }

    private var portSubLabel: String? {
        if status?.portlessHostname != nil {
            let label = port.label ?? "Port"
            return "\(label) :\(port.port)"
        }
        return nil
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
                if let sub = portSubLabel {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
                    copyURL()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isRunning ? "Copy URL" : "Copy URL (not running)")

                Button {
                    openInBrowser()
                } label: {
                    Image(systemName: "globe")
                        .foregroundStyle(isRunning ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(isRunning ? "Open in browser" : "Open in browser (not running)")

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

    private var bestURL: URL {
        if let portlessURL = PortlessService.shared.url(for: port.port) {
            return portlessURL
        }
        return URL(string: "http://localhost:\(port.port)")!
    }

    private func openInBrowser() {
        NSWorkspace.shared.open(bestURL)
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bestURL.absoluteString, forType: .string)
    }

    private func killProcess() {
        KillConfirmationController.shared.showConfirmation(
            port: port.port,
            processName: status?.processName
        )
    }
}

struct PortlessRouteMenuItem: View {
    let route: PortlessRoute
    let proxyStatus: PortlessProxyStatus
    @State private var isHovering = false

    private var url: URL {
        let scheme = proxyStatus.isTLS ? "https" : "http"
        return URL(string: "\(scheme)://\(route.hostname):\(proxyStatus.port)")!
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(route.hostname)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: "localhost:\(route.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy URL")

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "globe")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Open in browser")
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
}

struct PortlessProxyBadge: View {
    let status: PortlessProxyStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.blue)
                .frame(width: 6, height: 6)
            Text("Portless")
                .font(.caption)
                .fontWeight(.medium)
            Text(verbatim: ":\(status.port)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if status.isTLS {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

