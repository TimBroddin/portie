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
        let dirs = Self.stateDirectories()
        Task.detached {
            let routes = Self.loadRoutes(from: dirs)
            let proxyStatus = Self.loadProxyStatus(from: dirs)
            await MainActor.run { [weak self] in
                self?.routes = routes
                self?.proxyStatus = proxyStatus
            }
        }
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

    nonisolated private static func stateDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".portless").path
        return [home, "/tmp/portless"]
    }

    nonisolated private static func isProcessAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        // EPERM means the process exists but we lack permission — still alive
        return errno == EPERM
    }

    nonisolated private static func loadRoutes(from dirs: [String]) -> [PortlessRoute] {
        var allRoutes: [PortlessRoute] = []

        for dir in dirs {
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

                guard let pid32 = Int32(exactly: pid), isProcessAlive(pid32) else { continue }

                allRoutes.append(PortlessRoute(hostname: hostname, port: port, pid: pid))
            }
        }

        return allRoutes
    }

    nonisolated private static func loadProxyStatus(from dirs: [String]) -> PortlessProxyStatus? {
        for dir in dirs {
            let pidPath = "\(dir)/proxy.pid"
            guard let pidData = FileManager.default.contents(atPath: pidPath),
                  let pidString = String(data: pidData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let pid = Int32(pidString) else {
                continue
            }

            let isRunning = isProcessAlive(pid)
            if !isRunning { continue }

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

            return PortlessProxyStatus(isRunning: true, port: proxyPort, isTLS: isTLS)
        }

        return nil
    }
}
