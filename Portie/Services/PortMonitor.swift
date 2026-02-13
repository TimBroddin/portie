//
//  PortMonitor.swift
//  Portie
//
//  Created by Tim Broddin on 05/02/2026.
//

import Foundation
import Observation

struct PortStatus: Equatable {
    let port: Int
    let isRunning: Bool
    let pid: Int?
    let processName: String?
    let pageTitle: String?

    var displayName: String {
        if !isRunning {
            return "(not running)"
        }
        var parts: [String] = []
        if let name = processName {
            parts.append(name)
        }
        if let title = pageTitle {
            parts.append(title)
        }
        return parts.isEmpty ? "(running)" : parts.joined(separator: " · ")
    }
}

struct DiscoveredPort: Equatable, Identifiable {
    var id: Int { port }
    let port: Int
    let pid: Int
    let processName: String
}

@MainActor
@Observable
final class PortMonitor {
    static let shared = PortMonitor()

    private(set) var statuses: [Int: PortStatus] = [:]
    private(set) var discoveredPorts: [DiscoveredPort] = []
    private var timer: Timer?
    private let refreshInterval: TimeInterval = 15.0

    private init() {}

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let ports = PortStorage.shared.ports
        for port in ports {
            Task {
                let status = await checkPort(port.port)
                statuses[port.port] = status
            }
        }
        Task {
            await discoverOpenPorts()
        }
    }

    var activeCount: Int {
        statuses.values.filter { $0.isRunning }.count
    }

    private func discoverOpenPorts() async {
        let monitoredPortNumbers = Set(PortStorage.shared.ports.map { $0.port })
        let allListening = await getAllListeningPorts()
        discoveredPorts = allListening
            .filter { !monitoredPortNumbers.contains($0.port) }
            .sorted { $0.port < $1.port }
    }

    private func getAllListeningPorts() async -> [DiscoveredPort] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                process.arguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(returning: [])
                        return
                    }

                    var seen = Set<Int>()
                    var results: [(port: Int, pid: Int)] = []

                    for line in output.split(separator: "\n").dropFirst() { // skip header
                        let columns = line.split(separator: " ", omittingEmptySubsequences: true)
                        guard columns.count >= 9 else { continue }

                        guard let pid = Int(columns[1]) else { continue }

                        // Parse port from the NAME column (e.g. "*:3000" or "127.0.0.1:8080")
                        let nameCol = String(columns[8])
                        guard let colonIndex = nameCol.lastIndex(of: ":"),
                              let port = Int(nameCol[nameCol.index(after: colonIndex)...]) else {
                            continue
                        }

                        // Skip system/low ports and already seen ports
                        guard port >= 1024, !seen.contains(port) else { continue }
                        seen.insert(port)

                        results.append((port: port, pid: pid))
                    }

                    // Resolve full process names via ps
                    let discovered = results.compactMap { entry -> DiscoveredPort? in
                        let psProcess = Process()
                        psProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
                        psProcess.arguments = ["-p", "\(entry.pid)", "-o", "comm="]

                        let psPipe = Pipe()
                        psProcess.standardOutput = psPipe
                        psProcess.standardError = FileHandle.nullDevice

                        do {
                            try psProcess.run()
                            psProcess.waitUntilExit()
                        } catch {
                            return nil
                        }

                        let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
                        let name = String(data: psData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .split(separator: "/").last
                            .map(String.init) ?? "unknown"

                        return DiscoveredPort(port: entry.port, pid: entry.pid, processName: name)
                    }

                    continuation.resume(returning: discovered)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func checkPort(_ port: Int) async -> PortStatus {
        let processInfo = await getProcessInfo(port: port)

        guard let (pid, processName) = processInfo else {
            return PortStatus(port: port, isRunning: false, pid: nil, processName: nil, pageTitle: nil)
        }

        let pageTitle = await fetchPageTitle(port: port)

        return PortStatus(port: port, isRunning: true, pid: pid, processName: processName, pageTitle: pageTitle)
    }

    private func getProcessInfo(port: Int) async -> (pid: Int, name: String)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                process.arguments = ["-i", ":\(port)", "-sTCP:LISTEN", "-n", "-P", "-t"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let pid = Int(output.split(separator: "\n").first ?? "") else {
                        continuation.resume(returning: nil)
                        return
                    }

                    // Get process name from pid
                    let psProcess = Process()
                    psProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
                    psProcess.arguments = ["-p", "\(pid)", "-o", "comm="]

                    let psPipe = Pipe()
                    psProcess.standardOutput = psPipe
                    psProcess.standardError = FileHandle.nullDevice

                    try psProcess.run()
                    psProcess.waitUntilExit()

                    let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
                    let processName = String(data: psData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: "/").last
                        .map(String.init) ?? "unknown"

                    continuation.resume(returning: (pid, processName))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func fetchPageTitle(port: Int) async -> String? {
        guard let url = URL(string: "http://localhost:\(port)/") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Simple regex to extract title
            if let titleRange = html.range(of: "<title>.*?</title>", options: .regularExpression, range: nil, locale: nil) {
                var title = String(html[titleRange])
                title = title.replacingOccurrences(of: "<title>", with: "")
                title = title.replacingOccurrences(of: "</title>", with: "")
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
            return nil
        } catch {
            return nil
        }
    }

    func killProcess(port: Int) async -> Bool {
        guard let status = statuses[port], let pid = status.pid else { return false }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["\(pid)"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
