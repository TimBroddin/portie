//
//  PortlessService.swift
//  Portie
//
//  Created by Claude on 22/02/2026.
//

import Foundation
import Observation

struct PortlessRoute: Equatable {
    let hostname: String
    let port: Int
    let pid: Int
}

struct PortlessProxyStatus: Equatable {
    let isRunning: Bool
    let port: Int
    let isTLS: Bool
}

@MainActor
@Observable
final class PortlessService {
    static let shared = PortlessService()

    private(set) var routes: [PortlessRoute] = []
    private(set) var proxyStatus: PortlessProxyStatus?

    private init() {}

    /// Reload portless routes and proxy status from disk
    func refresh() {
        routes = loadRoutes()
        proxyStatus = loadProxyStatus()
    }

    /// Look up the portless hostname for a given port number
    func hostname(for port: Int) -> String? {
        routes.first(where: { $0.port == port })?.hostname
    }

    /// Build the full portless URL for a given port number
    func url(for port: Int) -> URL? {
        guard let hostname = hostname(for: port),
              let proxy = proxyStatus, proxy.isRunning else {
            return nil
        }
        let scheme = proxy.isTLS ? "https" : "http"
        return URL(string: "\(scheme)://\(hostname):\(proxy.port)")
    }

    // MARK: - Private

    private func stateDirectories() -> [String] {
        var dirs: [String] = []
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            dirs.append("\(home)/.portless")
        }
        dirs.append("/tmp/portless")
        return dirs
    }

    /// Find the first existing portless state directory
    private func activeStateDirectory() -> String? {
        for dir in stateDirectories() {
            if FileManager.default.fileExists(atPath: "\(dir)/routes.json") {
                return dir
            }
        }
        return nil
    }

    private func loadRoutes() -> [PortlessRoute] {
        var allRoutes: [PortlessRoute] = []

        for dir in stateDirectories() {
            let path = "\(dir)/routes.json"
            guard let data = FileManager.default.contents(atPath: path) else { continue }

            guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                continue
            }

            for entry in jsonArray {
                guard let hostname = entry["hostname"] as? String,
                      let port = entry["port"] as? Int,
                      let pid = entry["pid"] as? Int else {
                    continue
                }

                // Check if the process is still alive
                if kill(Int32(pid), 0) != 0 {
                    continue
                }

                allRoutes.append(PortlessRoute(hostname: hostname, port: port, pid: pid))
            }
        }

        return allRoutes
    }

    private func loadProxyStatus() -> PortlessProxyStatus? {
        guard let dir = activeStateDirectory() else { return nil }

        // Read proxy PID
        let pidPath = "\(dir)/proxy.pid"
        guard let pidData = FileManager.default.contents(atPath: pidPath),
              let pidString = String(data: pidData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidString) else {
            return nil
        }

        // Check if proxy process is alive
        let isRunning = kill(pid, 0) == 0

        // Read proxy port (default 1355)
        var proxyPort = 1355
        let portPath = "\(dir)/proxy.port"
        if let portData = FileManager.default.contents(atPath: portPath),
           let portString = String(data: portData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let port = Int(portString) {
            proxyPort = port
        }

        // Check TLS mode
        let isTLS = FileManager.default.fileExists(atPath: "\(dir)/proxy.tls")

        return PortlessProxyStatus(isRunning: isRunning, port: proxyPort, isTLS: isTLS)
    }
}
